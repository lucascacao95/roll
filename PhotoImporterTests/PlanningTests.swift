import XCTest
@testable import PhotoImporter

@MainActor
final class PlanningTests: XCTestCase {
    func testPathsForEventAndMultipleDaysAndFormat() async throws {
        let source = try TestPhotoFixtures.directory()
        let library = try TestPhotoFixtures.directory()
        defer { remove(source, library) }
        try pair(in: source, folder: "day1", date: "2026:11:21 12:00:00")
        try pair(in: source, folder: "day2", date: "2026:11:22 12:00:00")
        let captures = try await PhotoScanner().scan(root: source).captures
        let all = try await planner().plan(source: source, library: library, captures: captures, format: .all, event: "  Passeio  ")
        XCTAssertTrue(all.blockers.isEmpty)
        XCTAssertEqual(all.event, "Passeio")
        XCTAssertEqual(all.captureCount, 2)
        XCTAssertEqual(all.newCount, 4)
        XCTAssertEqual(Set(all.files.compactMap(\.relativeDestination)), [
            "2026/2026-11-21 - Passeio/JPEG/P100001.JPG", "2026/2026-11-21 - Passeio/RAW/P100001.RW2",
            "2026/2026-11-22 - Passeio/JPEG/P100001.JPG", "2026/2026-11-22 - Passeio/RAW/P100001.RW2"
        ])
        let jpeg = try await planner().plan(source: source, library: library, captures: captures, format: .jpeg, event: "")
        XCTAssertEqual(jpeg.files.count, 2)
        XCTAssertTrue(jpeg.files.allSatisfy { $0.relativeDestination?.contains("/JPEG/") == true })
        XCTAssertEqual(jpeg.files.first?.relativeDestination, "2026/2026-11-21/JPEG/P100001.JPG")
        XCTAssertLessThan(jpeg.estimatedBytes, all.estimatedBytes)
    }

    func testPlanDoesNotCreateOrChangeAnythingInSourceAndLibrary() async throws {
        let source = try TestPhotoFixtures.directory()
        let library = try TestPhotoFixtures.directory()
        defer { remove(source, library) }
        try pair(in: source)
        try TestPhotoFixtures.write("untouched.txt", root: library)
        let beforeSource = try snapshot(source)
        let beforeLibrary = try snapshot(library)
        let captures = try await PhotoScanner().scan(root: source).captures
        let plan = try await planner().plan(source: source, library: library, captures: captures, format: .all, event: "Passeio")
        XCTAssertEqual(plan.newCount, 2)
        XCTAssertEqual(try snapshot(source), beforeSource)
        XCTAssertEqual(try snapshot(library), beforeLibrary)
    }

    func testExistingFileIsNotCalledDuplicateEvenWithSameSize() async throws {
        let source = try TestPhotoFixtures.directory()
        let library = try TestPhotoFixtures.directory()
        defer { remove(source, library) }
        try pair(in: source)
        let captures = try await PhotoScanner().scan(root: source).captures
        let file = try XCTUnwrap(captures.first?.jpeg)
        let path = "2026/2026-11-21/JPEG/P100001.JPG"
        let destination = try TestPhotoFixtures.write(path, root: library)
        try Data(repeating: 0, count: Int(file.byteCount)).write(to: destination)
        let before = try snapshot(library)
        let plan = try await planner().plan(source: source, library: library, captures: captures, format: .all, event: "")
        XCTAssertEqual(plan.existingCount, 1)
        XCTAssertEqual(plan.newCount, 1)
        XCTAssertEqual(plan.files.first { $0.source.format == .jpeg }?.state, .existing)
        XCTAssertEqual(try snapshot(library), before)
    }

    func testNamesFromDifferentSourceFoldersCollideWithoutRenaming() async throws {
        let source = try TestPhotoFixtures.directory()
        let library = try TestPhotoFixtures.directory()
        defer { remove(source, library) }
        try pair(in: source, folder: "one")
        try pair(in: source, folder: "two")
        let captures = try await PhotoScanner().scan(root: source).captures
        let plan = try await planner().plan(source: source, library: library, captures: captures, format: .all, event: "")
        XCTAssertEqual(plan.blockedCount, 4)
        XCTAssertTrue(plan.files.allSatisfy { $0.state.detail.contains("Conflito") })
        XCTAssertEqual(Set(plan.files.compactMap(\.relativeDestination)).count, 2)
    }

    func testCaseRulesAndCanonicalUnicodeCollisions() async throws {
        let source = try TestPhotoFixtures.directory()
        let library = try TestPhotoFixtures.directory()
        defer { remove(source, library) }
        for (folder, name) in [("one", "Photo.JPG"), ("two", "photo.JPG"),
                               ("three", "Café.JPG"), ("four", "Cafe\u{301}.JPG")] {
            let directory = source.appendingPathComponent(folder)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try TestPhotoFixtures.jpeg(name, root: directory, original: "2026:11:21 12:00:00")
        }
        let captures = try await PhotoScanner().scan(root: source).captures
        let insensitive = try await planner(caseSensitive: false).plan(source: source, library: library, captures: captures, format: .all, event: "")
        XCTAssertEqual(insensitive.blockedCount, 4)
        let sensitive = try await planner(caseSensitive: true).plan(source: source, library: library, captures: captures, format: .all, event: "")
        XCTAssertEqual(sensitive.blockedCount, 2) // Unicode-equivalent paths remain conservatively conflicting.
        let unknown = try await planner(caseSensitive: nil).plan(source: source, library: library, captures: captures, format: .all, event: "")
        XCTAssertEqual(unknown.blockedCount, 4)
        XCTAssertTrue(unknown.notes.contains { $0.contains("Sensibilidade") })
    }

    func testExistingCaseVariantUsesDestinationNameRules() async throws {
        let source = try TestPhotoFixtures.directory()
        let library = try TestPhotoFixtures.directory()
        defer { remove(source, library) }
        try pair(in: source)
        try TestPhotoFixtures.write("2026/2026-11-21/jpeg/p100001.jpg", root: library)
        let captures = try await PhotoScanner().scan(root: source).captures
        let plan = try await planner(caseSensitive: false).plan(source: source, library: library, captures: captures, format: .jpeg, event: "")
        XCTAssertEqual(plan.existingCount, 1)
    }

    func testOverlapInBothDirectionsAndThroughAncestorAlias() async throws {
        let outer = try TestPhotoFixtures.directory()
        defer { remove(outer) }
        let source = outer.appendingPathComponent("sd")
        let inside = source.appendingPathComponent("inside")
        try FileManager.default.createDirectory(at: inside, withIntermediateDirectories: true)
        try pair(in: source)
        let captures = try await PhotoScanner().scan(root: source).captures
        for library in [source, inside, outer] {
            let plan = try await planner().plan(source: source, library: library, captures: captures, format: .all, event: "")
            XCTAssertTrue(plan.blockers.contains(L10n.text("The source and archive must be different folders and cannot contain each other.")))
        }
        let alias = outer.appendingPathComponent("alias")
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: source)
        let plan = try await planner().plan(source: source, library: alias.appendingPathComponent("inside"), captures: captures, format: .all, event: "")
        XCTAssertTrue(plan.hasBlockingIssues)
        XCTAssertTrue(plan.blockers.contains(L10n.text("The source and archive must be different folders and cannot contain each other.")))
    }

    func testSiblingWithSamePrefixDoesNotOverlap() async throws {
        let outer = try TestPhotoFixtures.directory()
        defer { remove(outer) }
        let source = outer.appendingPathComponent("sd")
        let library = outer.appendingPathComponent("sd-copy")
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: library, withIntermediateDirectories: true)
        try pair(in: source)
        let captures = try await PhotoScanner().scan(root: source).captures
        let plan = try await planner().plan(source: source, library: library, captures: captures, format: .all, event: "")
        XCTAssertFalse(plan.hasBlockingIssues)
        XCTAssertEqual(plan.newCount, 2)
    }

    func testDestinationSymlinkAndBrokenFinalLinkAreBlocked() async throws {
        let source = try TestPhotoFixtures.directory()
        let library = try TestPhotoFixtures.directory()
        let outside = try TestPhotoFixtures.directory()
        defer { remove(source, library, outside) }
        try pair(in: source)
        let captures = try await PhotoScanner().scan(root: source).captures
        let year = library.appendingPathComponent("2026")
        try FileManager.default.createSymbolicLink(at: year, withDestinationURL: outside)
        let escaping = try await planner().plan(source: source, library: library, captures: captures, format: .all, event: "")
        XCTAssertEqual(escaping.blockedCount, 2)
        XCTAssertTrue(escaping.files.allSatisfy { $0.state.detail.contains("Link simbólico") })
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: outside.path).isEmpty)
        try FileManager.default.removeItem(at: year)
        let parent = library.appendingPathComponent("2026/2026-11-21/JPEG")
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: parent.appendingPathComponent("P100001.JPG"),
                                                   withDestinationURL: outside.appendingPathComponent("missing.JPG"))
        let broken = try await planner().plan(source: source, library: library, captures: captures, format: .jpeg, event: "")
        XCTAssertEqual(broken.blockedCount, 1)
        XCTAssertEqual(broken.existingCount, 0)
    }

    func testFileInPlaceOfDirectoryAndDirectoryInPlaceOfFileAreBlocked() async throws {
        let source = try TestPhotoFixtures.directory()
        let library = try TestPhotoFixtures.directory()
        defer { remove(source, library) }
        try pair(in: source)
        let captures = try await PhotoScanner().scan(root: source).captures
        try TestPhotoFixtures.write("2026", root: library)
        let parentBlocked = try await planner().plan(source: source, library: library, captures: captures, format: .all, event: "")
        XCTAssertEqual(parentBlocked.blockedCount, 2)
        try FileManager.default.removeItem(at: library.appendingPathComponent("2026"))
        try FileManager.default.createDirectory(at: library.appendingPathComponent("2026/2026-11-21/JPEG/P100001.JPG"), withIntermediateDirectories: true)
        let finalBlocked = try await planner().plan(source: source, library: library, captures: captures, format: .jpeg, event: "")
        XCTAssertEqual(finalBlocked.blockedCount, 1)
    }

    func testMissingLibraryAndUnreadableParentDoNotLookLikeFreePaths() async throws {
        let source = try TestPhotoFixtures.directory()
        let library = try TestPhotoFixtures.directory()
        defer { remove(source, library) }
        try pair(in: source)
        let captures = try await PhotoScanner().scan(root: source).captures
        let missing = library.appendingPathComponent("missing")
        let absent = try await planner().plan(source: source, library: missing, captures: captures, format: .all, event: "")
        XCTAssertTrue(absent.hasBlockingIssues)
        XCTAssertFalse(FileManager.default.fileExists(atPath: missing.path))
        let year = library.appendingPathComponent("2026")
        try FileManager.default.createDirectory(at: year, withIntermediateDirectories: true)
        try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: year.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: year.path) }
        let denied = try await planner().plan(source: source, library: library, captures: captures, format: .all, event: "")
        XCTAssertEqual(denied.blockedCount, 2)
        XCTAssertEqual(denied.newCount, 0)
    }

    func testCapacityAndReadOnlyVolumeAreExplicit() async throws {
        let source = try TestPhotoFixtures.directory()
        let library = try TestPhotoFixtures.directory()
        defer { remove(source, library) }
        try pair(in: source)
        let captures = try await PhotoScanner().scan(root: source).captures
        let full = try await planner(capacity: 0).plan(source: source, library: library, captures: captures, format: .all, event: "")
        XCTAssertTrue(full.blockers.contains { $0.contains("Espaço insuficiente") })
        let unknown = try await planner(capacity: nil).plan(source: source, library: library, captures: captures, format: .all, event: "")
        XCTAssertTrue(unknown.blockers.contains { $0.contains("espaço disponível") })
        let readOnly = try await planner(readOnly: true).plan(source: source, library: library, captures: captures, format: .all, event: "")
        XCTAssertTrue(readOnly.blockers.contains { $0.contains("somente leitura") })
    }

    func testInvalidEventAndUnknownDateHaveNoInventedDestination() async throws {
        let source = try TestPhotoFixtures.directory()
        let library = try TestPhotoFixtures.directory()
        defer { remove(source, library) }
        try pair(in: source)
        let captures = try await PhotoScanner().scan(root: source).captures
        for event in ["../escape", "A/B", "A\\B", "..", "A:B", "A\nB", String(repeating: "a", count: 243)] {
            let plan = try await planner().plan(source: source, library: library, captures: captures, format: .all, event: event)
            XCTAssertTrue(plan.hasBlockingIssues, event)
            XCTAssertTrue(plan.files.allSatisfy { $0.relativeDestination == nil })
        }
        var unknownFiles = captures.flatMap(\.files)
        for index in unknownFiles.indices { unknownFiles[index].metadata = PhotoMetadata() }
        let undated = try await planner().plan(source: source, library: library, captures: PhotoGrouper.group(unknownFiles), format: .all, event: "")
        XCTAssertEqual(undated.blockedCount, 2)
        XCTAssertTrue(undated.files.allSatisfy { $0.relativeDestination == nil && $0.state.detail.contains("sem data") })
    }

    func testSourceRemovedOrChangedAfterDiscoveryIsBlocked() async throws {
        let source = try TestPhotoFixtures.directory()
        let library = try TestPhotoFixtures.directory()
        defer { remove(source, library) }
        try pair(in: source)
        let captures = try await PhotoScanner().scan(root: source).captures
        try FileManager.default.removeItem(at: source.appendingPathComponent("P100001.JPG"))
        try Data("changed size".utf8).write(to: source.appendingPathComponent("P100001.RW2"))
        let plan = try await planner().plan(source: source, library: library, captures: captures, format: .all, event: "")
        XCTAssertEqual(plan.blockedCount, 2)
    }

    func testCancelledPlanningDoesNotReturnAPlan() async throws {
        let source = try TestPhotoFixtures.directory()
        let library = try TestPhotoFixtures.directory()
        defer { remove(source, library) }
        let planner = planner()
        let task = Task { try await planner.plan(source: source, library: library, captures: [], format: .all, event: "") }
        task.cancel()
        do { _ = try await task.value; XCTFail("Cancelled planning should not complete") }
        catch { XCTAssertTrue(error is CancellationError) }
    }

    func testModelInvalidatesCompletedAndInFlightPlans() async throws {
        let source = try TestPhotoFixtures.directory()
        let library = try TestPhotoFixtures.directory()
        let another = try TestPhotoFixtures.directory()
        defer { remove(source, library, another) }
        try pair(in: source)
        let model = TestPhotoFixtures.model()
        model.discover(source)
        try await TestPhotoFixtures.waitForDiscovery(model)
        model.setLibrary(library)
        model.selectVisible()
        for change in [{ model.eventName = "Passeio" }, { model.filters.format = .jpeg },
                       { model.setDateRangeEnabled(true) }, { model.setLibrary(another) }] {
            try await generate(model)
            change()
            XCTAssertNil(model.plan)
            XCTAssertFalse(model.isShowingPlan)
        }
        try await generate(model)
        model.clearSelection()
        XCTAssertNil(model.plan)
        model.selectVisible()
        model.generatePlan()
        model.eventName = "Evento atualizado"
        try await generate(model)
        XCTAssertEqual(model.plan?.event, "Evento atualizado")
        model.discover(source)
        XCTAssertNil(model.plan)
        XCTAssertFalse(model.isShowingPlan)
        try await TestPhotoFixtures.waitForDiscovery(model)
    }

    private func generate(_ model: DiscoveryModel) async throws {
        model.generatePlan()
        for _ in 0..<500 {
            if !model.isPlanning { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertFalse(model.isPlanning)
        XCTAssertNil(model.planningError)
        _ = try XCTUnwrap(model.plan)
    }

    private func planner(capacity: Int64? = Int64.max, caseSensitive: Bool? = true, readOnly: Bool? = false) -> ImportPlanner {
        ImportPlanner { _ in
            LibraryVolumeInfo(name: "Test SSD", availableBytes: capacity, isCaseSensitive: caseSensitive,
                              isReadOnly: readOnly, isInternal: false)
        }
    }

    private func pair(in source: URL, folder: String = "", date: String = "2026:11:21 12:00:00") throws {
        let directory = folder.isEmpty ? source : source.appendingPathComponent(folder)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try TestPhotoFixtures.jpeg("P100001.JPG", root: directory, original: date)
        try TestPhotoFixtures.write("P100001.RW2", root: directory)
    }

    private func remove(_ urls: URL...) { for url in urls { try? FileManager.default.removeItem(at: url) } }

    private struct Snapshot: Equatable {
        let data: Data?
        let modified: Date?
        let created: Date?
    }

    private func snapshot(_ root: URL) throws -> [String: Snapshot] {
        let enumerator = try XCTUnwrap(FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil))
        let children = enumerator.allObjects as? [URL] ?? []
        var result: [String: Snapshot] = [:]
        for url in [root] + children {
            let values = try url.resourceValues(forKeys: [.isRegularFileKey, .creationDateKey, .contentModificationDateKey])
            result[url.path] = Snapshot(data: values.isRegularFile == true ? try Data(contentsOf: url) : nil,
                                        modified: values.contentModificationDate, created: values.creationDate)
        }
        return result
    }
}
