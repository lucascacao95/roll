import SwiftUI

struct PreferencesView: View {
    @Bindable var model: DiscoveryModel

    var body: some View {
        @Bindable var preferences = model.preferences
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                PageHeading(title: L10n.text("Settings"), subtitle: L10n.text("Configure your archive and import organization."))
                section(L10n.text("Photo archive"), subtitle: L10n.text("The destination folder for your photos, preferably on an external SSD."), symbol: "externaldrive") {
                    HStack {
                        Label(model.libraryAccess.savedPath ?? L10n.text("No saved folder"), systemImage: "folder.fill")
                            .lineLimit(2).textSelection(.enabled)
                        Spacer()
                        Button(L10n.text("Choose Folder…"), action: model.chooseLibrary)
                    }
                    Text(model.libraryAccess.status).font(.caption).foregroundStyle(.secondary)
                    HStack {
                        Button(L10n.text("Reconnect"), action: model.reconnectLibrary)
                        Button(L10n.text("Forget Folder"), action: model.forgetLibrary).disabled(model.libraryAccess.savedPath == nil)
                        Spacer()
                        if let free = model.libraryAccess.volume?.availableBytes {
                            Text(ByteCountFormatter.string(fromByteCount: free, countStyle: .file) + L10n.text(" available at last connection"))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                section(L10n.text("Folder organization"), subtitle: L10n.text("Set the structure for future import previews. Original filenames are preserved."), symbol: "folder.fill") {
                    HStack(spacing: 22) {
                        Toggle(L10n.text("Year"), isOn: $preferences.organization.yearFolder)
                        Label(L10n.text("Date"), systemImage: "checkmark.square.fill").foregroundStyle(.secondary)
                        Toggle(L10n.text("Format (RAW / JPEG)"), isOn: $preferences.organization.formatFolders)
                    }.toggleStyle(.checkbox)
                    Text(L10n.text("A date folder is required. The event is optional and set in New Roll.")).font(.caption).foregroundStyle(.secondary)
                    Divider()
                    Label(preferences.organization.description, systemImage: "folder")
                        .font(.callout).padding(12).frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.accentColor.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
                    Text(L10n.text("Resumed imports keep their recorded destinations.")).font(.caption).foregroundStyle(.secondary)
                }
                section(L10n.text("Default format"), subtitle: L10n.text("Applied when scanning a new source."), symbol: "photo.on.rectangle") {
                    Picker(L10n.text("Files"), selection: $preferences.format) {
                        ForEach(PhotoFormatFilter.allCases, id: \.self) { Text($0.label).tag($0) }
                    }.frame(maxWidth: 400)
                    Button(L10n.text("Apply Defaults to Current Filters"), action: model.applyDefaults)
                }
                section(L10n.text("Already imported files"), subtitle: L10n.text("Existing content is verified before skipping a copy."), symbol: "doc.on.doc") {
                    Label(L10n.text("Existing files are never overwritten"), systemImage: "checkmark.shield").font(.headline)
                    Toggle(L10n.text("Show only photos not yet imported by default"), isOn: $preferences.onlyNotImported)
                    Text(L10n.text("Only files with matching source and destination SHA-256 checksums are hidden. Name, date or size alone do not prove a duplicate."))
                        .font(.callout).foregroundStyle(.secondary)
                }
                section(L10n.text("Safety"), subtitle: L10n.text("Import verification and integrity."), symbol: "checkmark.shield") {
                    Label(L10n.text("SHA-256 verification is required after copying"), systemImage: "checkmark.square.fill")
                    Text(L10n.text("The final file is published only after size and content verification, without overwriting another file."))
                        .font(.callout).foregroundStyle(.secondary)
                    InformationBanner(title: L10n.text("Roll never erases your SD card."), message: L10n.text("Originals remain untouched. A verified import is not an independent backup."))
                }
            }.padding(30).disabled(model.isImporting)
        }
    }

    private func section<Content: View>(_ title: String, subtitle: String, symbol: String,
                                        @ViewBuilder content: () -> Content) -> some View {
        SurfaceCard {
            HStack(alignment: .top, spacing: 22) {
                Image(systemName: symbol).font(.system(size: 36)).foregroundStyle(symbol == "folder.fill" ? Color.accentColor : Color.secondary)
                    .frame(width: 55).padding(.top, 4).accessibilityHidden(true)
                Divider()
                VStack(alignment: .leading, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(title).font(.title3.bold())
                        Text(subtitle).font(.callout).foregroundStyle(.secondary)
                    }
                    content()
                }.frame(maxWidth: .infinity, alignment: .leading)
            }.fixedSize(horizontal: false, vertical: true)
        }
    }
}
