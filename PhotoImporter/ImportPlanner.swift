import Foundation

actor ImportPlanner {
    // A small seam to test insufficient/unknown capacity and filesystem name rules on real directories.
    private let volumeReader: @Sendable (URL) throws -> LibraryVolumeInfo

    init(volumeReader: @escaping @Sendable (URL) throws -> LibraryVolumeInfo = LibraryVolumeInfo.read) {
        self.volumeReader = volumeReader
    }

    func plan(source: URL, library: URL, captures: [PhotoCapture], format: PhotoFormatFilter, event input: String, organization: FolderOrganization = FolderOrganization()) throws -> ImportPlan {
        try Task.checkCancellation()
        let readingSource = source.startAccessingSecurityScopedResource()
        let readingLibrary = library.startAccessingSecurityScopedResource()
        defer {
            if readingSource { source.stopAccessingSecurityScopedResource() }
            if readingLibrary { library.stopAccessingSecurityScopedResource() }
        }
        let source = source.standardizedFileURL
        let library = library.standardizedFileURL
        var blockers: [String] = []
        var notes: [String] = []
        var sourceUsable = true
        var libraryUsable = true
        do { try PlanningPaths.validateRoot(source) }
        catch { sourceUsable = false; blockers.append(L10n.text("Source unavailable: %@", String(describing: error.localizedDescription))) }
        do { try PlanningPaths.validateRoot(library) }
        catch { libraryUsable = false; blockers.append(L10n.text("Archive unavailable or without read permission: %@", String(describing: error.localizedDescription))) }
        if sourceUsable && libraryUsable && PlanningPaths.rootsOverlap(source, library) {
            libraryUsable = false
            blockers.append(L10n.text("The source and archive must be different folders and cannot contain each other."))
        }

        var event = ""
        var eventValid = true
        do { event = try ImportNaming.eventName(input) }
        catch { eventValid = false; blockers.append(error.localizedDescription) }

        var volume: LibraryVolumeInfo?
        if libraryUsable {
            do { volume = try volumeReader(library) }
            catch { notes.append(L10n.text("Could not read volume properties: %@", String(describing: error.localizedDescription))) }
            if volume?.isReadOnly == true { blockers.append(L10n.text("The archive volume is read-only.")) }
            if volume?.isReadOnly == nil { notes.append(L10n.text("Could not confirm whether the volume allows writing.")) }
            if volume?.isCaseSensitive == nil {
                notes.append(L10n.text("Case sensitivity is unknown. Equivalent names will be treated as conflicts."))
            }
        }

        var paths = PlanningPaths(caseSensitive: volume?.isCaseSensitive ?? false)
        var files: [PlannedFile] = []
        var estimatedBytes: Int64 = 0
        for capture in captures {
            for file in capture.files where format.includes(file) {
                try Task.checkCancellation()
                let sum = estimatedBytes.addingReportingOverflow(file.byteCount)
                if file.byteCount < 0 || sum.overflow {
                    throw PlanningError.message(L10n.text("Invalid total size. Scan the source again."))
                }
                estimatedBytes = sum.partialValue
                let date = capture.captureDate
                var destination: String?
                var state: PlannedFileState = .newFile
                var snapshot: FileSnapshot?
                do {
                    guard eventValid else { throw PlanningError.message(L10n.text("Correct the event name.")) }
                    guard let date else { throw PlanningError.message(L10n.text("This photo has no valid date. Deselect it to continue.")) }
                    destination = try ImportNaming.relativeDestination(file: file, day: date.timestamp.day, event: event, organization: organization)
                    guard sourceUsable, libraryUsable else { throw PlanningError.message(L10n.text("The source or archive could not be validated.")) }
                    try PlanningPaths.validateSource(file, root: source)
                    snapshot = try PlanningPaths.node(at: file.url)?.snapshot
                    state = try paths.inspectDestination(destination!, root: library)
                } catch is CancellationError {
                    throw CancellationError()
                } catch {
                    state = .blocked(error.localizedDescription)
                }
                files.append(PlannedFile(source: file, captureID: capture.id, relativeDestination: destination, date: date, state: state, sourceSnapshot: snapshot))
            }
        }

        let collisionGroups = Dictionary(grouping: files.indices.filter { files[$0].relativeDestination != nil }) {
            ImportNaming.key(files[$0].relativeDestination!, caseSensitive: volume?.isCaseSensitive ?? false)
        }
        for indices in collisionGroups.values where indices.count > 1 {
            for index in indices {
                files[index].state = .blocked(L10n.text("Selected files conflict: multiple source files have the same destination. Deselect the conflicting files."))
            }
        }
        if files.isEmpty { blockers.append(L10n.text("Select at least one photo with eligible files.")) }
        if libraryUsable {
            if let available = volume?.availableBytes, available >= 0 {
                if estimatedBytes > available { blockers.append(L10n.text("Not enough space for the estimated selection size.")) }
            } else { blockers.append(L10n.text("Available space could not be verified.")) }
        }
        if files.contains(where: { $0.date?.source.isFallback == true }) {
            notes.append(L10n.text("Some folders use fallback dates. Review dates and their sources in the file details."))
        }
        notes.append(L10n.text("The estimate includes existing files until their content is verified. Space, permissions and paths are checked again before copying; no space has been reserved."))
        notes.append(L10n.text("Write access has not yet been tested. This step only reads the source and archive."))
        try Task.checkCancellation()
        return ImportPlan(sourceRoot: source, libraryRoot: library, event: event, files: files,
                          estimatedBytes: estimatedBytes, volume: volume, blockers: blockers, notes: notes,
                          sourceIdentity: try? PlanningPaths.node(at: source)?.snapshot.identity,
                          libraryIdentity: try? PlanningPaths.node(at: library)?.snapshot.identity,
                          sourceVolumeID: try? source.resourceValues(forKeys: [.volumeUUIDStringKey]).volumeUUIDString,
                          libraryVolumeID: volume?.identifier)
    }
}
