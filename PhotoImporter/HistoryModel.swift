import AppKit
import Observation
import Darwin

private enum HistoryActionResult: Sendable {
    case checks([HistoryFileCheck]), temporaries([TemporaryCandidate]), cleanup([String]), plan(ImportPlan)
}

@MainActor @Observable
final class HistoryModel {
    private(set) var entries: [HistoryEntry] = []
    private(set) var issues: [String] = []
    private(set) var isLoading = false
    private(set) var isBusy = false
    private(set) var errorMessage: String?
    private(set) var source: URL?
    private(set) var library: URL?
    private(set) var checks: [HistoryFileCheck] = []
    private(set) var checkedAt: Date?
    private(set) var temporaries: [TemporaryCandidate] = []
    private(set) var cleanupMessages: [String] = []
    private(set) var preparedPlan: ImportPlan?
    var selectedID: UUID? {
        didSet {
            if selectedID != oldValue {
                cancel()
                source = nil
                library = nil
                checks = []
                checkedAt = nil
                temporaries = []
                cleanupMessages = []
                preparedPlan = nil
            }
        }
    }
    var selected: HistoryEntry? { entries.first { $0.id == selectedID } }
    @ObservationIgnored private let importer: ImportService
    @ObservationIgnored private var action: Task<Void, Never>?
    @ObservationIgnored private var loading: Task<Void, Never>?
    @ObservationIgnored private var revision = UUID()

    init(importer: ImportService = .shared) { self.importer = importer }

    func refresh() {
        resetResults()
        loading?.cancel()
        isLoading = true
        loading = Task {
            do {
                let listing = try await importer.historyList()
                guard !Task.isCancelled else { return }
                entries = listing.entries
                issues = listing.issues
                if !entries.contains(where: { $0.id == selectedID }) { selectedID = entries.first?.id }
            } catch { errorMessage = error.localizedDescription }
            isLoading = false
            loading = nil
        }
    }

    func confirmSource(_ url: URL) { resetResults(); source = url }
    func confirmLibrary(_ url: URL) { resetResults(); library = url }
    func chooseSource() {
        if let url = chooseFolder(title: L10n.text("Confirm Source for This Import"), path: selected?.record.sourceRootPath) { confirmSource(url) }
    }
    func chooseLibrary() {
        if let url = chooseFolder(title: L10n.text("Confirm Archive for This Import"), path: selected?.record.libraryRootPath) { confirmLibrary(url) }
    }

    func reconcile() {
        guard let selected, !selected.isActive, let library else { return }
        let id = selected.id
        let service = importer
        checks = []
        checkedAt = nil
        perform { .checks(try await service.reconcile(id, library: library)) }
    }

    func prepareRecovery() {
        guard let selected, !selected.isActive, let source, let library else { return }
        let id = selected.id
        let service = importer
        preparedPlan = nil
        perform { .plan(try await service.prepareRecovery(id, source: source, library: library)) }
    }

    func inspectTemporaries() {
        guard let selected, !selected.isActive, let library else { return }
        let id = selected.id
        let service = importer
        cleanupMessages = []
        temporaries = []
        perform { .temporaries(try await service.inspectTemporaries(id, library: library)) }
    }

    func cleanTemporaries() {
        guard let selected, !selected.isActive, let library else { return }
        let id = selected.id
        let approved = temporaries.filter(\.removable)
        guard !approved.isEmpty else { return }
        let service = importer
        perform { .cleanup(try await service.cleanTemporaries(id, library: library, approved: approved)) }
    }

    func cancel() {
        revision = UUID()
        action?.cancel()
        action = nil
        isBusy = false
        errorMessage = nil
    }

    private func resetResults() {
        cancel()
        checks = []
        checkedAt = nil
        temporaries = []
        cleanupMessages = []
        preparedPlan = nil
    }

    private func perform(_ work: @escaping @Sendable () async throws -> HistoryActionResult) {
        cancel()
        let token = revision
        isBusy = true
        action = Task {
            do {
                let result = try await work()
                guard token == revision, !Task.isCancelled else { return }
                switch result {
                case .checks(let value): checks = value; checkedAt = .now
                case .temporaries(let value): temporaries = value
                case .cleanup(let value): cleanupMessages = value; temporaries = []
                case .plan(let value): preparedPlan = value
                }
            } catch is CancellationError {} catch {
                guard token == revision else { return }
                let native = error as NSError
                errorMessage = native.domain == NSPOSIXErrorDomain && [EAGAIN, EWOULDBLOCK].contains(Int32(native.code)) ?
                    L10n.text("The operation is active in another window or instance. Wait for it to finish.") : error.localizedDescription
            }
            guard token == revision else { return }
            isBusy = false
            action = nil
        }
    }

    private func chooseFolder(title: String, path: String?) -> URL? {
        let panel = NSOpenPanel()
        panel.title = title
        panel.prompt = L10n.text("Confirm Folder")
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = false
        if let path { panel.directoryURL = URL(fileURLWithPath: path) }
        return panel.runModal() == .OK ? panel.url : nil
    }
}
