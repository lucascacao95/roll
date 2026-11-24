import SwiftUI

struct PlanningControls: View {
    @Bindable var model: DiscoveryModel

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 10) {
                Text(L10n.text("Destination archive")).font(.title2.bold())
                SurfaceCard {
                    HStack(spacing: 20) {
                        Image(systemName: "externaldrive").font(.system(size: 36)).foregroundStyle(.secondary).frame(width: 50)
                        Divider().frame(height: 48)
                        VStack(alignment: .leading, spacing: 5) {
                            Text(model.libraryRoot?.lastPathComponent ?? L10n.text("Choose your archive")).font(.title3.bold())
                            Text(model.libraryRoot?.path ?? model.libraryAccess.savedPath ?? L10n.text("Destination folder for your photos"))
                                .foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                                .help(model.libraryRoot?.path ?? model.libraryAccess.savedPath ?? "")
                        }
                        Spacer(minLength: 0)
                        Menu {
                            Button(L10n.text("Choose Folder…"), action: model.chooseLibrary)
                            Button(L10n.text("Reconnect Archive"), action: model.reconnectLibrary)
                        } label: { Label(L10n.text("Change"), systemImage: "chevron.down") }
                            .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                    }
                }
                Text(model.libraryAccess.status).font(.caption).foregroundStyle(.secondary)
            }
            HStack(alignment: .top, spacing: 24) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(L10n.text("Format")).font(.headline)
                    ChoiceMenu(title: L10n.text("Format"), selection: $model.filters.format,
                               options: [("RAW + JPEG", .all), ("RAW", .raw), ("JPEG", .jpeg)])
                }
                VStack(alignment: .leading, spacing: 8) {
                    Text(L10n.text("Organization")).font(.headline)
                    ChoiceMenu(title: L10n.text("Organization"), selection: Binding(get: { model.preferences.organization }, set: {
                        model.preferences.organization = $0
                        model.invalidatePlan()
                    }), options: [
                        (L10n.text("Year / Date / Format"), FolderOrganization()),
                        (L10n.text("Year / Date"), FolderOrganization(yearFolder: true, formatFolders: false)),
                        (L10n.text("Date / Format"), FolderOrganization(yearFolder: false, formatFolders: true)),
                        (L10n.text("Date"), FolderOrganization(yearFolder: false, formatFolders: false))
                    ])
                }
            }
            HStack {
                TextField(L10n.text("Event name (optional)"), text: $model.eventName).textFieldStyle(.roundedBorder).controlSize(.large)
                if model.isPlanning {
                    ProgressView().controlSize(.small)
                    Button(L10n.text("Cancel Preview"), action: model.invalidatePlan)
                }
            }
        }.disabled(model.isImporting)
    }
}

struct ImportPlanView: View {
    let plan: ImportPlan
    @Bindable var model: DiscoveryModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L10n.text("Import Preview")).font(.title2.bold())
            Text(L10n.text("Source: ") + plan.sourceRoot.path).font(.caption).textSelection(.enabled)
            Text(plan.libraryRoot.path).font(.callout).textSelection(.enabled)
            HStack {
                Text(L10n.text("%@ photos · %@ files · ", String(describing: plan.captureCount), String(describing: plan.files.count)) +
                     ByteCountFormatter.string(fromByteCount: plan.estimatedBytes, countStyle: .file))
                Spacer()
                Text(L10n.text("Free: ") + (plan.volume?.availableBytes.map {
                    ByteCountFormatter.string(fromByteCount: $0, countStyle: .file)
                } ?? L10n.text("not verified")))
            }.font(.callout)
            if let volume = plan.volume {
                Text(L10n.text("Volume: %@ · %@ · %@", String(describing: volume.name ?? L10n.text("unnamed")), String(describing: volumeLocation(volume)), String(describing: volumeAccess(volume))))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Text(L10n.text("%@ new · %@ existing to verify · %@ needing attention", String(describing: plan.newCount), String(describing: plan.existingCount), String(describing: plan.blockedCount)))
                .font(.callout)

            if !plan.blockers.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(plan.blockers.enumerated()), id: \.offset) { _, message in
                        Label(message, systemImage: "exclamationmark.triangle").foregroundStyle(.red)
                    }
                }.font(.callout)
            }

            if model.isImporting || model.importReport != nil || model.importError != nil {
                ImportOperationView(model: model)
            } else {
            Table(plan.files) {
                TableColumn(L10n.text("Source")) { row in
                    Text(row.source.relativePath).lineLimit(2).help(row.source.url.path)
                }.width(min: 150, ideal: 190)
                TableColumn(L10n.text("Destination relative to archive")) { row in
                    Text(row.relativeDestination ?? L10n.text("No destination defined"))
                        .font(.system(.caption, design: .monospaced)).lineLimit(2)
                        .help(row.relativeDestination.map { plan.libraryRoot.appendingPathComponent($0).path } ?? row.state.detail)
                }.width(min: 240, ideal: 350)
                TableColumn(L10n.text("Format")) { row in Text(row.source.format == .raw ? "RAW" : "JPEG") }
                    .width(60)
                TableColumn(L10n.text("Size")) { row in
                    Text(ByteCountFormatter.string(fromByteCount: row.source.byteCount, countStyle: .file))
                }.width(85)
                TableColumn(L10n.text("Status")) { row in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(row.state.label).foregroundStyle(row.state.isBlocked ? Color.red : Color.primary)
                        if row.state.isBlocked { Text(row.state.detail).font(.caption).lineLimit(2) }
                    }.help(rowDetails(row))
                }.width(min: 140, ideal: 220)
            }
            }
            DisclosureGroup(L10n.text("Verification notes and limitations")) {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(plan.notes.enumerated()), id: \.offset) { _, note in Text(note) }
                }.font(.caption).foregroundStyle(.secondary)
            }
            HStack {
                Text(L10n.text("A verified import is not an independent backup. Originals on your card are preserved."))
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                if model.isImporting {
                    Button(L10n.text("Cancel Import"), action: model.cancelImport)
                } else {
                    Button(L10n.text("Close")) { dismiss() }.keyboardShortcut(.cancelAction)
                    Button(model.importReport == nil ? L10n.text("Import Roll") : L10n.text("Verify and Retry"), action: model.startImport)
                        .disabled(plan.hasBlockingIssues)
                }
            }
        }
        .padding(24)
        .frame(minWidth: 950, idealWidth: 1_100, minHeight: 560, idealHeight: 680)
        .interactiveDismissDisabled(model.isImporting)
    }

    private func volumeLocation(_ info: LibraryVolumeInfo) -> String {
        switch info.isInternal {
        case true: L10n.text("internal storage")
        case false: L10n.text("external storage")
        case nil: L10n.text("location not verified")
        }
    }

    private func volumeAccess(_ info: LibraryVolumeInfo) -> String {
        switch info.isReadOnly {
        case true: L10n.text("read-only")
        case false: L10n.text("volume allows writing; actual access not yet tested")
        case nil: L10n.text("write access not verified")
        }
    }

    private func rowDetails(_ row: PlannedFile) -> String {
        var text = row.state.detail
        if let date = row.date {
            text += L10n.text("\nDate: %@ · %@ · %@", String(describing: date.timestamp.displayText), String(describing: date.source.label), String(describing: date.relativePath))
        }
        return text
    }
}
