import Foundation
import Darwin

enum HistoryRoots {
    static func validate(_ root: URL, recordedPath: String, identity: FileIdentity?, volumeID: String?, strict: Bool = true) throws {
        guard try PlanningPaths.node(at: root)?.kind == .directory else {
            throw PlanningError.message(L10n.text("The confirmed folder is missing, is a link or is not a folder."))
        }
        let descriptor = try SafeImportFiles.root(root)
        let actual = try SafeImportFiles.snapshot(descriptor, directory: true).identity
        if let volumeID {
            let current = try root.resourceValues(forKeys: [.volumeUUIDStringKey]).volumeUUIDString
            guard current == volumeID else { throw PlanningError.message(L10n.text("The confirmed folder belongs to another volume or its identity could not be confirmed.")) }
        }
        if let identity {
            guard identity.inode == actual.inode, volumeID != nil || identity.device == actual.device else {
                throw PlanningError.message(L10n.text("The confirmed folder is not the one recorded for this import."))
            }
        } else {
            guard !strict, root.resolvingSymlinksInPath().standardizedFileURL == URL(fileURLWithPath: recordedPath).resolvingSymlinksInPath().standardizedFileURL else {
                throw PlanningError.message(L10n.text("The older record lacks sufficient identity information for this action. Scan the source again."))
            }
        }
    }

    static func snapshotMatches(_ actual: FileSnapshot, _ expected: FileSnapshot, volumeID: String?) -> Bool {
        actual.identity.inode == expected.identity.inode && (volumeID != nil || actual.identity.device == expected.identity.device) &&
        actual.size == expected.size && actual.modifiedSeconds == expected.modifiedSeconds &&
        actual.modifiedNanos == expected.modifiedNanos && actual.changedSeconds == expected.changedSeconds &&
        actual.changedNanos == expected.changedNanos &&
        (expected.createdSeconds == nil || (actual.createdSeconds == expected.createdSeconds && actual.createdNanos == expected.createdNanos))
    }
}

extension ImportService {
    func historyList() throws -> JournalListing { try journal.list() }

    func reconcile(_ id: UUID, library: URL) throws -> [HistoryFileCheck] {
        let record = try journal.load(id)
        try checkJournalSeparation(record, source: nil, library: library)
        let lease = try journal.lock(id)
        defer { lease.unlock() }
        let access = library.startAccessingSecurityScopedResource()
        defer { if access { library.stopAccessingSecurityScopedResource() } }
        try validateLibrary(library, record: record, strict: false)
        let root = try SafeImportFiles.root(library)
        let sensitive = try volumeReader(library).isCaseSensitive ?? false
        return try checkFiles(record, library: library, root: root, caseSensitive: sensitive)
    }

    private func checkFiles(_ record: ImportRecord, library: URL, root: ImportDescriptor, caseSensitive: Bool) throws -> [HistoryFileCheck] {
        var checks: [HistoryFileCheck] = []
        let hashes = referenceHashes(record)
        for file in record.files {
            try Task.checkCancellation()
            do {
                try validateLibrary(library, record: record, strict: false)
                guard let current = try SafeImportFiles.hash(relative: file.destinationRelativePath, in: root, caseSensitive: caseSensitive) else {
                    checks.append(HistoryFileCheck(id: file.id, state: .missing, message: L10n.text("The recorded path does not exist at the destination.")))
                    continue
                }
                try validateLibrary(library, record: record, strict: false)
                guard let expected = hashes[file.id] else {
                    checks.append(HistoryFileCheck(id: file.id, state: .unknown, message: L10n.text("The file exists, but this operation did not record a SHA-256 checksum. Presence alone does not prove an intact import.")))
                    continue
                }
                let valid = current.snapshot.size == file.byteCount && current.sha256 == expected
                checks.append(HistoryFileCheck(id: file.id, state: valid ? .verified : .different,
                                              message: valid ? (file.sha256 == nil ? L10n.text("Size and SHA-256 verified now using a linked recovery record.") : L10n.text("Size and SHA-256 verified now.")) : L10n.text("The current file does not match the recorded content.")))
            } catch is CancellationError { throw CancellationError() }
            catch { checks.append(HistoryFileCheck(id: file.id, state: .unavailable, message: error.localizedDescription)) }
        }
        return checks
    }

    private func referenceHashes(_ record: ImportRecord) -> [String: String] {
        let records = (try? journal.list().entries.map(\.record)) ?? []
        func resolve(_ parent: ImportRecord, visited: Set<UUID>) -> [String: String] {
            guard !visited.contains(parent.id), visited.count < 64 else { return [:] }
            var visited = visited
            visited.insert(parent.id)
            var hashes = Dictionary(uniqueKeysWithValues: parent.files.compactMap { file in file.sha256.map { (file.id, $0) } })
            for child in records where child.recoveryOf == parent.id {
                guard let sourceID = parent.sourceIdentity, let libraryID = parent.libraryIdentity,
                      child.sourceIdentity?.inode == sourceID.inode, child.libraryIdentity?.inode == libraryID.inode,
                      child.sourceVolumeID == parent.sourceVolumeID, child.libraryVolumeID == parent.libraryVolumeID,
                      parent.sourceVolumeID != nil || child.sourceIdentity == sourceID,
                      parent.libraryVolumeID != nil || child.libraryIdentity == libraryID else { continue }
                let childHashes = resolve(child, visited: visited)
                for file in parent.files where hashes[file.id] == nil {
                    guard let old = file.sourceSnapshot,
                          let receipt = child.files.first(where: { $0.sourceRelativePath == file.sourceRelativePath &&
                              $0.destinationRelativePath == file.destinationRelativePath && $0.byteCount == file.byteCount }),
                          let source = receipt.sourceSnapshot, let hash = childHashes[receipt.id],
                          HistoryRoots.snapshotMatches(source, old, volumeID: parent.sourceVolumeID) else { continue }
                    hashes[file.id] = hash
                }
            }
            return hashes
        }
        return resolve(record, visited: [])
    }

    func prepareRecovery(_ id: UUID, source: URL, library: URL) throws -> ImportPlan {
        let record = try journal.load(id)
        try checkJournalSeparation(record, source: source, library: library)
        let lease = try journal.lock(id)
        defer { lease.unlock() }
        let sourceAccess = source.startAccessingSecurityScopedResource()
        let libraryAccess = library.startAccessingSecurityScopedResource()
        defer {
            if sourceAccess { source.stopAccessingSecurityScopedResource() }
            if libraryAccess { library.stopAccessingSecurityScopedResource() }
        }
        try HistoryRoots.validate(source, recordedPath: record.sourceRootPath, identity: record.sourceIdentity, volumeID: record.sourceVolumeID)
        try validateLibrary(library, record: record)
        guard !PlanningPaths.rootsOverlap(source, library) else { throw PlanningError.message(L10n.text("The source and archive overlap.")) }
        let sourceRoot = try SafeImportFiles.root(source)
        let libraryRoot = try SafeImportFiles.root(library)
        let volume = try volumeReader(library)
        let sensitive = volume.isCaseSensitive ?? false
        let checks = try checkFiles(record, library: library, root: libraryRoot, caseSensitive: sensitive)
        let intact = Set(checks.filter { $0.state == .verified }.map(\.id))
        let references = referenceHashes(record)
        var paths = PlanningPaths(caseSensitive: sensitive)
        var items: [PlannedFile] = []
        var total: Int64 = 0
        var missingBytes: Int64 = 0
        for file in record.files where !intact.contains(file.id) {
            try Task.checkCancellation()
            let url = source.appendingPathComponent(file.sourceRelativePath)
            guard let format = PhotoFormat(extension: url.pathExtension) else { throw PlanningError.message(L10n.text("Unknown format in the record.")) }
            let photo = PhotoFile(url: url, relativePath: file.sourceRelativePath, format: format, byteCount: file.byteCount)
            var state: PlannedFileState = .newFile
            var snapshot: FileSnapshot?
            var expectedSHA: String?
            do {
                guard let current = try SafeImportFiles.hash(relative: file.sourceRelativePath, in: sourceRoot, caseSensitive: true) else {
                    throw PlanningError.message(L10n.text("The source for this file is missing."))
                }
                guard current.snapshot.size == file.byteCount else { throw PlanningError.message(L10n.text("The source size has changed since the recorded operation.")) }
                if let old = file.sourceSnapshot {
                    guard HistoryRoots.snapshotMatches(current.snapshot, old, volumeID: record.sourceVolumeID) else {
                        throw PlanningError.message(L10n.text("The source has changed since the interrupted import. Scan the source again."))
                    }
                } else if references[file.id] == nil {
                    throw PlanningError.message(L10n.text("This older record lacks source identity or checksum information. Scan this file again."))
                }
                guard references[file.id] == nil || references[file.id] == current.sha256 else { throw PlanningError.message(L10n.text("The source content differs from the record.")) }
                snapshot = current.snapshot
                expectedSHA = current.sha256
                state = try paths.inspectDestination(file.destinationRelativePath, root: library)
                if state == .existing {
                    guard let existing = try SafeImportFiles.hash(relative: file.destinationRelativePath, in: libraryRoot, caseSensitive: sensitive),
                          existing.sha256 == current.sha256, existing.snapshot.size == current.snapshot.size else {
                        throw PlanningError.message(L10n.text("Conflict: the existing file differs from the source. It will be preserved."))
                    }
                }
                if state == .newFile { missingBytes = try checkedSum(missingBytes, file.byteCount) }
            } catch is CancellationError { throw CancellationError() }
            catch { state = .blocked(error.localizedDescription) }
            total = try checkedSum(total, file.byteCount)
            items.append(PlannedFile(source: photo, captureID: (file.sourceRelativePath as NSString).deletingPathExtension,
                                     relativeDestination: file.destinationRelativePath, date: nil, state: state,
                                     sourceSnapshot: snapshot, expectedSHA256: expectedSHA))
        }
        var blockers: [String] = []
        if items.isEmpty { blockers.append(L10n.text("All files from this operation are intact at the destination. No copy is needed.")) }
        if volume.isReadOnly != false { blockers.append(L10n.text("The volume does not allow writing or its state could not be confirmed.")) }
        if let available = volume.availableBytes, available >= missingBytes {} else { blockers.append(L10n.text("Insufficient or unknown space for recovery.")) }
        let groups = Dictionary(grouping: items.indices) { ImportNaming.key(items[$0].relativeDestination!, caseSensitive: sensitive) }
        for indices in groups.values where indices.count > 1 {
            for index in indices { items[index].state = .blocked(L10n.text("The record contains conflicting equivalent destinations.")) }
        }
        try HistoryRoots.validate(source, recordedPath: record.sourceRootPath, identity: record.sourceIdentity, volumeID: record.sourceVolumeID)
        try validateLibrary(library, record: record)
        return ImportPlan(sourceRoot: source, libraryRoot: library, event: "", files: items, estimatedBytes: total,
                          volume: volume, blockers: blockers,
                          notes: [L10n.text("Resuming operation %@. Original destination paths are preserved.", String(describing: id.uuidString)),
                                  L10n.text("%@ intact files were verified and excluded from the new copy. The previous operation remains in history.", String(describing: intact.count))],
                          sourceIdentity: try SafeImportFiles.snapshot(sourceRoot, directory: true).identity,
                          libraryIdentity: try SafeImportFiles.snapshot(libraryRoot, directory: true).identity,
                          sourceVolumeID: record.sourceVolumeID, libraryVolumeID: volume.identifier, recoveryOf: id)
    }

    func inspectTemporaries(_ id: UUID, library: URL) throws -> [TemporaryCandidate] {
        let record = try journal.load(id)
        try checkJournalSeparation(record, source: nil, library: library)
        let lease = try journal.lock(id)
        defer { lease.unlock() }
        let access = library.startAccessingSecurityScopedResource()
        defer { if access { library.stopAccessingSecurityScopedResource() } }
        return try temporaryCandidates(record, library: library)
    }

    private func temporaryCandidates(_ record: ImportRecord, library: URL) throws -> [TemporaryCandidate] {
        try validateLibrary(library, record: record)
        let root = try SafeImportFiles.root(library)
        let sensitive = try volumeReader(library).isCaseSensitive ?? false
        var candidates: [TemporaryCandidate] = []
        for file in record.files {
            try Task.checkCancellation()
            let parts = try SafeImportFiles.components(file.destinationRelativePath)
            let relative = (Array(parts.dropLast()) + [file.temporaryName]).joined(separator: "/")
            do {
                let parent = try SafeImportFiles.directory(Array(parts.dropLast()), in: root, create: false, caseSensitive: sensitive)
                guard let current = try SafeImportFiles.node(file.temporaryName, in: parent) else { continue }
                var info = stat()
                guard fstatat(parent.raw, file.temporaryName, &info, AT_SYMLINK_NOFOLLOW) == 0 else { throw SafeImportFiles.posixError() }
                let expected = file.temporarySnapshot
                let owned = expected.map { $0.createdSeconds != nil && $0.createdSeconds == current.createdSeconds &&
                    $0.createdNanos == current.createdNanos && $0.identity.inode == current.identity.inode &&
                    (record.libraryVolumeID != nil || $0.identity.device == current.identity.device) } ?? false
                let sourceIDs = Set(record.files.compactMap { $0.sourceSnapshot?.identity.inode })
                let safe = owned && info.st_nlink == 1 && current.size <= file.byteCount && !sourceIDs.contains(current.identity.inode)
                candidates.append(TemporaryCandidate(id: file.id, relativePath: relative, snapshot: current, removable: safe,
                    message: safe ? L10n.text("Recorded identity matches a regular file with no other links. It can be removed.") :
                        L10n.text("Missing or mismatched identity, unexpected size or additional links. Temporary file preserved.")))
            } catch let error as NSError where error.domain == NSPOSIXErrorDomain && error.code == Int(ENOENT) { continue }
            catch { candidates.append(TemporaryCandidate(id: file.id, relativePath: relative, snapshot: nil, removable: false, message: error.localizedDescription)) }
        }
        try validateLibrary(library, record: record)
        return candidates
    }

    func cleanTemporaries(_ id: UUID, library: URL, approved: [TemporaryCandidate]) throws -> [String] {
        let record = try journal.load(id)
        try checkJournalSeparation(record, source: nil, library: library)
        let lease = try journal.lock(id)
        defer { lease.unlock() }
        let access = library.startAccessingSecurityScopedResource()
        defer { if access { library.stopAccessingSecurityScopedResource() } }
        let current = try temporaryCandidates(record, library: library)
        let root = try SafeImportFiles.root(library)
        let sensitive = try volumeReader(library).isCaseSensitive ?? false
        var messages: [String] = []
        for candidate in approved where candidate.removable {
            try Task.checkCancellation()
            guard let fresh = current.first(where: { $0.id == candidate.id }), fresh.removable,
                  fresh.relativePath == candidate.relativePath, fresh.snapshot == candidate.snapshot else {
                messages.append(L10n.text("Preserved: %@. The state changed or identity was not confirmed.", String(describing: candidate.relativePath)))
                continue
            }
            try validateLibrary(library, record: record)
            let parts = try SafeImportFiles.components(fresh.relativePath)
            let parent = try SafeImportFiles.directory(Array(parts.dropLast()), in: root, create: false, caseSensitive: sensitive)
            guard try SafeImportFiles.node(parts.last!, in: parent) == fresh.snapshot else {
                messages.append(L10n.text("Preserved: %@. The file changed.", String(describing: fresh.relativePath)))
                continue
            }
            guard unlinkat(parent.raw, parts.last!, 0) == 0 else { throw SafeImportFiles.posixError() }
            try SafeImportFiles.synchronize(parent)
            messages.append(L10n.text("Removed: %@", String(describing: fresh.relativePath)))
        }
        return messages
    }

    func assessImported(source: URL, library: URL, files: [PhotoFile]) throws -> ImportedAssessment {
        guard !PlanningPaths.rootsOverlap(journal.root, source), !PlanningPaths.rootsOverlap(journal.root, library),
              !PlanningPaths.rootsOverlap(source, library) else { throw PlanningError.message(L10n.text("The source, archive or local record overlap.")) }
        let sourceAccess = source.startAccessingSecurityScopedResource()
        let libraryAccess = library.startAccessingSecurityScopedResource()
        defer {
            if sourceAccess { source.stopAccessingSecurityScopedResource() }
            if libraryAccess { library.stopAccessingSecurityScopedResource() }
        }
        let sourceRoot = try SafeImportFiles.root(source)
        let sourceIdentity = try SafeImportFiles.snapshot(sourceRoot, directory: true).identity
        let libraryRoot = try SafeImportFiles.root(library)
        let libraryIdentity = try SafeImportFiles.snapshot(libraryRoot, directory: true).identity
        let volume = try volumeReader(library)
        let listing = try journal.list()
        var notes = listing.issues
        let records = listing.entries.map(\.record).filter { record in
            (try? validateLibrary(library, record: record, strict: false)) != nil
        }
        let references = records.flatMap(\.files).filter { $0.sha256 != nil }
        let bySize = Dictionary(grouping: references, by: \.byteCount)
        var verified: Set<String> = []
        for file in files {
            try Task.checkCancellation()
            guard let candidates = bySize[file.byteCount] else { continue }
            do {
                guard source.appendingPathComponent(file.relativePath).standardizedFileURL == file.url.standardizedFileURL,
                      let original = try SafeImportFiles.hash(relative: file.relativePath, in: sourceRoot, caseSensitive: true),
                      original.snapshot.size == file.byteCount else { continue }
                for candidate in candidates where candidate.sha256 == original.sha256 {
                    let existing = try SafeImportFiles.hash(relative: candidate.destinationRelativePath, in: libraryRoot,
                                                            caseSensitive: volume.isCaseSensitive ?? false)
                    if existing?.sha256 == original.sha256 && existing?.snapshot.size == file.byteCount {
                        try PlanningPaths.validateSource(file, root: source)
                        var currentPaths = PlanningPaths(caseSensitive: volume.isCaseSensitive ?? false)
                        guard try PlanningPaths.node(at: file.url)?.snapshot == original.snapshot,
                              try currentPaths.inspectDestination(candidate.destinationRelativePath, root: library) == .existing,
                              try PlanningPaths.node(at: library.appendingPathComponent(candidate.destinationRelativePath))?.snapshot == existing?.snapshot else { continue }
                        verified.insert(file.id)
                        break
                    }
                }
            } catch is CancellationError { throw CancellationError() }
            catch { notes.append("\(file.relativePath): \(error.localizedDescription)") }
        }
        guard try PlanningPaths.node(at: source)?.snapshot.identity == sourceIdentity,
              try PlanningPaths.node(at: library)?.snapshot.identity == libraryIdentity else {
            throw PlanningError.message(L10n.text("The source or archive changed during verification."))
        }
        return ImportedAssessment(verifiedIDs: verified, notes: notes)
    }

    private func validateLibrary(_ library: URL, record: ImportRecord, strict: Bool = true) throws {
        try HistoryRoots.validate(library, recordedPath: record.libraryRootPath, identity: record.libraryIdentity, volumeID: record.libraryVolumeID, strict: strict)
    }

    private func checkJournalSeparation(_ record: ImportRecord, source: URL?, library: URL) throws {
        guard !PlanningPaths.rootsOverlap(journal.root, library),
              !PlanningPaths.rootsOverlap(journal.root, source ?? URL(fileURLWithPath: record.sourceRootPath)),
              !PlanningPaths.rootsOverlap(library, source ?? URL(fileURLWithPath: record.sourceRootPath)) else {
            throw PlanningError.message(L10n.text("The source, archive or local record overlap. Action blocked."))
        }
    }

    private func checkedSum(_ lhs: Int64, _ rhs: Int64) throws -> Int64 {
        let value = lhs.addingReportingOverflow(rhs)
        guard rhs >= 0, !value.overflow else { throw PlanningError.message(L10n.text("Invalid size in the record.")) }
        return value.partialValue
    }
}
