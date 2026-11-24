import SwiftUI

@main
struct PhotoImporterApp: App {
    var body: some Scene {
        WindowGroup("Roll") {
            DiscoveryView()
                .frame(minWidth: 1040, minHeight: 740)
        }
        .defaultSize(width: 1_280, height: 880)
        .commands { RollCommands() }

        Window(L10n.text("About Roll"), id: "about-roll") {
            AboutRollView()
        }.windowResizability(.contentSize)
    }
}
