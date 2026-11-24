import Foundation

enum PlannedFileState: Equatable, Sendable {
    case newFile
    case existing
    case blocked(String)

    var label: String {
        switch self {
        case .newFile: L10n.text("New")
        case .existing: L10n.text("Exists — verify")
        case .blocked: L10n.text("Needs attention")
        }
    }

    var detail: String {
        switch self {
        case .newFile: L10n.text("The path was available when checked.")
        case .existing: L10n.text("An existing file was found. Name and size do not prove it is a duplicate; its content still needs verification.")
        case .blocked(let reason): reason
        }
    }

    var isBlocked: Bool {
        if case .blocked = self { return true }
        return false
    }
}

struct PlannedFile: Identifiable, Sendable {
    let source: PhotoFile
    let captureID: String
    let relativeDestination: String?
    let date: PhotoDate?
    var state: PlannedFileState
    var sourceSnapshot: FileSnapshot?
    var expectedSHA256: String?
    var id: String { source.relativePath }
}

struct LibraryVolumeInfo: Sendable {
    var name: String?
    var identifier: String?
    var availableBytes: Int64?
    var isCaseSensitive: Bool?
    var isReadOnly: Bool?
    var isInternal: Bool?
    var totalBytes: Int64?

    static func read(at url: URL) throws -> Self {
        let values = try url.resourceValues(forKeys: [
            .volumeTotalCapacityKey, .volumeNameKey, .volumeUUIDStringKey, .volumeAvailableCapacityKey, .volumeSupportsCaseSensitiveNamesKey,
            .volumeIsReadOnlyKey, .volumeIsInternalKey
        ])
        return Self(name: values.volumeName, identifier: values.volumeUUIDString,
                    availableBytes: values.volumeAvailableCapacity.map(Int64.init),
                    isCaseSensitive: values.volumeSupportsCaseSensitiveNames,
                    isReadOnly: values.volumeIsReadOnly, isInternal: values.volumeIsInternal,
                    totalBytes: values.volumeTotalCapacity.map(Int64.init))
    }
}

struct ImportPlan: Sendable {
    let sourceRoot: URL
    let libraryRoot: URL
    let event: String
    let files: [PlannedFile]
    let estimatedBytes: Int64
    let volume: LibraryVolumeInfo?
    let blockers: [String]
    let notes: [String]
    var sourceIdentity: FileIdentity?
    var libraryIdentity: FileIdentity?
    var sourceVolumeID: String?
    var libraryVolumeID: String?
    var recoveryOf: UUID?

    var captureCount: Int { Set(files.map(\.captureID)).count }
    var newCount: Int { files.filter { $0.state == .newFile }.count }
    var existingCount: Int { files.filter { $0.state == .existing }.count }
    var blockedCount: Int { files.filter { $0.state.isBlocked }.count }
    var hasBlockingIssues: Bool { !blockers.isEmpty || blockedCount > 0 }
}

enum ImportNaming {
    static func eventName(_ input: String) throws -> String {
        let value = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard value.isEmpty || validComponent(value), value.utf8.count <= 242 else {
            throw PlanningError.message(L10n.text("Invalid event name. Avoid separators, control characters, '.'/'..' and very long names."))
        }
        return value
    }

    static func validComponent(_ value: String) -> Bool {
        !value.isEmpty && value != "." && value != ".." && value.utf8.count <= 255 &&
        !value.hasSuffix(".") && !value.hasSuffix(" ") &&
        value.rangeOfCharacter(from: CharacterSet(charactersIn: "<>:\"/\\|?*").union(.controlCharacters)) == nil
    }

    static func relativeDestination(file: PhotoFile, day: PhotoDay, event: String, organization: FolderOrganization = FolderOrganization()) throws -> String {
        guard validComponent(file.url.lastPathComponent) else {
            throw PlanningError.message(L10n.text("The original filename is incompatible with the destination. It will not be renamed automatically."))
        }
        let date = String(format: "%04d-%02d-%02d", day.year, day.month, day.day)
        let session = event.isEmpty ? date : date + " - " + event
        var parts: [String] = []
        if organization.yearFolder { parts.append(String(format: "%04d", day.year)) }
        parts.append(session)
        if organization.formatFolders { parts.append(file.format == .raw ? "RAW" : "JPEG") }
        parts.append(file.url.lastPathComponent)
        return parts.joined(separator: "/")
    }

    static func key(_ path: String, caseSensitive: Bool) -> String {
        let normalized = path.precomposedStringWithCanonicalMapping
        return caseSensitive ? normalized : normalized.folding(options: .caseInsensitive, locale: Locale(identifier: "en_US_POSIX"))
    }
}

enum PlanningError: LocalizedError {
    case message(String)
    var errorDescription: String? {
        switch self { case .message(let text): text }
    }
}
