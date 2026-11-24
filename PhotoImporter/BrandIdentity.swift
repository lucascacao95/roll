import SwiftUI

/// Brand colors are accents; backgrounds and safety states keep native semantics.
enum RollBrand {
    static let amber = Color("BrandAmber")
    static let olive = Color("BrandOlive")
    static let ivory = Color("BrandIvory")
    static let charcoal = Color("BrandCharcoal")
}

struct RollWordmark: View {
    @Environment(\.colorScheme) private var colorScheme
    var body: some View {
        HStack(spacing: 0) {
            Text("roll").foregroundStyle(colorScheme == .dark ? RollBrand.ivory : RollBrand.charcoal)
            Text(".").foregroundStyle(RollBrand.amber)
        }.font(.system(size: 26, weight: .semibold)).tracking(-0.6)
            .accessibilityElement(children: .ignore).accessibilityLabel("Roll")
    }
}

struct AboutRollView: View {
    private var version: String {
        let info = Bundle.main.infoDictionary ?? [:]
        return "\(info["CFBundleShortVersionString"] as? String ?? "—") (\(info["CFBundleVersion"] as? String ?? "—"))"
    }
    var body: some View {
        VStack(spacing: 16) {
            // The original code-generated artwork is shared with Finder and Dock through the app bundle.
            Image(nsImage: NSApplication.shared.applicationIconImage)
                .resizable().interpolation(.high).scaledToFit().frame(width: 72, height: 72)
                .accessibilityHidden(true)
            RollWordmark()
            Text("From capture to collection.").font(.subheadline).foregroundStyle(.secondary)
            Text(L10n.text("Version %@", version)).font(.caption).foregroundStyle(.secondary)
            Text(L10n.text("A native macOS photography utility for importing and organizing your own files."))
                .multilineTextAlignment(.center)
            Divider()
            Text(L10n.text("Originals stay on your card. A verified import is not an independent backup."))
                .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }.padding(32).frame(width: 380).fixedSize(horizontal: false, vertical: true)
            .background(Color(nsColor: .windowBackgroundColor))
    }
}

struct RollSettingsActionKey: FocusedValueKey {
    typealias Value = () -> Void
}

extension FocusedValues {
    var rollShowSettings: (() -> Void)? {
        get { self[RollSettingsActionKey.self] }
        set { self[RollSettingsActionKey.self] = newValue }
    }
}

struct RollCommands: Commands {
    @Environment(\.openWindow) private var openWindow
    @FocusedValue(\.rollShowSettings) private var showSettings

    var body: some Commands {
        CommandGroup(replacing: .appInfo) {
            Button(L10n.text("About Roll")) { openWindow(id: "about-roll") }
        }
        CommandGroup(replacing: .appSettings) {
            Button(L10n.text("Settings…")) { showSettings?() }
                .keyboardShortcut(",", modifiers: .command).disabled(showSettings == nil)
        }
    }
}
