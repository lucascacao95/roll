import SwiftUI

private enum HistoryStatusFilter: String, CaseIterable {
    case all = "Todos", completed = "Concluídas", interrupted = "Interrompidas", partial = "Parciais", failed = "Com erros", cancelled = "Canceladas", active = "Ativas"
    var label: String { L10n.legacyLabel(rawValue) }

    func matches(_ entry: HistoryEntry) -> Bool {
        switch self {
        case .all: true
        case .completed: entry.record.state == .completed
        case .interrupted: entry.record.state == .running && !entry.isActive
        case .partial: entry.record.state == .partial
        case .failed: entry.record.state == .failed
        case .cancelled: entry.record.state == .cancelled
        case .active: entry.isActive
        }
    }
}

struct HistoryView: View {
    @Bindable var model: HistoryModel
    let onRecovery: (ImportPlan) -> Void
    @State private var confirmCleanup = false
    @State private var showingDetails = false
    @State private var pendingRecovery: ImportPlan?
    @State private var period = 0
    @State private var status: HistoryStatusFilter = .all

    private var filtered: [HistoryEntry] {
        let cutoff = period == 0 ? Date.distantPast : Calendar.current.date(byAdding: .day, value: -period, to: .now) ?? .distantPast
        return model.entries.filter { $0.record.startedAt >= cutoff && status.matches($0) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                PageHeading(title: L10n.text("Previous Rolls"), subtitle: L10n.text("Review the results and details of each import."), symbol: "clock")
                InformationBanner(title: L10n.text("Recorded results and destination verification"), message: L10n.text("History preserves the result of each operation. Check the destination in the details to verify its current content. A verified import is not an independent backup."))
                HStack(alignment: .bottom, spacing: 28) {
                    VStack(alignment: .leading, spacing: 7) {
                        Text(L10n.text("Period")).font(.callout)
                        Picker(L10n.text("Period"), selection: $period) {
                            Text(L10n.text("All Time")).tag(0)
                            Text(L10n.text("Last 7 Days")).tag(7)
                            Text(L10n.text("Last 30 Days")).tag(30)
                            Text(L10n.text("Last 90 Days")).tag(90)
                        }.labelsHidden().frame(width: 210)
                    }
                    VStack(alignment: .leading, spacing: 7) {
                        Text("Status").font(.callout)
                        Picker("Status", selection: $status) {
                            ForEach(HistoryStatusFilter.allCases, id: \.self) { Text($0.label).tag($0) }
                        }.labelsHidden().frame(width: 180)
                    }
                    Spacer()
                    if model.isLoading { ProgressView().controlSize(.small) }
                    Text(filtered.count == 1 ? L10n.text("1 roll") : L10n.text("%@ rolls", String(describing: filtered.count))).foregroundStyle(.secondary)
                    Button(L10n.text("Refresh"), systemImage: "arrow.clockwise", action: model.refresh)
                        .labelStyle(.iconOnly).help(L10n.text("Refresh History")).disabled(model.isLoading || model.isBusy)
                }
                if !model.issues.isEmpty {
                    DisclosureGroup(L10n.text("%@ issues reading records", String(describing: model.issues.count))) {
                        ForEach(Array(model.issues.enumerated()), id: \.offset) { _, message in Text(message).font(.caption).textSelection(.enabled) }
                    }
                }
                if let error = model.errorMessage { Text(error).foregroundStyle(.red).textSelection(.enabled) }
                if filtered.isEmpty && !model.isLoading {
                    ContentUnavailableView(model.entries.isEmpty ? L10n.text("No previous rolls") : L10n.text("No rolls match this filter"), systemImage: "clock.arrow.circlepath")
                }
                LazyVStack(spacing: 12) {
                    ForEach(filtered) { entry in
                        Button {
                            model.selectedID = entry.id
                            showingDetails = true
                        } label: { historyRow(entry) }
                        .buttonStyle(.plain).accessibilityHint(L10n.text("Open details, verification and recovery"))
                    }
                }
            }.padding(30)
        }
        .onAppear { model.refresh() }
        .onDisappear { model.cancel() }
        .sheet(isPresented: $showingDetails, onDismiss: {
            if let plan = pendingRecovery { pendingRecovery = nil; onRecovery(plan) }
        }) {
            if let entry = model.selected {
                VStack(alignment: .leading, spacing: 18) {
                    HStack {
                        Text(L10n.text("Import Details")).font(.title2.bold())
                        Spacer()
                        Button(L10n.text("Close")) { showingDetails = false }.keyboardShortcut(.cancelAction)
                    }
                    if let error = model.errorMessage { Text(error).foregroundStyle(.red).textSelection(.enabled) }
                    details(entry)
                }.padding(24).frame(minWidth: 1000, idealWidth: 1100, minHeight: 680, idealHeight: 780)
                .confirmationDialog(L10n.text("Remove only the verified temporary files below?"), isPresented: $confirmCleanup) {
                    Button(L10n.text("Remove Verified Temporary Files"), role: .destructive, action: model.cleanTemporaries)
                } message: {
                    Text(L10n.text("The list shows files and their verified identities. Final files and originals are preserved."))
                }
            }
        }
    }

    private func historyRow(_ entry: HistoryEntry) -> some View {
        SurfaceCard {
            HStack(spacing: 18) {
                Image(systemName: "photo.stack").font(.system(size: 28)).foregroundStyle(Color.accentColor)
                    .frame(width: 62, height: 68).background(Color.accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 7) {
                    Text(entry.record.startedAt, format: .dateTime.day().month(.abbreviated).year().hour().minute()).font(.headline)
                    Text(sessionName(entry)).font(.callout).foregroundStyle(.secondary).lineLimit(1)
                    Text(L10n.text("%@ photos · %@ files", String(describing: entry.record.captureCount), String(describing: entry.record.files.count))).font(.caption)
                }.frame(maxWidth: .infinity, alignment: .leading)
                VStack(alignment: .leading, spacing: 7) {
                    Label(URL(fileURLWithPath: entry.record.sourceRootPath).lastPathComponent, systemImage: "sdcard")
                        .help(L10n.text("Source: ") + entry.record.sourceRootPath)
                    Label(URL(fileURLWithPath: entry.record.libraryRootPath).lastPathComponent, systemImage: "externaldrive")
                        .help(L10n.text("Destination: ") + entry.record.libraryRootPath)
                }.font(.caption).foregroundStyle(.secondary).lineLimit(1).frame(maxWidth: 200, alignment: .leading)
                Text(entry.title).font(.caption.weight(.semibold)).foregroundStyle(statusColor(entry))
                    .padding(.horizontal, 12).padding(.vertical, 7)
                    .background(statusColor(entry).opacity(0.12), in: Capsule()).fixedSize(horizontal: false, vertical: true)
                Image(systemName: "chevron.right").foregroundStyle(.secondary)
            }
        }
    }

    private func sessionName(_ entry: HistoryEntry) -> String {
        let components = entry.record.files.first?.destinationRelativePath.split(separator: "/").map(String.init) ?? []
        return components.first { $0.range(of: #"^\d{4}-\d{2}-\d{2}"#, options: .regularExpression) != nil } ?? L10n.text("Photo import")
    }

    private func statusColor(_ entry: HistoryEntry) -> Color {
        if entry.isActive { return .blue }
        switch entry.record.state {
        case .completed: return .green
        case .failed: return .red
        case .running, .partial, .cancelled: return .orange
        }
    }

    @ViewBuilder
    private func details(_ entry: HistoryEntry) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L10n.text("Recorded status: %@", String(describing: entry.title))).font(.headline)
            Text(L10n.text("Recorded source: %@", String(describing: entry.record.sourceRootPath))).font(.caption).textSelection(.enabled)
            Text(L10n.text("Recorded archive: %@", String(describing: entry.record.libraryRootPath))).font(.caption).textSelection(.enabled)
            if let id = entry.record.recoveryOf { Text(L10n.text("Resuming operation %@", String(describing: id.uuidString))).font(.caption).textSelection(.enabled) }
            ForEach(model.entries.filter { $0.record.recoveryOf == entry.id }) { child in
                Button(L10n.text("View recovery from %@ — %@", String(describing: child.record.startedAt.formatted(date: .numeric, time: .shortened)), String(describing: child.title))) {
                    model.selectedID = child.id
                }.font(.caption)
            }
            if let error = entry.record.error { Text(error).font(.caption).foregroundStyle(.red) }
            HStack {
                Button(L10n.text("Confirm Archive…"), action: model.chooseLibrary)
                Text(model.library?.path ?? L10n.text("Required to verify the destination")).font(.caption).lineLimit(2)
            }
            HStack {
                Button(L10n.text("Confirm Source…"), action: model.chooseSource)
                Text(model.source?.path ?? L10n.text("Required to prepare recovery")).font(.caption).lineLimit(2)
            }
            HStack {
                Button(L10n.text("Verify Destination"), action: model.reconcile).disabled(model.library == nil)
                Button(L10n.text("Prepare Recovery"), action: model.prepareRecovery).disabled(model.library == nil || model.source == nil)
                Button(L10n.text("Inspect Temporary Files"), action: model.inspectTemporaries).disabled(model.library == nil)
            }.disabled(model.isBusy || entry.isActive)
            if entry.isActive { Text(L10n.text("Active operation or unconfirmed older activity. Recovery and cleanup are blocked.")).font(.caption).foregroundStyle(.orange) }
            if model.isBusy {
                HStack {
                    ProgressView().controlSize(.small)
                    Text(L10n.text("Verifying files…")).font(.callout)
                    Button(L10n.text("Cancel"), action: model.cancel)
                }
            }
            if let date = model.checkedAt {
                Text(L10n.text("Destination verified at %@. Verify again after external changes.", String(describing: date.formatted(date: .numeric, time: .standard))))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Table(entry.record.files) {
                TableColumn(L10n.text("File"), value: \.sourceRelativePath)
                TableColumn(L10n.text("Recorded result")) { file in Text(file.status.label).help(file.error ?? file.status.label) }
                TableColumn(L10n.text("Destination now")) { file in
                    let check = model.checks.first { $0.id == file.id }
                    Text(check?.state.label ?? L10n.text("Not verified"))
                        .help(check?.message ?? file.destinationRelativePath)
                }
            }.frame(minHeight: 140)
            if !model.temporaries.isEmpty {
                DisclosureGroup(L10n.text("Recorded temporary files found: %@", String(describing: model.temporaries.count))) {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(model.temporaries) { item in
                                Text(item.relativePath + "\n" + item.message).font(.caption).textSelection(.enabled)
                            }
                        }
                    }.frame(maxHeight: 120)
                }
                Button(L10n.text("Remove %@ Verified Temporary Files…", String(describing: model.temporaries.filter(\.removable).count)), role: .destructive) { confirmCleanup = true }
                    .disabled(model.isBusy || !model.temporaries.contains(where: \.removable))
            }
            ForEach(Array(model.cleanupMessages.enumerated()), id: \.offset) { _, message in Text(message).font(.caption) }
            if let plan = model.preparedPlan {
                Text(L10n.text("Recovery prepared: %@ files; files already intact were preserved.", String(describing: plan.files.count))).font(.callout)
                Button(L10n.text("Open Recovery Preview")) { showingDetails = false; pendingRecovery = plan }.disabled(model.isBusy)
            }
            Text(L10n.text("History records the operation result. Only destination verification confirms current presence and content."))
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}
