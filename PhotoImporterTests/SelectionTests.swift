import XCTest
@testable import PhotoImporter

@MainActor
final class SelectionTests: XCTestCase {
    func testInclusiveDateRangeCombinesWithFormat() async throws {
        let early = try XCTUnwrap(PhotoTimestamp.parseEXIF("2026:11:21 00:00:00"))
        let late = try XCTUnwrap(PhotoTimestamp.parseEXIF("2026:11:22 23:59:59"))
        let outside = try XCTUnwrap(PhotoTimestamp.parseEXIF("2026:11:23 00:00:00"))
        let captures = PhotoGrouper.group([
            TestPhotoFixtures.file("early.JPG", metadata: PhotoMetadata(original: early)),
            TestPhotoFixtures.file("late.JPG", metadata: PhotoMetadata(original: late)),
            TestPhotoFixtures.file("late.RW2", metadata: PhotoMetadata(original: late)),
            TestPhotoFixtures.file("outside.JPG", metadata: PhotoMetadata(original: outside)),
            TestPhotoFixtures.file("unknown.RW2")
        ])
        var filter = PhotoFilters(startDay: early.day, endDay: late.day)
        XCTAssertEqual(captures.filter(filter.matches).map(\.name), ["early", "late"])
        filter.format = .raw
        XCTAssertEqual(captures.filter(filter.matches).map(\.name), ["late"])
        filter.startDay = late.day
        XCTAssertEqual(captures.filter(filter.matches).map(\.name), ["late"])
        filter.endDay = early.day
        XCTAssertFalse(filter.isValid)
        XCTAssertTrue(captures.filter(filter.matches).isEmpty)
    }

    func testFallbackDatesParticipateAndUnknownDatesRequireNoDateFilter() async throws {
        let timestamp = try XCTUnwrap(PhotoTimestamp.parseEXIF("2026:11:21 12:00:00"))
        let captures = PhotoGrouper.group([
            TestPhotoFixtures.file("fallback.JPG", metadata: PhotoMetadata(fileCreation: timestamp)),
            TestPhotoFixtures.file("unknown.RW2")
        ])
        XCTAssertEqual(captures.filter(PhotoFilters().matches).count, 2)
        let filter = PhotoFilters(startDay: timestamp.day, endDay: timestamp.day)
        XCTAssertEqual(captures.filter(filter.matches).map(\.name), ["fallback"])
    }

    func testTenPairsCountPhysicalFilesAndBytesByFormat() async throws {
        let root = try TestPhotoFixtures.directory()
        defer { try? FileManager.default.removeItem(at: root) }
        for index in 0..<10 {
            try TestPhotoFixtures.write("P\(index).JPG", root: root)
            try TestPhotoFixtures.write("P\(index).RW2", root: root)
        }
        let model = TestPhotoFixtures.model()
        model.discover(root)
        try await TestPhotoFixtures.waitForDiscovery(model)
        XCTAssertEqual(model.selectedSummary.captureCount, 0)
        model.selectVisible()
        XCTAssertEqual(model.selectedSummary.captureCount, 10)
        XCTAssertEqual(model.selectedSummary.fileCount, 20)
        let total = model.selectedSummary.byteCount

        model.filters.format = .jpeg
        XCTAssertEqual(model.selectedSummary.captureCount, 10)
        XCTAssertEqual(model.selectedSummary.fileCount, 10)
        let jpegBytes = model.selectedSummary.byteCount
        model.filters.format = .raw
        XCTAssertEqual(model.selectedSummary.captureCount, 10)
        XCTAssertEqual(model.selectedSummary.fileCount, 10)
        XCTAssertEqual(jpegBytes + model.selectedSummary.byteCount, total)
        model.clearSelection()
        XCTAssertEqual(model.selectedSummary.byteCount, 0)
        XCTAssertEqual(model.selectedSummary.fileCount, 0)
    }

    func testFiltersPruneHiddenSelectionsWithoutSelectingNewlyVisiblePhotos() async throws {
        let root = try TestPhotoFixtures.directory()
        defer { try? FileManager.default.removeItem(at: root) }
        try TestPhotoFixtures.jpeg("early.JPG", root: root, original: "2026:11:21 00:00:00")
        try TestPhotoFixtures.jpeg("late.JPG", root: root, original: "2026:11:22 23:59:59")
        let model = TestPhotoFixtures.model()
        model.discover(root)
        try await TestPhotoFixtures.waitForDiscovery(model)
        model.selectVisible()
        XCTAssertEqual(model.selectedIDs.count, 2)
        model.setDateRangeEnabled(true)
        XCTAssertEqual(model.selectedIDs.count, 2)
        model.filters.endDay = PhotoDay(year: 2026, month: 11, day: 21)
        XCTAssertEqual(model.visibleCaptures.map(\.name), ["early"])
        XCTAssertEqual(model.selectedIDs.count, 1)
        let hidden = try XCTUnwrap(model.result?.captures.first { $0.name == "late" })
        model.toggleSelection(hidden.id)
        XCTAssertEqual(model.selectedIDs.count, 1)
        model.setDateRangeEnabled(false)
        XCTAssertEqual(model.visibleCaptures.count, 2)
        XCTAssertEqual(model.selectedIDs.count, 1)
        let selected = try XCTUnwrap(model.selectedIDs.first)
        model.toggleSelection(selected)
        XCTAssertTrue(model.selectedIDs.isEmpty)
    }

    func testChangingFormatPrunesIneligibleCapturesAndPreservesAllJPEGVariants() async throws {
        let root = try TestPhotoFixtures.directory()
        defer { try? FileManager.default.removeItem(at: root) }
        for name in ["pair.JPG", "pair.JPEG", "pair.RW2", "jpeg-only.JPG"] {
            try TestPhotoFixtures.write(name, root: root)
        }
        let model = TestPhotoFixtures.model()
        model.discover(root)
        try await TestPhotoFixtures.waitForDiscovery(model)
        model.selectVisible()
        XCTAssertEqual(model.selectedSummary.fileCount, 4)
        model.filters.format = .jpeg
        XCTAssertEqual(model.selectedSummary.fileCount, 3)
        model.filters.format = .raw
        XCTAssertEqual(model.selectedSummary.captureCount, 1)
        XCTAssertEqual(model.selectedSummary.fileCount, 1)
        model.filters.format = .all
        XCTAssertEqual(model.selectedSummary.captureCount, 1)
        XCTAssertEqual(model.selectedSummary.fileCount, 3)
    }

    func testChangingSourceResetsFiltersAndSelection() async throws {
        let first = try TestPhotoFixtures.directory()
        let second = try TestPhotoFixtures.directory()
        defer {
            try? FileManager.default.removeItem(at: first)
            try? FileManager.default.removeItem(at: second)
        }
        try TestPhotoFixtures.write("first.JPG", root: first)
        try TestPhotoFixtures.write("second.RW2", root: second)
        let model = TestPhotoFixtures.model()
        model.discover(first)
        try await TestPhotoFixtures.waitForDiscovery(model)
        model.selectVisible()
        model.filters.format = .jpeg
        model.setDateRangeEnabled(true)
        model.discover(second)
        XCTAssertTrue(model.selectedIDs.isEmpty)
        XCTAssertEqual(model.filters, PhotoFilters())
        try await TestPhotoFixtures.waitForDiscovery(model)
        XCTAssertEqual(model.visibleCaptures.map(\.name), ["second"])
        XCTAssertTrue(model.selectedIDs.isEmpty)
    }
}
