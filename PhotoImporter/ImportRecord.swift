import Foundation
import Darwin

struct FileIdentity: Codable, Equatable, Sendable {
    let device: UInt64
    let inode: UInt64
}

struct FileSnapshot: Codable, Equatable, Sendable {
    let identity: FileIdentity
    let size: Int64
    let modifiedSeconds: Int64
    let modifiedNanos: Int64
    let changedSeconds: Int64
    let changedNanos: Int64
    let createdSeconds: Int64?
    let createdNanos: Int64?

    init(_ info: stat) {
        identity = FileIdentity(device: UInt64(truncatingIfNeeded: info.st_dev), inode: info.st_ino)
        size = info.st_size
        modifiedSeconds = Int64(info.st_mtimespec.tv_sec)
        modifiedNanos = Int64(info.st_mtimespec.tv_nsec)
        changedSeconds = Int64(info.st_ctimespec.tv_sec)
        changedNanos = Int64(info.st_ctimespec.tv_nsec)
        let hasBirthTime = info.st_birthtimespec.tv_sec != 0 || info.st_birthtimespec.tv_nsec != 0
        createdSeconds = hasBirthTime ? Int64(info.st_birthtimespec.tv_sec) : nil
        createdNanos = hasBirthTime ? Int64(info.st_birthtimespec.tv_nsec) : nil
    }
}

enum ImportFileStatus: String, Codable, Sendable {
    case pending, copying, verified, copied, alreadyPresent, failed, cancelled
    var label: String {
        switch self {
        case .pending: L10n.text("Not started")
        case .copying: L10n.text("Copying")
        case .verified: L10n.text("Temporary file verified; completion pending")
        case .copied: L10n.text("Copied and verified")
        case .alreadyPresent: L10n.text("Already Imported — content verified")
        case .failed: L10n.text("Failed")
        case .cancelled: L10n.text("Cancelled")
        }
    }
    var isSuccess: Bool { self == .copied || self == .alreadyPresent }
}

struct ImportFileRecord: Codable, Identifiable, Sendable {
    let id: String
    let sourceRelativePath: String
    let destinationRelativePath: String
    let byteCount: Int64
    let temporaryName: String
    var status: ImportFileStatus = .pending
    var sha256: String?
    var error: String?
    var sourceSnapshot: FileSnapshot?
    var temporarySnapshot: FileSnapshot?
}

struct ImportRecord: Codable, Identifiable, Sendable {
    enum State: String, Codable { case running, completed, partial, failed, cancelled }
    let schemaVersion: Int
    let id: UUID
    let startedAt: Date
    let sourceRootPath: String
    let libraryRootPath: String
    let sourceIdentity: FileIdentity?
    let libraryIdentity: FileIdentity?
    let sourceVolumeID: String?
    let libraryVolumeID: String?
    var files: [ImportFileRecord]
    var state: State = .running
    var finishedAt: Date?
    var error: String?
    var recoveryOf: UUID?

    var copiedCount: Int { files.filter { $0.status == .copied }.count }
    var existingCount: Int { files.filter { $0.status == .alreadyPresent }.count }
    var failedCount: Int { files.filter { $0.status == .failed }.count }
    var successCount: Int { files.filter { $0.status.isSuccess }.count }
    var captureCount: Int {
        Set(files.map { ($0.sourceRelativePath as NSString).deletingPathExtension }).count
    }
    var title: String {
        switch state {
        case .running: L10n.text("Import in progress")
        case .completed: L10n.text("Import Complete")
        case .partial: L10n.text("Partial import")
        case .failed: L10n.text("Import incomplete")
        case .cancelled: L10n.text("Import cancelled")
        }
    }
}

struct ImportProgress: Sendable {
    let completedFiles: Int
    let totalFiles: Int
    let path: String
    let phase: String
    let fileFraction: Double
    var fraction: Double {
        guard totalFiles > 0 else { return 0 }
        return min(1, (Double(completedFiles) + fileFraction) / Double(totalFiles))
    }
}

struct ImportJournalError: LocalizedError {
    let message: String
    var errorDescription: String? { L10n.text("Could not save the import record: ") + message }
}

struct ImportJournal: Sendable {
    let root: URL

    static var defaultRoot: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("PhotoImporter/Imports", isDirectory: true)
    }

    func save(_ record: ImportRecord) throws {
        do {
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let url = root.appendingPathComponent(record.id.uuidString + ".json")
            try encoder.encode(record).write(to: url, options: .atomic)
            let handle = try FileHandle(forWritingTo: url)
            defer { try? handle.close() }
            try handle.synchronize()
            // The JSON's atomic replacement also changes its directory entry.
            let directory = try SafeImportFiles.root(root)
            try SafeImportFiles.synchronize(directory)
        } catch { throw ImportJournalError(message: error.localizedDescription) }
    }

    func load(_ id: UUID) throws -> ImportRecord {
        let data = try Data(contentsOf: root.appendingPathComponent(id.uuidString + ".json"))
        let record = try JSONDecoder().decode(ImportRecord.self, from: data)
        try validate(record)
        return record
    }

    func validate(_ record: ImportRecord) throws {
        guard (1...2).contains(record.schemaVersion), record.recoveryOf != record.id, !record.files.isEmpty,
              record.sourceRootPath.hasPrefix("/"), record.libraryRootPath.hasPrefix("/"),
              Set(record.files.map(\.id)).count == record.files.count else {
            throw ImportJournalError(message: L10n.text("Invalid record or unknown version."))
        }
        for (index, file) in record.files.enumerated() {
            _ = try SafeImportFiles.components(file.sourceRelativePath)
            let parts = try SafeImportFiles.components(file.destinationRelativePath)
            guard parts.allSatisfy(ImportNaming.validComponent), file.byteCount >= 0,
                  file.temporaryName == ".photoimporter-\(record.id.uuidString)-\(index).partial",
                  file.sha256 == nil || (file.sha256!.count == 64 && file.sha256!.utf8.allSatisfy({
                      (48...57).contains($0) || (97...102).contains($0)
                  })) else { throw ImportJournalError(message: L10n.text("Invalid path, hash or temporary filename in the record.")) }
        }
    }

    func list() throws -> JournalListing {
        guard FileManager.default.fileExists(atPath: root.path) else { return JournalListing(entries: [], issues: []) }
        let urls = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
        var entries: [HistoryEntry] = []
        var issues: [String] = []
        for url in urls where url.pathExtension == "json" {
            do {
                guard let id = UUID(uuidString: url.deletingPathExtension().lastPathComponent) else {
                    throw ImportJournalError(message: L10n.text("Invalid record filename."))
                }
                let record = try load(id)
                guard record.id == id else { throw ImportJournalError(message: L10n.text("Mismatched identifier in the record.")) }
                let active: Bool
                do {
                    let lease = try ImportOperationLock(url: root.appendingPathComponent(id.uuidString + ".lock"), create: false)
                    lease.unlock()
                    active = false
                } catch let error as NSError where error.domain == NSPOSIXErrorDomain && error.code == Int(ENOENT) {
                    active = record.schemaVersion == 1 && record.state == .running
                    if active { issues.append(L10n.text("%@: older running record without an activity lock. Recovery and cleanup are blocked; scan the source again.", String(describing: url.lastPathComponent))) }
                } catch let error as NSError where error.domain == NSPOSIXErrorDomain && [EWOULDBLOCK, EAGAIN].contains(Int32(error.code)) {
                    active = true
                } catch {
                    issues.append(L10n.text("%@: activity could not be confirmed; actions blocked.", String(describing: url.lastPathComponent)))
                    active = true
                }
                entries.append(HistoryEntry(record: record, isActive: active))
            } catch { issues.append("\(url.lastPathComponent): \(error.localizedDescription)") }
        }
        return JournalListing(entries: entries.sorted { $0.record.startedAt > $1.record.startedAt }, issues: issues)
    }

    func lock(_ id: UUID) throws -> ImportOperationLock {
        do {
            let path = root.appendingPathComponent(id.uuidString + ".lock")
            if FileManager.default.fileExists(atPath: root.appendingPathComponent(id.uuidString + ".json").path) {
                let old = try load(id)
                if old.schemaVersion == 1 && old.state == .running && !FileManager.default.fileExists(atPath: path.path) {
                    throw ImportJournalError(message: L10n.text("Activity for this older operation cannot be confirmed. Scan the source again."))
                }
            }
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            return try ImportOperationLock(url: path)
        } catch let error as ImportJournalError { throw error
        } catch let error as NSError where error.domain == NSPOSIXErrorDomain && [EWOULDBLOCK, EAGAIN].contains(Int32(error.code)) {
            throw error
        } catch { throw ImportJournalError(message: error.localizedDescription) }
    }
}

final class ImportOperationLock {
    private let descriptor: ImportDescriptor
    init(url: URL, create: Bool = true) throws {
        descriptor = try ImportDescriptor(open(url.path, (create ? O_RDWR | O_CREAT : O_RDONLY) | O_NOFOLLOW | O_CLOEXEC, 0o600))
        guard flock(descriptor.raw, LOCK_EX | LOCK_NB) == 0 else { throw SafeImportFiles.posixError() }
    }
    func unlock() { _ = flock(descriptor.raw, LOCK_UN) }
}
