import SwiftUI

enum AppSection: String, CaseIterable, Identifiable {
    case importer = "Importar", history = "Histórico", preferences = "Preferências"
    var id: Self { self }
    var label: String { L10n.legacyLabel(rawValue) }
    var symbol: String {
        switch self { case .importer: "square.and.arrow.down"; case .history: "clock"; case .preferences: "gearshape" }
    }
}

struct DiscoveryView: View {
    @Environment(\.colorScheme) private var colorScheme
    @State private var model: DiscoveryModel
    @State private var section: AppSection?

    init(model: DiscoveryModel = DiscoveryModel(), initialSection: AppSection = .importer) {
        _model = State(initialValue: model)
        _section = State(initialValue: initialSection)
    }

    var body: some View {
        NavigationSplitView {
            VStack(alignment: .leading, spacing: 24) {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        RollWordmark()
                        Text(L10n.text("From capture to collection.")).font(.caption).foregroundStyle(sidebarForeground.opacity(0.7))
                    }
                }.padding(.horizontal, 20).padding(.top, 28)
                VStack(spacing: 8) {
                    ForEach(AppSection.allCases) { item in
                        Button { section = item } label: {
                            Label(item.label, systemImage: item.symbol).font(.title3)
                                .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 16).padding(.vertical, 13)
                                .foregroundStyle(section == item ? RollBrand.charcoal : sidebarForeground)
                                .background {
                                    if section == item {
                                        RoundedRectangle(cornerRadius: 10).fill(RollBrand.amber)
                                    }
                                }
                                .contentShape(RoundedRectangle(cornerRadius: 10))
                        }.buttonStyle(.plain).accessibilityAddTraits(section == item ? .isSelected : [])
                    }
                }.padding(.horizontal, 16).disabled(model.isImporting)
                Spacer(minLength: 0)
                LibraryCapacityView(access: model.libraryAccess).padding(16)
            }
            .navigationSplitViewColumnWidth(min: 220, ideal: 245, max: 290)
        } detail: {
            Group {
                switch section ?? .importer {
                case .importer: importPage
                case .history:
                    HistoryView(model: model.history) { recovery in
                        section = .importer
                        model.acceptRecoveryPlan(recovery)
                    }
                case .preferences: PreferencesView(model: model)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(nsColor: .windowBackgroundColor))
        }
        .tint(.accentColor)
        .navigationTitle("Roll")
        .focusedSceneValue(\.rollShowSettings, model.isImporting ? nil : { section = .preferences })
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Button { section = .importer; model.chooseSource() } label: { Label(L10n.text("Choose Source"), systemImage: "folder") }
                    .keyboardShortcut("o", modifiers: .command).disabled(model.isImporting)
            }
            ToolbarItem(placement: .automatic) {
                Button { section = .preferences } label: { Label(L10n.text("Settings"), systemImage: "gearshape") }
                    .disabled(model.isImporting)
            }
        }
        .sheet(isPresented: $model.isShowingPlan) {
            if let plan = model.plan { ImportPlanView(plan: plan, model: model) }
        }
        .onChange(of: model.preferences.organization) { model.invalidatePlan() }
        .onDisappear { model.cancel() }
    }

    private var sidebarForeground: Color { colorScheme == .dark ? RollBrand.ivory : RollBrand.charcoal }

    private var importPage: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top) {
                        heading
                        Spacer(minLength: 12)
                        ConnectionBadge(connected: model.libraryRoot != nil)
                    }
                    VStack(alignment: .leading, spacing: 12) { heading; ConnectionBadge(connected: model.libraryRoot != nil) }
                }
                VStack(alignment: .leading, spacing: 10) {
                    Text(L10n.text("Source")).font(.title2.bold())
                    SurfaceCard {
                        HStack(spacing: 20) {
                            Image(systemName: "sdcard").font(.system(size: 36)).foregroundStyle(Color.accentColor).frame(width: 50)
                            Divider().frame(height: 48)
                            VStack(alignment: .leading, spacing: 5) {
                                Text(model.root?.lastPathComponent ?? L10n.text("Choose your SD card")).font(.title3.bold())
                                Text(model.result.map { L10n.text("%@ photos found", String(describing: $0.captures.count)) } ?? L10n.text("A card or folder with JPG, JPEG and RW2 files"))
                                    .foregroundStyle(.secondary)
                                if let root = model.root { Text(root.path).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle).help(root.path) }
                            }
                            Spacer(minLength: 0)
                            Menu {
                                Button(L10n.text("Choose Folder…")) { model.chooseSource() }
                                Divider()
                                ForEach(model.volumes.volumes, id: \.self) { volume in
                                    Button(volume.lastPathComponent) { model.chooseSource(at: volume) }
                                }
                                if model.volumes.volumes.isEmpty { Text(L10n.text("No external volumes detected")) }
                                Button(L10n.text("Refresh Volumes")) { model.volumes.refresh() }
                            } label: { Label(L10n.text("Choose Source"), systemImage: "chevron.down") }
                            .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                        }
                    }.disabled(model.isImporting)
                }
                if model.isScanning {
                    HStack { ProgressView().controlSize(.small); Text(L10n.text("Scanning for photos…")); Spacer(); Button(L10n.text("Cancel"), action: model.cancel) }
                }
                if let error = model.errorMessage {
                    Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.red).textSelection(.enabled)
                }
                PlanningControls(model: model)
                if let result = model.result, let root = model.root {
                    VStack(alignment: .leading, spacing: 16) {
                        Text(L10n.text("Select your photos")).font(.title2.bold())
                        DiscoveryResultsView(model: model, result: result, root: root).id(model.sessionID)
                    }.disabled(model.isImporting)
                } else if !model.isScanning, model.errorMessage == nil {
                    ContentUnavailableView(L10n.text("Start a new roll"), systemImage: "photo.on.rectangle.angled",
                        description: Text(L10n.text("Choose a card or folder to select photos for your roll.")))
                }
            }.padding(30)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) { importFooter }
    }

    private var heading: some View {
        PageHeading(title: L10n.text("New Roll"), subtitle: L10n.text("Bring photos from your camera card into your archive."), symbol: "film")
    }

    private var importFooter: some View {
        VStack(spacing: 14) {
            HStack(spacing: 0) {
                metric(L10n.text("Selected photos"), value: "\(model.selectedSummary.captureCount)", symbol: "photo")
                Divider().frame(height: 50)
                metric(L10n.text("Files to copy"), value: "\(model.selectedSummary.fileCount)", symbol: "doc.on.doc")
                Divider().frame(height: 50)
                metric(L10n.text("Estimated size"), value: ByteCountFormatter.string(fromByteCount: model.selectedSummary.byteCount, countStyle: .file), symbol: "externaldrive")
            }.padding(.vertical, 14).background(Color.accentColor.opacity(0.065), in: RoundedRectangle(cornerRadius: 14))
            if let error = model.planningError {
                Label(error, systemImage: "exclamationmark.triangle").font(.callout).foregroundStyle(.red)
            }
            if model.isPlanning { Button(L10n.text("Cancel Preview"), action: model.invalidatePlan) }
            Button(action: model.generatePlan) {
                Label(model.isPlanning ? L10n.text("Preparing preview…") : L10n.text("Review Roll"), systemImage: "square.and.arrow.down")
                    .font(.title3.weight(.semibold)).frame(maxWidth: .infinity).padding(.vertical, 10)
            }.buttonStyle(.borderedProminent).controlSize(.large)
                .disabled(model.isImporting || model.isPlanning || model.libraryRoot == nil || model.selectedIDs.isEmpty || model.isScanning || model.isCheckingImported)
            Text(L10n.text("Review destinations before copying. Originals on your card are preserved.")).font(.caption).foregroundStyle(.secondary)
        }.padding(.horizontal, 30).padding(.vertical, 16).background(.bar)
    }

    private func metric(_ title: String, value: String, symbol: String) -> some View {
        VStack(spacing: 5) {
            Image(systemName: symbol).font(.title3).foregroundStyle(Color.accentColor)
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.system(size: 25, weight: .bold, design: .rounded)).lineLimit(1).minimumScaleFactor(0.65)
        }.frame(maxWidth: .infinity)
    }
}

private struct DiscoveryResultsView: View {
    @Bindable var model: DiscoveryModel
    let result: ScanResult
    let root: URL

    var body: some View {
        let visible = model.visibleCaptures
        let summary = model.visibleSummary
        let selected = model.selectedSummary
        FilterControls(model: model)

        HStack {
            Text(L10n.text("%@ of %@ photos · %@ eligible files", String(describing: visible.count), String(describing: result.captures.count), String(describing: summary.fileCount)))
            Spacer()
            Text(ByteCountFormatter.string(fromByteCount: summary.byteCount, countStyle: .file))
        }.font(.callout).foregroundStyle(.secondary)

        HStack {
            Button(L10n.text("Select Visible"), action: model.selectVisible).disabled(visible.isEmpty)
            Button(L10n.text("Clear Selection"), action: model.clearSelection).disabled(model.selectedIDs.isEmpty)
            Spacer()
            Text(L10n.text("Selected: %@ photos · %@ files · ", String(describing: selected.captureCount), String(describing: selected.fileCount)) +
                 ByteCountFormatter.string(fromByteCount: selected.byteCount, countStyle: .file))
                .font(.callout)
        }

        if !result.issues.isEmpty {
            DisclosureGroup(L10n.text("%@ read issues — partial results", String(describing: result.issues.count))) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(Array(result.issues.enumerated()), id: \.offset) { _, issue in
                            Text("\(issue.path): \(issue.message)").font(.caption).textSelection(.enabled)
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }.frame(maxHeight: 100)
            }
        }

        if result.captures.isEmpty {
            ContentUnavailableView(L10n.text("No photos found"), systemImage: "photo", description:
                Text(L10n.text("JPG, JPEG and RW2 files are supported, including inside DCIM.")))
        } else if visible.isEmpty {
            ContentUnavailableView(L10n.text("No photos match this filter"), systemImage: "line.3.horizontal.decrease", description:
                Text(L10n.text("Adjust the format or date range.")))
        } else {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 210), spacing: 16)], spacing: 16) {
                    ForEach(visible) { capture in
                        CaptureCard(capture: capture, root: root, loader: model.thumbnails,
                                    isSelected: model.selectedIDs.contains(capture.id), eligibleCount: model.eligibleFiles(capture).count) {
                            model.toggleSelection(capture.id)
                        }
                    }
                }.padding(2)
        }
    }
}

private struct FilterControls: View {
    @Bindable var model: DiscoveryModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 16) {
                Toggle(L10n.text("Filter by date"), isOn: Binding(
                    get: { model.filters.hasDateRange },
                    set: { model.setDateRangeEnabled($0) }
                )).toggleStyle(.checkbox)
            }
            HStack {
                Toggle(L10n.text("Not yet imported into this archive"), isOn: $model.filters.onlyNotImported)
                    .toggleStyle(.checkbox).disabled(model.libraryRoot == nil)
                if model.isCheckingImported { ProgressView().controlSize(.small) }
                if model.filters.onlyNotImported {
                    Button(L10n.text("Refresh Verification"), action: model.checkImported).disabled(model.isCheckingImported)
                }
            }
            if model.filters.onlyNotImported {
                Text(model.importedCheckedAt.map { L10n.text("Verified at %@. Only files with matching source and destination content are hidden.", String(describing: $0.formatted(date: .numeric, time: .standard))) } ??
                     L10n.text("Files not yet verified remain visible."))
                    .font(.caption).foregroundStyle(.secondary)
                if !model.importedNotes.isEmpty {
                    DisclosureGroup(L10n.text("%@ verification notes", String(describing: model.importedNotes.count))) {
                        ScrollView {
                            ForEach(Array(model.importedNotes.enumerated()), id: \.offset) { _, note in Text(note).font(.caption) }
                        }.frame(maxHeight: 80)
                    }
                }
            }
            if let start = model.filters.startDay, let end = model.filters.endDay {
                HStack {
                    DatePicker(L10n.text("From"), selection: Binding(
                        get: { start.pickerDate },
                        set: { model.filters.startDay = PhotoDay(date: $0) }
                    ), in: ...end.pickerDate, displayedComponents: .date)
                    DatePicker(L10n.text("To"), selection: Binding(
                        get: { end.pickerDate },
                        set: { model.filters.endDay = PhotoDay(date: $0) }
                    ), in: start.pickerDate..., displayedComponents: .date)
                }.environment(\.calendar, Calendar(identifier: .gregorian))
                if !model.filters.isValid {
                    Text(L10n.text("The start date must be on or before the end date.")).foregroundStyle(.red)
                }
            }
            Text(L10n.text("Changing filters deselects hidden photos. Fallback dates are identified on the cards."))
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}

private struct CaptureCard: View {
    let capture: PhotoCapture
    let root: URL
    let loader: ThumbnailLoader
    let isSelected: Bool
    let eligibleCount: Int
    let toggleSelection: () -> Void
    @State private var thumbnail: CGImage?
    @State private var loaded = false

    var body: some View {
        Button(action: toggleSelection) {
            VStack(alignment: .leading, spacing: 8) {
                ZStack(alignment: .topTrailing) {
                    ZStack {
                        Rectangle().fill(.quaternary)
                        if let thumbnail {
                            Image(decorative: thumbnail, scale: 1).resizable().scaledToFit()
                        } else {
                            VStack(spacing: 6) {
                                Image(systemName: "photo").font(.largeTitle)
                                Text(loaded ? L10n.text("Preview unavailable") : L10n.text("Loading…")).font(.caption)
                            }.foregroundStyle(.secondary)
                        }
                    }.frame(height: 140).clipShape(RoundedRectangle(cornerRadius: 8))
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.title2).foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                        .background(.background, in: Circle()).padding(8)
                }
                Text(capture.name).font(.headline).lineLimit(1)
                Text(capture.formatLabel).font(.caption.bold())
                if eligibleCount < capture.files.count { Text(L10n.text("%@ of %@ eligible files", String(describing: eligibleCount), String(describing: capture.files.count))).font(.caption) }
                if let date = capture.captureDate {
                    Text(date.timestamp.day.displayText).font(.caption)
                    Text(date.source.label).font(.caption2)
                        .foregroundStyle(date.source.isFallback ? Color.orange : Color.secondary)
                        .lineLimit(1)
                } else {
                    Text(L10n.text("No date available")).font(.caption).foregroundStyle(.secondary)
                }
                Text(capture.directory.isEmpty ? L10n.text("Source folder") : capture.directory)
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            .padding(10)
            .background(.background, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(
                isSelected ? Color.accentColor : Color.secondary.opacity(0.3), lineWidth: isSelected ? 2 : 1
            ))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(capture.name), \(capture.formatLabel)")
        .accessibilityValue(isSelected ? L10n.text("Selected") : L10n.text("Not selected"))
        .help(details)
        .task {
            let image = await loader.image(for: capture, root: root)
            guard !Task.isCancelled else { return }
            thumbnail = image
            loaded = true
        }
    }

    private var details: String {
        var lines = capture.files.map(\.relativePath)
        if let date = capture.captureDate {
            lines.append("\(date.timestamp.displayText) · \(date.source.label) · \(date.relativePath)")
        }
        return lines.joined(separator: "\n")
    }
}
