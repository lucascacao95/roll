// Native captures of production views with isolated, code-generated fixtures.
// This file is deliberately outside both Xcode targets.
import AppKit
import SwiftUI
import ImageIO
import UniformTypeIdentifiers

@main struct DemoCapture {
    @MainActor static func main() async throws {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        if let iconURL = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
           let icon = NSImage(contentsOf: iconURL) { NSApp.applicationIconImage = icon }
        guard CommandLine.arguments.count > 1 else { throw CocoaError(.fileNoSuchFile) }
        let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let base = URL(fileURLWithPath: "/private/tmp").appendingPathComponent("RollDemo-" + UUID().uuidString)
        let source = base.appendingPathComponent("Demo Card")
        let archive = base.appendingPathComponent("Demo Archive")
        for folder in [source, archive] { try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true) }
        let keepFixtures = CommandLine.arguments.contains("--keep-fixtures")
        defer { if !keepFixtures { try? FileManager.default.removeItem(at: base) } }
        if keepFixtures { print("Demo folders retained for manual capture: \(base.path)") }
        for index in 1...6 {
            try illustration(index, at: source.appendingPathComponent(String(format: "DEMO%04d.JPG", index)))
            // Extension/grouping fixtures only: these are not camera-decodable RAW images.
            try Data("Synthetic RAW grouping fixture \(index)".utf8)
                .write(to: source.appendingPathComponent(String(format: "DEMO%04d.RW2", index)))
        }
        let domain = "RollDemo." + UUID().uuidString
        let defaults = UserDefaults(suiteName: domain)!
        defer { defaults.removePersistentDomain(forName: domain) }
        let access = LibraryAccess(defaults: defaults)
        access.choose(archive)
        defer { access.forget() }
        let service = ImportService(journalRoot: base.appendingPathComponent("journal"))
        let model = DiscoveryModel(importer: service, preferences: AppPreferences(defaults: defaults), libraryAccess: access)
        model.discover(source)
        try await wait { !model.isScanning }
        guard model.result?.fileCount == 12 else { throw CocoaError(.fileReadCorruptFile) }
        model.eventName = "Demo photo walk"
        model.selectVisible()
        try await render(DiscoveryView(model: model), to: output.appendingPathComponent("import-light.png"))
        try await render(DiscoveryView(model: model), dark: true, to: output.appendingPathComponent("import-dark.png"))
        model.filters.format = .jpeg
        model.setDateRangeEnabled(true)
        try await render(DiscoveryView(model: model), to: output.appendingPathComponent("selection-light.png"))
        model.filters.format = .all
        model.selectVisible()
        // A real import produces the demo history. Its journal lives only under base.
        let plan = try await ImportPlanner().plan(source: source, library: archive,
            captures: model.result!.captures, format: .all, event: model.eventName)
        guard !plan.hasBlockingIssues else { throw CocoaError(.fileWriteUnknown) }
        let report = try await service.run(plan)
        guard report.copiedCount == 12 else { throw CocoaError(.fileWriteUnknown) }
        try await render(DiscoveryView(model: model, initialSection: .history),
                         to: output.appendingPathComponent("history-light.png"))
        try await render(DiscoveryView(model: model, initialSection: .preferences),
                         to: output.appendingPathComponent("settings-light.png"))
        try await render(AboutRollView(), size: NSSize(width: 444, height: 370),
                         to: output.appendingPathComponent("about-light.png"))
        try await captureProgress(source: source, archive: archive, base: base, defaults: defaults, output: output)
        print("Captured production SwiftUI views; copied 12 synthetic files with real verification. No user photos used.")
    }

    @MainActor private static func captureProgress(source: URL, archive: URL, base: URL,
                                                   defaults: UserDefaults, output: URL) async throws {
        // Hold the copy actor at an actual checkpoint so the UI can display real progress.
        let gate = DispatchSemaphore(value: 0)
        defer { gate.signal() }
        let importer = ImportService(journalRoot: base.appendingPathComponent("progress-journal"), checkpoint: { point in
            if point.phase == .beforeVerification {
                guard gate.wait(timeout: .now() + 10) == .success else { throw CancellationError() }
            }
        })
        let model = DiscoveryModel(importer: importer, preferences: AppPreferences(defaults: defaults),
                                   libraryAccess: LibraryAccess(defaults: defaults))
        model.discover(source)
        try await wait { !model.isScanning }
        model.setLibrary(archive)
        model.filters.format = .jpeg
        model.eventName = "Demo progress"
        if let first = model.visibleCaptures.first { model.toggleSelection(first.id) }
        model.generatePlan()
        try await wait { !model.isPlanning }
        guard let plan = model.plan, !plan.hasBlockingIssues else { throw CocoaError(.fileWriteUnknown) }
        model.isShowingPlan = false
        model.startImport()
        try await wait { model.importProgress != nil || !model.isImporting }
        guard model.isImporting else { throw CocoaError(.fileWriteUnknown) }
        try await render(ImportPlanView(plan: plan, model: model), size: NSSize(width: 1100, height: 680),
                         to: output.appendingPathComponent("progress-light.png"))
        gate.signal()
        try await wait { !model.isImporting }
        guard model.importReport?.copiedCount == 1 else { throw CocoaError(.fileWriteUnknown) }
    }

    @MainActor private static func wait(_ condition: () -> Bool) async throws {
        for _ in 0..<500 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        throw CocoaError(.coderInvalidValue)
    }

    @MainActor private static func render<V: View>(_ view: V, size: NSSize = NSSize(width: 1280, height: 1400),
                                                  dark: Bool = false, to url: URL) async throws {
        let host = NSHostingView(rootView: view.environment(\.colorScheme, dark ? .dark : .light)
            .background(Color(nsColor: .windowBackgroundColor)))
        let window = NSWindow(contentRect: NSRect(origin: NSPoint(x: -4000, y: -4000), size: size),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        window.contentView = host
        window.display()
        try await Task.sleep(for: .milliseconds(700))
        host.layoutSubtreeIfNeeded()
        guard let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { throw CocoaError(.fileWriteUnknown) }
        host.cacheDisplay(in: host.bounds, to: bitmap)
        guard let png = bitmap.representation(using: .png, properties: [:]) else { throw CocoaError(.fileWriteUnknown) }
        try png.write(to: url)
        window.orderOut(nil)
    }

    // Original geometric illustrations; no photographs, fonts, network or external assets.
    private static func illustration(_ index: Int, at url: URL) throws {
        guard let ctx = CGContext(data: nil, width: 640, height: 420, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
        else { throw CocoaError(.fileWriteUnknown) }
        let tone = CGFloat(index) / 12
        ctx.setFillColor(CGColor(red: 0.30 + tone / 2, green: 0.48, blue: 0.61, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: 640, height: 420))
        ctx.setFillColor(CGColor(red: 0.95, green: 0.77, blue: 0.40, alpha: 1))
        ctx.fillEllipse(in: CGRect(x: 420 - index * 22, y: 255, width: 85, height: 85))
        for layer in 0..<3 {
            ctx.setFillColor(CGColor(red: 0.15 + CGFloat(layer) * 0.06, green: 0.27 + CGFloat(layer) * 0.05, blue: 0.29, alpha: 1))
            ctx.move(to: CGPoint(x: 0, y: 0))
            ctx.addLine(to: CGPoint(x: 0, y: 80 + layer * 45))
            ctx.addLine(to: CGPoint(x: 140 + index * 15, y: 220 - layer * 35))
            ctx.addLine(to: CGPoint(x: 380, y: 85 + layer * 20))
            ctx.addLine(to: CGPoint(x: 520, y: 180 - layer * 20))
            ctx.addLine(to: CGPoint(x: 640, y: 80))
            ctx.addLine(to: CGPoint(x: 640, y: 0))
            ctx.closePath(); ctx.fillPath()
        }
        guard let image = ctx.makeImage(), let writer = CGImageDestinationCreateWithURL(url as CFURL, UTType.jpeg.identifier as CFString, 1, nil)
        else { throw CocoaError(.fileWriteUnknown) }
        CGImageDestinationAddImage(writer, image, [kCGImagePropertyExifDictionary:
            [kCGImagePropertyExifDateTimeOriginal: "2026:11:21 12:00:00"]] as CFDictionary)
        guard CGImageDestinationFinalize(writer) else { throw CocoaError(.fileWriteUnknown) }
    }
}
