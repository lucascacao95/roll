import AppKit
import Observation

@MainActor @Observable
final class DiscoveryModel {
    private(set) var root: URL?
    private(set) var result: ScanResult?
    private(set) var errorMessage: String?
    private(set) var isScanning = false
    private(set) var sessionID = UUID()
    private(set) var thumbnails = ThumbnailLoader()
    private(set) var selectedIDs: Set<String> = [] {
        didSet { if !applyingPlanAssessment { invalidatePlan() } }
    }
    var filters = PhotoFilters() {
        didSet {
            if filters.onlyNotImported != oldValue.onlyNotImported {
                if filters.onlyNotImported { checkImported() } else { clearAssessment() }
            }
            selectedIDs.formIntersection(visibleCaptures.map(\.id))
            invalidatePlan()
        }
    }
    private(set) var libraryRoot: URL?
    var eventName = "" {
        didSet { if eventName != oldValue { invalidatePlan() } }
    }
    private(set) var plan: ImportPlan?
    private(set) var isPlanning = false
    private(set) var planningError: String?
    var isShowingPlan = false
    private(set) var isImporting = false
    private(set) var importProgress: ImportProgress?
    private(set) var importReport: ImportRecord?
    private(set) var importError: String?
    @ObservationIgnored private var importTask: Task<Void, Never>?
    @ObservationIgnored private var importRevision = UUID()
    @ObservationIgnored private let importer: ImportService
    let history: HistoryModel
    private(set) var isCheckingImported = false
    private(set) var verifiedImportedIDs: Set<String> = []
    private(set) var importedNotes: [String] = []
    private(set) var importedCheckedAt: Date?
    @ObservationIgnored private var assessmentTask: Task<Void, Never>?
    @ObservationIgnored private var assessmentRevision = UUID()
    @ObservationIgnored private var applyingPlanAssessment = false

    let preferences: AppPreferences
    let libraryAccess: LibraryAccess
    let volumes = VolumeMonitor()
    @ObservationIgnored private var volumesChangedDuringImport = false

    init(importer: ImportService = .shared, preferences: AppPreferences = .shared,
         libraryAccess: LibraryAccess = .shared) {
        self.importer = importer
        self.preferences = preferences
        self.libraryAccess = libraryAccess
        history = HistoryModel(importer: importer)
        filters = preferences.filters
        libraryRoot = libraryAccess.url
        volumes.onChange = { [weak self] in self?.volumesChanged() }
    }

    func volumesChanged() {
        guard !isImporting else { volumesChangedDuringImport = true; return }
        libraryAccess.reconnect()
        libraryRoot = libraryAccess.url
        clearAssessment()
        invalidatePlan()
        // A new discovery is required after a volume change; never reuse stale source identities.
        if root != nil {
            scanTask?.cancel()
            sessionID = UUID()
            isScanning = false
            result = nil
            selectedIDs.removeAll()
            errorMessage = L10n.text("Volumes changed. Choose the source again to refresh the scan.")
        }
    }

    func reconnectLibrary() {
        guard !isImporting else { return }
        libraryAccess.reconnect()
        libraryRoot = libraryAccess.url
        clearAssessment()
        invalidatePlan()
        if filters.onlyNotImported { checkImported() }
    }

    func forgetLibrary() {
        guard !isImporting else { return }
        libraryAccess.forget()
        libraryRoot = nil
        clearAssessment()
        invalidatePlan()
    }

    func applyDefaults() {
        guard !isImporting else { return }
        filters = preferences.filters
        invalidatePlan()
    }

    func acceptRecoveryPlan(_ recovery: ImportPlan) {
        guard !isImporting else { return }
        invalidatePlan()
        plan = recovery
        isShowingPlan = true
    }

    func clearAssessment() {
        assessmentRevision = UUID()
        assessmentTask?.cancel()
        assessmentTask = nil
        isCheckingImported = false
        verifiedImportedIDs = []
        importedNotes = []
        importedCheckedAt = nil
    }

    func checkImported() {
        guard !isImporting else { return }
        clearAssessment()
        guard let root, let libraryRoot, let result else {
            importedNotes = [L10n.text("Choose a source and archive and finish scanning before checking imported files.")]
            return
        }
        let revision = assessmentRevision
        let files = result.captures.flatMap(\.files)
        isCheckingImported = true
        assessmentTask = Task {
            do {
                let value = try await importer.assessImported(source: root, library: libraryRoot, files: files)
                guard revision == assessmentRevision, !Task.isCancelled else { return }
                verifiedImportedIDs = value.verifiedIDs
                importedNotes = value.notes
                importedCheckedAt = .now
                applyingPlanAssessment = true
                selectedIDs.formIntersection(visibleCaptures.map(\.id))
                applyingPlanAssessment = false
                if importReport == nil { invalidatePlan() }
            } catch is CancellationError {} catch {
                guard revision == assessmentRevision else { return }
                importedNotes = [error.localizedDescription]
            }
            guard revision == assessmentRevision else { return }
            isCheckingImported = false
            assessmentTask = nil
        }
    }

    func eligibleFiles(_ capture: PhotoCapture) -> [PhotoFile] {
        capture.files.filter { filters.format.includes($0) && (!filters.onlyNotImported || !verifiedImportedIDs.contains($0.id)) }
    }

    private var eligibleCaptures: [PhotoCapture] {
        visibleCaptures.map { PhotoCapture(id: $0.id, files: eligibleFiles($0), representativeDate: $0.captureDate) }
    }

    @ObservationIgnored private var plannedOrganization: FolderOrganization?

    func startImport() {
        guard !isImporting, let plan, !plan.hasBlockingIssues else { return }
        if plan.recoveryOf == nil, let plannedOrganization, plannedOrganization != preferences.organization {
            invalidatePlan()
            planningError = L10n.text("Organization changed. Generate a new preview.")
            return
        }
        let revision = UUID()
        importRevision = revision
        importReport = nil
        importError = nil
        importProgress = nil
        isImporting = true
        let update: @Sendable (ImportProgress) -> Void = { [weak self] progress in
            Task { @MainActor [weak self] in
                guard let self, self.importRevision == revision, self.isImporting else { return }
                self.importProgress = progress
            }
        }
        importTask = Task {
            do {
                let report = try await importer.run(plan, progress: update)
                importReport = report
            } catch is CancellationError {
                importError = L10n.text("Import cancelled before copying started.")
            } catch { importError = error.localizedDescription }
            isImporting = false
            importTask = nil
            importProgress = nil
            clearAssessment()
            if filters.onlyNotImported { checkImported() }
            history.refresh()
            if volumesChangedDuringImport {
                volumesChangedDuringImport = false
                // Keep the finished report visible. The engine owns independent access leases
                // during copying; workspace notifications never close those leases mid-operation.
                libraryAccess.reconnect()
                libraryRoot = libraryAccess.url
                scanTask?.cancel()
                sessionID = UUID()
                result = nil
                applyingPlanAssessment = true
                selectedIDs.removeAll()
                applyingPlanAssessment = false
                clearAssessment()
                errorMessage = L10n.text("Volumes changed during the import. Review the summary and choose the source again.")
            }
        }
    }

    func cancelImport() { importTask?.cancel() }

    var visibleCaptures: [PhotoCapture] {
        result?.captures.filter { filters.matches($0) && !eligibleFiles($0).isEmpty } ?? []
    }
    var visibleSummary: PhotoSummary { PhotoSummary(captures: eligibleCaptures, format: .all) }
    var selectedSummary: PhotoSummary {
        PhotoSummary(captures: eligibleCaptures.filter { selectedIDs.contains($0.id) }, format: .all)
    }

    func toggleSelection(_ id: String) {
        guard !isImporting else { return }
        guard visibleCaptures.contains(where: { $0.id == id }) else { return }
        if !selectedIDs.insert(id).inserted { selectedIDs.remove(id) }
    }

    func selectVisible() { if !isImporting { selectedIDs = Set(visibleCaptures.map(\.id)) } }
    func clearSelection() { if !isImporting { selectedIDs.removeAll() } }

    func setDateRangeEnabled(_ enabled: Bool) {
        guard !isImporting else { return }
        var updated = filters
        let days = result?.captures.compactMap { $0.captureDate?.timestamp.day } ?? []
        updated.startDay = enabled ? (days.min() ?? PhotoDay(date: .now)) : nil
        updated.endDay = enabled ? (days.max() ?? PhotoDay(date: .now)) : nil
        filters = updated
    }

    @ObservationIgnored private var scanTask: Task<Void, Never>?
    @ObservationIgnored private let scanner = PhotoScanner()
    @ObservationIgnored private let planner = ImportPlanner()
    @ObservationIgnored private var planTask: Task<Void, Never>?
    @ObservationIgnored private var planRevision = UUID()

    func chooseLibrary() {
        guard !isImporting else { return }
        let panel = NSOpenPanel()
        panel.title = L10n.text("Choose the Archive Folder on Your SSD")
        panel.prompt = L10n.text("Use as Archive")
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = false
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        libraryAccess.choose(url)
        libraryRoot = libraryAccess.url
        clearAssessment()
        invalidatePlan()
        if filters.onlyNotImported { checkImported() }
    }

    func setLibrary(_ url: URL) {
        guard !isImporting else { return }
        libraryRoot = url
        clearAssessment()
        if filters.onlyNotImported { checkImported() }
        invalidatePlan()
    }

    func generatePlan() {
        guard !isImporting else { return }
        invalidatePlan()
        guard let root, let libraryRoot else {
            planningError = L10n.text("Choose the source and archive folder.")
            return
        }
        guard !selectedIDs.isEmpty, !isScanning, !isCheckingImported else {
            planningError = L10n.text("Select photos after scanning is complete.")
            return
        }
        let revision = planRevision
        let format = filters.format
        let event = eventName
        let organization = preferences.organization
        isPlanning = true
        planTask = Task {
            do {
                if filters.onlyNotImported, let result {
                    let assessment = try await importer.assessImported(source: root, library: libraryRoot, files: result.captures.flatMap(\.files))
                    guard revision == planRevision, !Task.isCancelled else { return }
                    verifiedImportedIDs = assessment.verifiedIDs
                    importedNotes = assessment.notes
                    importedCheckedAt = .now
                    applyingPlanAssessment = true
                    selectedIDs.formIntersection(visibleCaptures.map(\.id))
                    applyingPlanAssessment = false
                }
                let captures = eligibleCaptures.filter { selectedIDs.contains($0.id) }
                let generated = try await planner.plan(source: root, library: libraryRoot,
                                                       captures: captures, format: format, event: event, organization: organization)
                guard revision == planRevision, !Task.isCancelled else { return }
                guard organization == preferences.organization else {
                    invalidatePlan()
                    return
                }
                plannedOrganization = organization
                plan = generated
                isShowingPlan = true
            } catch is CancellationError {
                // Changes to the selection or destination invalidate work in flight.
            } catch {
                guard revision == planRevision else { return }
                planningError = error.localizedDescription
            }
            guard revision == planRevision else { return }
            isPlanning = false
            planTask = nil
        }
    }

    func invalidatePlan() {
        guard !isImporting else { return }
        planRevision = UUID()
        planTask?.cancel()
        planTask = nil
        isPlanning = false
        plan = nil
        plannedOrganization = nil
        planningError = nil
        isShowingPlan = false
        importReport = nil
        importError = nil
    }

    func chooseSource(at suggested: URL? = nil) {
        guard !isImporting else { return }
        let panel = NSOpenPanel()
        panel.title = L10n.text("Choose an SD Card or Source Folder")
        panel.directoryURL = suggested
        panel.prompt = L10n.text("Use as Source")
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = false
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        discover(url)
    }

    func discover(_ url: URL) {
        guard !isImporting else { return }
        scanTask?.cancel()
        sessionID = UUID()
        let session = sessionID
        root = url
        clearAssessment()
        result = nil
        selectedIDs.removeAll()
        filters = preferences.filters
        errorMessage = nil
        thumbnails = ThumbnailLoader()
        isScanning = true
        scanTask = Task {
            do {
                let discovered = try await scanner.scan(root: url)
                guard sessionID == session else { return }
                if !Task.isCancelled {
                    result = discovered
                    if filters.onlyNotImported { checkImported() }
                }
            } catch is CancellationError {
                // Cancellation is a normal user action, not a read error.
            } catch {
                guard sessionID == session else { return }
                errorMessage = error.localizedDescription
            }
            guard sessionID == session else { return }
            isScanning = false
            scanTask = nil
        }
    }

    func cancel() {
        scanTask?.cancel()
        clearAssessment()
        if isImporting { cancelImport() } else { invalidatePlan() }
    }
}
