import Foundation

struct HistoryEntry: Identifiable, Sendable {
    let record: ImportRecord
    let isActive: Bool
    var id: UUID { record.id }
    var title: String {
        if record.schemaVersion == 1 && record.state == .running && isActive { return L10n.text("Older activity unconfirmed") }
        if record.state == .running && !isActive { return L10n.text("Import interrupted") }
        return record.title
    }
}

struct JournalListing: Sendable {
    let entries: [HistoryEntry]
    let issues: [String]
}

enum ReconciliationState: String, Sendable {
    case verified = "Íntegro — SHA-256 conferido"
    case missing = "Ausente no destino"
    case different = "Conteúdo diferente"
    case unknown = "Sem checksum de referência"
    case unavailable = "Não foi possível verificar"
    var label: String { L10n.legacyLabel(rawValue) }
}

struct HistoryFileCheck: Identifiable, Sendable {
    let id: String
    let state: ReconciliationState
    let message: String
}

struct TemporaryCandidate: Identifiable, Sendable {
    let id: String
    let relativePath: String
    let snapshot: FileSnapshot?
    let removable: Bool
    let message: String
}

struct ImportedAssessment: Sendable {
    let verifiedIDs: Set<String>
    let notes: [String]
}

struct HashedImportFile: Sendable {
    let snapshot: FileSnapshot
    let sha256: String
}
