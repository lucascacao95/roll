import Foundation
import Darwin

struct CopyCheckpoint: Sendable {
    enum Phase: Sendable { case temporaryCreated, chunkCopied, beforeVerification, beforePublication, willRename, afterPublication }
    let phase: Phase
    let source: URL
    let temporary: URL
    let destination: URL
    let bytes: Int64
}

/// One serial service per application; no suspension while an operation owns descriptors.
actor ImportService {
    static let shared = ImportService()
    let journal: ImportJournal
    let volumeReader: @Sendable (URL) throws -> LibraryVolumeInfo
    private let checkpoint: @Sendable (CopyCheckpoint) throws -> Void

    init(journalRoot: URL = ImportJournal.defaultRoot,
         volumeReader: @escaping @Sendable (URL) throws -> LibraryVolumeInfo = LibraryVolumeInfo.read,
         checkpoint: @escaping @Sendable (CopyCheckpoint) throws -> Void = { _ in }) {
        journal = ImportJournal(root: journalRoot)
        self.volumeReader = volumeReader
        self.checkpoint = checkpoint
    }

    func run(_ plan: ImportPlan, progress: @escaping @Sendable (ImportProgress) -> Void = { _ in }) throws -> ImportRecord {
        try Task.checkCancellation()
        guard !plan.hasBlockingIssues, !plan.files.isEmpty,
              let sourceIdentity = plan.sourceIdentity, let libraryIdentity = plan.libraryIdentity,
              plan.files.allSatisfy({ $0.sourceSnapshot != nil && $0.relativeDestination != nil }) else {
            throw PlanningError.message(L10n.text("The preview has unresolved issues or is incomplete. Generate another preview."))
        }
        guard !PlanningPaths.rootsOverlap(journal.root, plan.sourceRoot),
              !PlanningPaths.rootsOverlap(journal.root, plan.libraryRoot) else {
            throw PlanningError.message(L10n.text("The local record folder cannot be inside the source or archive, or contain them."))
        }
        let readingSource = plan.sourceRoot.startAccessingSecurityScopedResource()
        let writingLibrary = plan.libraryRoot.startAccessingSecurityScopedResource()
        defer {
            if readingSource { plan.sourceRoot.stopAccessingSecurityScopedResource() }
            if writingLibrary { plan.libraryRoot.stopAccessingSecurityScopedResource() }
        }
        let id = UUID()
        let recoveryLease = try plan.recoveryOf.map { try journal.lock($0) }
        defer { recoveryLease?.unlock() }
        let lease = try journal.lock(id)
        defer { lease.unlock() }
        var record = ImportRecord(schemaVersion: 2, id: id, startedAt: .now,
                                  sourceRootPath: plan.sourceRoot.path, libraryRootPath: plan.libraryRoot.path,
                                  sourceIdentity: sourceIdentity, libraryIdentity: libraryIdentity,
                                  sourceVolumeID: plan.sourceVolumeID, libraryVolumeID: plan.libraryVolumeID,
                                  files: plan.files.enumerated().map { index, file in
            ImportFileRecord(id: file.id, sourceRelativePath: file.source.relativePath,
                             destinationRelativePath: file.relativeDestination!, byteCount: file.source.byteCount,
                             temporaryName: ".photoimporter-\(id.uuidString)-\(index).partial",
                             sourceSnapshot: file.sourceSnapshot)
        })
        record.recoveryOf = plan.recoveryOf
        // Persist every intended temporary name before any write to the library.
        try journal.save(record)
        var cancelled = false
        do {
            try validateRoots(plan, sourceIdentity: sourceIdentity, libraryIdentity: libraryIdentity)
            let source = try SafeImportFiles.root(plan.sourceRoot)
            let library = try SafeImportFiles.root(plan.libraryRoot)
            guard try SafeImportFiles.snapshot(source, directory: true).identity == sourceIdentity,
                  try SafeImportFiles.snapshot(library, directory: true).identity == libraryIdentity else {
                throw PlanningError.message(L10n.text("A volume or folder has been replaced since the preview."))
            }
            let volume = try validateVolume(plan.libraryRoot, required: 0)
            let caseSensitive = volume.isCaseSensitive ?? false
            var currentPaths = PlanningPaths(caseSensitive: caseSensitive)
            var newBytes: Int64 = 0
            for file in plan.files {
                try Task.checkCancellation()
                if try currentPaths.inspectDestination(file.relativeDestination!, root: plan.libraryRoot) == .newFile {
                    let sum = newBytes.addingReportingOverflow(file.source.byteCount)
                    guard file.source.byteCount >= 0, !sum.overflow else { throw PlanningError.message(L10n.text("Invalid preview size.")) }
                    newBytes = sum.partialValue
                }
            }
            _ = try validateVolume(plan.libraryRoot, required: newBytes)
            for index in plan.files.indices {
                do {
                    try Task.checkCancellation()
                    try validateRoots(plan, sourceIdentity: sourceIdentity, libraryIdentity: libraryIdentity)
                    record.files[index].status = .copying
                    try journal.save(record)
                    let item = plan.files[index]
                    let temporaryName = record.files[index].temporaryName
                    let emit: (String, Double) -> Void = { phase, fraction in
                        progress(ImportProgress(completedFiles: index, totalFiles: plan.files.count,
                                                path: item.source.relativePath, phase: phase, fileFraction: fraction))
                    }
                    let result = try copy(item, plan: plan, source: source, library: library,
                                          caseSensitive: caseSensitive, temporaryName: temporaryName,
                                          emit: emit, temporaryCreated: { snapshot in
                        record.files[index].temporarySnapshot = snapshot
                        try journal.save(record)
                    }, verified: { hash in
                        record.files[index].sha256 = hash
                        record.files[index].status = .verified
                        try journal.save(record)
                    })
                    // Complete this short commit section even if cancellation arrives after publication.
                    record.files[index].status = result.status
                    record.files[index].sha256 = result.hash
                    try journal.save(record)
                    emit(L10n.text("Complete"), 1)
                } catch is CancellationError {
                    record.files[index].status = .cancelled
                    record.files[index].error = L10n.text("Cancelled. Originals preserved; no incomplete final file was published.")
                    cancelled = true
                    break
                } catch {
                    record.files[index].status = .failed
                    record.files[index].error = error.localizedDescription
                    if error is ImportJournalError || Self.isFatalIO(error) {
                        record.error = error.localizedDescription
                        break
                    }
                    try journal.save(record)
                }
            }
        } catch is CancellationError {
            cancelled = true
        } catch { record.error = error.localizedDescription }

        record.finishedAt = .now
        if cancelled { record.state = .cancelled }
        else if record.successCount == record.files.count { record.state = .completed }
        else { record.state = record.successCount > 0 ? .partial : .failed }
        do { try journal.save(record) }
        catch { record.error = error.localizedDescription + L10n.text(" The previous record must be reconciled with files at the destination.") }
        return record
    }

    private func copy(_ item: PlannedFile, plan: ImportPlan, source: ImportDescriptor, library: ImportDescriptor,
                      caseSensitive: Bool, temporaryName: String, emit: (String, Double) -> Void,
                      temporaryCreated: (FileSnapshot) throws -> Void,
                      verified: (String) throws -> Void) throws -> (status: ImportFileStatus, hash: String) {
        let sourceParts = try SafeImportFiles.components(item.source.relativePath)
        let destinationParts = try SafeImportFiles.components(item.relativeDestination!)
        guard let expected = item.sourceSnapshot, expected.size >= 0, expected.size == item.source.byteCount,
              destinationParts.allSatisfy(ImportNaming.validComponent),
              item.source.url.standardizedFileURL == plan.sourceRoot.appendingPathComponent(item.source.relativePath).standardizedFileURL else {
            throw PlanningError.message(L10n.text("The preview file or path is invalid."))
        }
        let sourceParent = try SafeImportFiles.directory(Array(sourceParts.dropLast()), in: source, create: false, caseSensitive: true)
        let input = try SafeImportFiles.readFile(sourceParts.last!, in: sourceParent)
        guard try SafeImportFiles.snapshot(input) == expected else {
            throw PlanningError.message(L10n.text("The source changed since the preview. Scan the source and generate another preview."))
        }
        // Inspect without creating directories before checking the space for this file.
        _ = try validateVolume(plan.libraryRoot, required: 0)
        let parent = try SafeImportFiles.directory(Array(destinationParts.dropLast()), in: library, create: true, caseSensitive: caseSensitive)
        let parentIdentity = try SafeImportFiles.snapshot(parent, directory: true).identity
        let finalName = destinationParts.last!
        let size = expected.size
        let fraction: @Sendable (Int64) -> Double = { size == 0 ? 1 : min(1, Double($0) / Double(size)) }
        if let existingName = try SafeImportFiles.matchingName(finalName, in: parent, caseSensitive: caseSensitive) {
            let existing = try SafeImportFiles.readFile(existingName, in: parent)
            let existingSnapshot = try SafeImportFiles.snapshot(existing)
            guard existingSnapshot.size == size else { throw PlanningError.message(L10n.text("Conflict: a file of a different size already exists at the destination. Nothing was replaced.")) }
            let sourceHash = try SafeImportFiles.digest(input, expectedSize: size) { emit(L10n.text("Verifying source"), fraction($0) * 0.5) }
            let existingHash = try SafeImportFiles.digest(existing, expectedSize: size) { emit(L10n.text("Verifying existing file"), 0.5 + fraction($0) * 0.5) }
            try validateUnchanged(item, input: input, plan: plan, parent: parent, parentIdentity: parentIdentity, library: library, parts: destinationParts, caseSensitive: caseSensitive)
            guard sourceHash == existingHash, item.expectedSHA256 == nil || item.expectedSHA256 == sourceHash,
                  try SafeImportFiles.snapshot(existing) == existingSnapshot,
                  try SafeImportFiles.node(existingName, in: parent) == existingSnapshot else {
                throw PlanningError.message(L10n.text("Conflict: existing content differs from the source or changed during verification. Nothing was replaced."))
            }
            return (.alreadyPresent, sourceHash)
        }

        _ = try validateVolume(plan.libraryRoot, required: size)
        let temporary = try ImportDescriptor(openat(parent.raw, temporaryName, O_RDWR | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600))
        var published = false
        defer { if !published { _ = unlinkat(parent.raw, temporaryName, 0) } }
        try temporaryCreated(SafeImportFiles.snapshot(temporary))
        let destinationURL = plan.libraryRoot.appendingPathComponent(item.relativeDestination!)
        let temporaryURL = destinationURL.deletingLastPathComponent().appendingPathComponent(temporaryName)
        func check(_ phase: CopyCheckpoint.Phase, bytes: Int64 = 0) throws {
            try checkpoint(CopyCheckpoint(phase: phase, source: item.source.url, temporary: temporaryURL,
                                          destination: destinationURL, bytes: bytes))
        }
        try check(.temporaryCreated)
        let sourceHash = try SafeImportFiles.digest(input, copyingTo: temporary, expectedSize: size) { bytes in
            emit(L10n.text("Copying"), fraction(bytes) * 0.5)
            try check(.chunkCopied, bytes: bytes)
        }
        try SafeImportFiles.synchronize(temporary)
        try check(.beforeVerification)
        let temporarySnapshot = try SafeImportFiles.snapshot(temporary)
        guard temporarySnapshot.size == size else { throw PlanningError.message(L10n.text("Invalid temporary copy size.")) }
        let copiedHash = try SafeImportFiles.digest(temporary, expectedSize: size) { emit(L10n.text("Verifying copy"), 0.5 + fraction($0) * 0.5) }
        guard copiedHash == sourceHash, item.expectedSHA256 == nil || item.expectedSHA256 == sourceHash,
              try SafeImportFiles.snapshot(temporary) == temporarySnapshot else {
            throw PlanningError.message(L10n.text("SHA-256 verification of the copy failed."))
        }
        try verified(sourceHash)
        try check(.beforePublication)
        try Task.checkCancellation()
        try validateUnchanged(item, input: input, plan: plan, parent: parent, parentIdentity: parentIdentity,
                              library: library, parts: destinationParts, caseSensitive: caseSensitive)
        guard try SafeImportFiles.node(temporaryName, in: parent) == temporarySnapshot,
              try SafeImportFiles.matchingName(finalName, in: parent, caseSensitive: caseSensitive) == nil else {
            throw PlanningError.message(L10n.text("The destination changed before completion. Nothing was replaced."))
        }
        // There is intentionally no fallback to rename(), which could overwrite an existing file.
        try check(.willRename)
        guard renameatx_np(parent.raw, temporaryName, parent.raw, finalName, UInt32(RENAME_EXCL)) == 0 else {
            if errno == ENOTSUP || errno == EINVAL {
                throw PlanningError.message(L10n.text("The filesystem does not support the required safe finalization without replacement."))
            }
            throw SafeImportFiles.posixError()
        }
        published = true
        try check(.afterPublication)
        guard try SafeImportFiles.node(finalName, in: parent)?.identity == temporarySnapshot.identity else {
            throw PlanningError.message(L10n.text("The final file changed after publication; check the destination."))
        }
        try SafeImportFiles.synchronize(parent)
        return (.copied, sourceHash)
    }

    private func validateUnchanged(_ item: PlannedFile, input: ImportDescriptor, plan: ImportPlan,
                                   parent: ImportDescriptor, parentIdentity: FileIdentity, library: ImportDescriptor,
                                   parts: [String], caseSensitive: Bool) throws {
        try validateRoots(plan, sourceIdentity: plan.sourceIdentity!, libraryIdentity: plan.libraryIdentity!)
        try PlanningPaths.validateSource(item.source, root: plan.sourceRoot)
        guard try SafeImportFiles.snapshot(input) == item.sourceSnapshot,
              try PlanningPaths.node(at: item.source.url)?.snapshot == item.sourceSnapshot else {
            throw PlanningError.message(L10n.text("The source changed during copying. The final file was not published."))
        }
        let currentParent = try SafeImportFiles.directory(Array(parts.dropLast()), in: library, create: false, caseSensitive: caseSensitive)
        guard try SafeImportFiles.snapshot(currentParent, directory: true).identity == parentIdentity,
              try SafeImportFiles.snapshot(parent, directory: true).identity == parentIdentity else {
            throw PlanningError.message(L10n.text("The destination folder changed during the operation."))
        }
    }

    private func validateRoots(_ plan: ImportPlan, sourceIdentity: FileIdentity, libraryIdentity: FileIdentity) throws {
        guard !PlanningPaths.rootsOverlap(plan.sourceRoot, plan.libraryRoot),
              try PlanningPaths.node(at: plan.sourceRoot)?.snapshot.identity == sourceIdentity,
              try PlanningPaths.node(at: plan.libraryRoot)?.snapshot.identity == libraryIdentity else {
            throw PlanningError.message(L10n.text("The source or archive was disconnected, replaced or overlaps. Generate another preview."))
        }
        for (root, expected) in [(plan.sourceRoot, plan.sourceVolumeID), (plan.libraryRoot, plan.libraryVolumeID)] {
            if let expected {
                let current = try root.resourceValues(forKeys: [.volumeUUIDStringKey]).volumeUUIDString
                guard current == expected else { throw PlanningError.message(L10n.text("The volume identity changed or cannot be confirmed. Generate another preview.")) }
            }
        }
    }

    private func validateVolume(_ root: URL, required: Int64) throws -> LibraryVolumeInfo {
        let volume = try volumeReader(root)
        guard volume.isReadOnly == false else { throw PlanningError.message(L10n.text("The volume does not allow writing or its state is unknown.")) }
        guard let available = volume.availableBytes, available >= required else {
            throw PlanningError.message(L10n.text("Insufficient or unverifiable space at the destination."))
        }
        return volume
    }

    private static func isFatalIO(_ error: Error) -> Bool {
        let error = error as NSError
        return error.domain == NSPOSIXErrorDomain && [ENOSPC, ENODEV, EIO, EROFS, EBADF].contains(Int32(error.code))
    }
}
