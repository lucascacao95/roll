import XCTest
import AppKit
@testable import PhotoImporter

@MainActor
final class PreferencesTests: XCTestCase {
    private func settings() -> (UserDefaults, String) {
        let name = "PhotoImporterTests.\(UUID())"
        return (UserDefaults(suiteName: name)!, name)
    }

    func testPreferencesRoundTripAndSafeDefaultsForInvalidValues() {
        let (defaults, name) = settings()
        defer { defaults.removePersistentDomain(forName: name) }
        let first = AppPreferences(defaults: defaults)
        XCTAssertEqual(first.filters, PhotoFilters())
        XCTAssertEqual(first.organization, FolderOrganization())
        first.format = .jpeg
        first.onlyNotImported = true
        first.organization = FolderOrganization(yearFolder: false, formatFolders: false)
        let restored = AppPreferences(defaults: defaults)
        XCTAssertEqual(restored.format, .jpeg)
        XCTAssertTrue(restored.onlyNotImported)
        XCTAssertFalse(restored.organization.yearFolder)
        XCTAssertFalse(restored.organization.formatFolders)
        defaults.set("unknown", forKey: "defaultFormat")
        defaults.set(Data("invalid".utf8), forKey: "organization")
        let invalid = AppPreferences(defaults: defaults)
        XCTAssertEqual(invalid.format, .all)
        XCTAssertEqual(invalid.organization, FolderOrganization())
    }

    func testDiscoveryUsesDefaultsWithoutPersistingSessionFilters() async throws {
        let (defaults, name) = settings()
        defer { defaults.removePersistentDomain(forName: name) }
        let preferences = AppPreferences(defaults: defaults)
        preferences.format = .jpeg
        let source = try TestPhotoFixtures.directory()
        defer { try? FileManager.default.removeItem(at: source) }
        try TestPhotoFixtures.write("pair.JPG", root: source)
        try TestPhotoFixtures.write("pair.RW2", root: source)
        let model = DiscoveryModel(preferences: preferences, libraryAccess: LibraryAccess(defaults: defaults))
        model.discover(source)
        try await TestPhotoFixtures.waitForDiscovery(model)
        model.selectVisible()
        XCTAssertEqual(model.selectedSummary.fileCount, 1)
        model.filters.format = .raw
        XCTAssertEqual(preferences.format, .jpeg)
        model.discover(source)
        try await TestPhotoFixtures.waitForDiscovery(model)
        XCTAssertEqual(model.filters.format, .jpeg)
        XCTAssertTrue(model.selectedIDs.isEmpty)
    }

    func testNativeBookmarkRestoresSameFolderAndForgetOnlyRemovesPreference() throws {
        let (defaults, name) = settings()
        defer { defaults.removePersistentDomain(forName: name) }
        let folder = try TestPhotoFixtures.directory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = try TestPhotoFixtures.write("original.JPG", root: folder)
        let content = try Data(contentsOf: file)
        let access = LibraryAccess(defaults: defaults)
        access.choose(folder)
        XCTAssertEqual(access.url?.resolvingSymlinksInPath(), folder.resolvingSymlinksInPath(), access.status)
        let restored = LibraryAccess(defaults: defaults)
        XCTAssertEqual(restored.url?.resolvingSymlinksInPath(), folder.resolvingSymlinksInPath(), restored.status)
        restored.forget()
        XCTAssertNil(restored.url)
        XCTAssertNil(defaults.data(forKey: "libraryBookmark"))
        XCTAssertEqual(try Data(contentsOf: file), content)
        access.forget()
    }

    func testSavedIdentityRejectsAnotherFolderAndSymlink() throws {
        let folder = try TestPhotoFixtures.directory()
        let other = try TestPhotoFixtures.directory()
        defer {
            try? FileManager.default.removeItem(at: folder)
            try? FileManager.default.removeItem(at: other)
        }
        let identity = try SavedLibrary.capture(folder, bookmark: Data())
        XCTAssertNoThrow(try identity.validate(folder))
        XCTAssertThrowsError(try identity.validate(other))
        let link = other.appendingPathComponent("link")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: folder)
        XCTAssertThrowsError(try identity.validate(link))
    }

    func testMissingLibraryAndCorruptBookmarkDoNotRestoreFromPath() throws {
        let (defaults, name) = settings()
        defer { defaults.removePersistentDomain(forName: name) }
        let folder = try TestPhotoFixtures.directory()
        let access = LibraryAccess(defaults: defaults)
        access.choose(folder)
        XCTAssertNotNil(access.url, access.status)
        try FileManager.default.removeItem(at: folder)
        access.reconnect()
        XCTAssertNil(access.url)
        XCTAssertNotNil(access.savedPath)
        defaults.set(Data("broken".utf8), forKey: "libraryBookmark")
        let invalid = LibraryAccess(defaults: defaults)
        XCTAssertNil(invalid.url)
        XCTAssertTrue(invalid.status.contains("inválida"))
        access.forget()
    }

    func testVolumeChangeClearsDiscoverySelectionAndPlan() async throws {
        let (defaults, name) = settings()
        defer { defaults.removePersistentDomain(forName: name) }
        let source = try TestPhotoFixtures.directory()
        let library = try TestPhotoFixtures.directory()
        defer {
            try? FileManager.default.removeItem(at: source)
            try? FileManager.default.removeItem(at: library)
        }
        try TestPhotoFixtures.jpeg("one.JPG", root: source, original: "2026:11:21 12:00:00")
        let access = LibraryAccess(defaults: defaults)
        access.choose(library)
        let model = DiscoveryModel(preferences: AppPreferences(defaults: defaults), libraryAccess: access)
        model.discover(source)
        try await TestPhotoFixtures.waitForDiscovery(model)
        model.selectVisible()
        model.generatePlan()
        while model.isPlanning { await Task.yield() }
        XCTAssertNotNil(model.plan)
        NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.didMountNotification, object: nil)
        XCTAssertNil(model.plan)
        XCTAssertNil(model.result)
        XCTAssertTrue(model.selectedIDs.isEmpty)
        XCTAssertNotNil(model.libraryRoot)
        XCTAssertFalse(model.isImporting)
        access.forget()
    }

    func testAllOrganizationOptionsAndCollisionsUsePlanner() async throws {
        let source = try TestPhotoFixtures.directory()
        let library = try TestPhotoFixtures.directory()
        defer {
            try? FileManager.default.removeItem(at: source)
            try? FileManager.default.removeItem(at: library)
        }
        try TestPhotoFixtures.jpeg("one.JPG", root: source, original: "2026:11:21 12:00:00")
        let captures = try await PhotoScanner().scan(root: source).captures
        for year in [true, false] {
            for formats in [true, false] {
                let plan = try await ImportPlanner().plan(source: source, library: library, captures: captures,
                    format: .all, event: "Passeio", organization: FolderOrganization(yearFolder: year, formatFolders: formats))
                XCTAssertFalse(plan.hasBlockingIssues)
                XCTAssertEqual(plan.files.first?.relativeDestination,
                    (year ? "2026/" : "") + "2026-11-21 - Passeio/" + (formats ? "JPEG/" : "") + "one.JPG")
            }
        }
        try FileManager.default.createDirectory(at: source.appendingPathComponent("another"), withIntermediateDirectories: true)
        try TestPhotoFixtures.jpeg("another/one.JPG", root: source, original: "2026:11:21 12:00:00")
        let all = try await PhotoScanner().scan(root: source).captures
        let collision = try await ImportPlanner().plan(source: source, library: library, captures: all,
            format: .all, event: "", organization: FolderOrganization(yearFolder: false, formatFolders: false))
        XCTAssertEqual(collision.blockedCount, 2)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: library.path), [])
    }
    func testBookmarkNeverAcceptsReplacementAtOldPath() throws {
        let (defaults, name) = settings()
        defer { defaults.removePersistentDomain(forName: name) }
        let parent = try TestPhotoFixtures.directory()
        defer { try? FileManager.default.removeItem(at: parent) }
        let folder = parent.appendingPathComponent("Library")
        let renamed = parent.appendingPathComponent("Renamed")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let access = LibraryAccess(defaults: defaults)
        access.choose(folder)
        XCTAssertNotNil(access.url, access.status)
        try FileManager.default.moveItem(at: folder, to: renamed)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        access.reconnect()
        // Native resolution can choose the replacement path. Identity validation must refuse it.
        XCTAssertNotEqual(access.url?.resolvingSymlinksInPath(), folder.resolvingSymlinksInPath())
        if let resolved = access.url {
            XCTAssertEqual(resolved.resolvingSymlinksInPath(), renamed.resolvingSymlinksInPath())
        } else {
            XCTAssertTrue(access.status.contains("identidade"))
        }
        access.forget()
    }

    func testChangedOrganizationRequiresNewPlanThenCopiesToChosenLayout() async throws {
        let (defaults, name) = settings()
        defer { defaults.removePersistentDomain(forName: name) }
        let source = try TestPhotoFixtures.directory()
        let library = try TestPhotoFixtures.directory()
        let journal = try TestPhotoFixtures.directory()
        defer {
            for url in [source, library, journal] { try? FileManager.default.removeItem(at: url) }
        }
        let original = try TestPhotoFixtures.jpeg("one.JPG", root: source, original: "2026:11:21 12:00:00")
        let snapshot = try XCTUnwrap(PlanningPaths.node(at: original)?.snapshot)
        let preferences = AppPreferences(defaults: defaults)
        let model = DiscoveryModel(importer: ImportService(journalRoot: journal), preferences: preferences,
                                   libraryAccess: LibraryAccess(defaults: defaults))
        model.setLibrary(library)
        model.discover(source)
        try await TestPhotoFixtures.waitForDiscovery(model)
        model.selectVisible()
        model.generatePlan()
        while model.isPlanning { await Task.yield() }
        XCTAssertNotNil(model.plan)
        preferences.organization = FolderOrganization(yearFolder: false, formatFolders: false)
        model.startImport()
        XCTAssertFalse(model.isImporting)
        XCTAssertNil(model.plan)
        XCTAssertNotNil(model.planningError)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: library.path), [])
        model.generatePlan()
        while model.isPlanning { await Task.yield() }
        XCTAssertEqual(model.plan?.files.first?.relativeDestination, "2026-11-21/one.JPG")
        model.startImport()
        XCTAssertTrue(model.isImporting)
        model.volumesChanged() // During copying, defer access refresh and keep the final report.
        for _ in 0..<500 {
            if !model.isImporting { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertFalse(model.isImporting)
        XCTAssertNil(model.importError)
        XCTAssertEqual(model.importReport?.files.first?.status, .copied)
        XCTAssertNil(model.result)
        XCTAssertTrue(model.isShowingPlan)
        XCTAssertTrue(model.selectedIDs.isEmpty)
        XCTAssertEqual(try Data(contentsOf: library.appendingPathComponent("2026-11-21/one.JPG")), try Data(contentsOf: original))
        XCTAssertEqual(try PlanningPaths.node(at: original)?.snapshot, snapshot)
    }

}
