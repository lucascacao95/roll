import XCTest
@testable import PhotoImporter

@MainActor
final class MetadataTests: XCTestCase {
    func testStrictEXIFParsingRejectsInvalidDatesAndTimes() async throws {
        let valid = try XCTUnwrap(PhotoTimestamp.parseEXIF("2024:02:29 23:59:59"))
        XCTAssertEqual(valid.day, PhotoDay(year: 2024, month: 2, day: 29))
        XCTAssertEqual(valid.hour, 23)
        for text in ["2026:02:29 12:00:00", "2026:04:31 12:00:00", "0000:01:01 00:00:00",
                     "2026:00:21 12:00:00", "2026:11:00 12:00:00", "2026:11:21 24:00:00",
                     "2026:11:21 12:60:00", "2026:11:21 12:00:60", "2026-11-21 12:00:00",
                     "2026:11:21", "2026:11:21 12:00:00 garbage", "    :  :     :  :  "] {
            XCTAssertNil(PhotoTimestamp.parseEXIF(text), text)
        }
        XCTAssertNil(PhotoTimestamp.parseEXIF(nil))
    }

    func testImageIOReadsEXIFWithoutShiftingCameraDay() async throws {
        let root = try TestPhotoFixtures.directory()
        defer { try? FileManager.default.removeItem(at: root) }
        try TestPhotoFixtures.jpeg("east.JPG", root: root, original: "2026:11:21 00:01:02",
                                   digitized: "2026:11:22 12:00:00", offset: "+14:00")
        try TestPhotoFixtures.jpeg("west.JPG", root: root, original: "2026:11:21 23:59:58", offset: "-12:00")
        let result = try await PhotoScanner().scan(root: root)
        XCTAssertEqual(result.captures.count, 2)
        for capture in result.captures {
            let date = try XCTUnwrap(capture.captureDate)
            XCTAssertEqual(date.source, .original)
            XCTAssertEqual(date.timestamp.day, PhotoDay(year: 2026, month: 11, day: 21))
            XCTAssertFalse(date.source.isFallback)
        }
        XCTAssertEqual(result.captures.first?.captureDate?.timestamp.hour, 0)
        XCTAssertEqual(result.captures.last?.captureDate?.timestamp.hour, 23)
    }

    func testInvalidOriginalUsesDigitizedDateBeforeFilesystem() async throws {
        let root = try TestPhotoFixtures.directory()
        defer { try? FileManager.default.removeItem(at: root) }
        try TestPhotoFixtures.jpeg("capture.JPG", root: root, original: "2026:02:30 12:00:00",
                                   digitized: "2025:03:04 05:06:07")
        let result = try await PhotoScanner().scan(root: root)
        let date = try XCTUnwrap(result.captures.first?.captureDate)
        XCTAssertEqual(date.source, .digitized)
        XCTAssertEqual(date.timestamp.day, PhotoDay(year: 2025, month: 3, day: 4))
        XCTAssertTrue(date.source.isFallback)
    }

    func testJPEGWithoutEXIFUsesCreationDateAndPreservesOriginal() async throws {
        let root = try TestPhotoFixtures.directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let url = try TestPhotoFixtures.jpeg("capture.JPG", root: root)
        let beforeData = try Data(contentsOf: url)
        let before = try url.resourceValues(forKeys: [.creationDateKey, .contentModificationDateKey])
        let result = try await PhotoScanner().scan(root: root)
        let capture = try XCTUnwrap(result.captures.first)
        let date = try XCTUnwrap(capture.captureDate)
        XCTAssertEqual(date.source, .fileCreation)
        XCTAssertEqual(date.timestamp.day, PhotoDay(date: try XCTUnwrap(before.creationDate)))
        _ = await ThumbnailLoader().image(for: capture, root: root)
        XCTAssertEqual(try Data(contentsOf: url), beforeData)
        let after = try url.resourceValues(forKeys: [.creationDateKey, .contentModificationDateKey])
        XCTAssertEqual(after.creationDate, before.creationDate)
        XCTAssertEqual(after.contentModificationDate, before.contentModificationDate)
    }

    func testDatePriorityAppliesAcrossWholePairWithJPEGAsTiebreaker() async throws {
        let jpegDate = try XCTUnwrap(PhotoTimestamp.parseEXIF("2026:11:21 12:00:00"))
        let rawDate = try XCTUnwrap(PhotoTimestamp.parseEXIF("2026:11:20 12:00:00"))
        let fallbackJPEG = TestPhotoFixtures.file("pair.JPG", metadata: PhotoMetadata(fileCreation: jpegDate))
        let raw = TestPhotoFixtures.file("pair.RW2", metadata: PhotoMetadata(original: rawDate))
        let rawPreferred = try XCTUnwrap(PhotoGrouper.group([fallbackJPEG, raw]).first?.captureDate)
        XCTAssertEqual(rawPreferred.source, .original)
        XCTAssertEqual(rawPreferred.relativePath, "pair.RW2")

        let jpeg = TestPhotoFixtures.file("pair.JPG", metadata: PhotoMetadata(original: jpegDate))
        let jpegPreferred = try XCTUnwrap(PhotoGrouper.group([raw, jpeg]).first?.captureDate)
        XCTAssertEqual(jpegPreferred.relativePath, "pair.JPG")
        XCTAssertEqual(jpegPreferred.timestamp, jpegDate)
    }

    func testModificationFallbackAndUnknownDate() async throws {
        let timestamp = try XCTUnwrap(PhotoTimestamp.parseEXIF("2026:11:21 12:00:00"))
        let modified = TestPhotoFixtures.file("capture.JPG", metadata: PhotoMetadata(fileModification: timestamp))
        XCTAssertEqual(PhotoGrouper.group([modified]).first?.captureDate?.source, .fileModification)
        let unknown = TestPhotoFixtures.file("unknown.RW2")
        XCTAssertNil(PhotoGrouper.group([unknown]).first?.captureDate)
    }

    func testPreviewFallsBackToAnotherJPEGAndTriesRAWWithoutCrashing() async throws {
        let root = try TestPhotoFixtures.directory()
        defer { try? FileManager.default.removeItem(at: root) }
        try TestPhotoFixtures.write("pair.JPEG", root: root)
        try TestPhotoFixtures.jpeg("pair.JPG", root: root)
        try TestPhotoFixtures.write("pair.RW2", root: root)
        try TestPhotoFixtures.write("raw-only.RW2", root: root)
        let result = try await PhotoScanner().scan(root: root)
        let pair = try XCTUnwrap(result.captures.first { $0.name == "pair" })
        XCTAssertEqual(pair.previewFiles.map(\.relativePath), ["pair.JPEG", "pair.JPG", "pair.RW2"])
        let loader = ThumbnailLoader()
        let image = await loader.image(for: pair, root: root)
        XCTAssertNotNil(image)
        let raw = try XCTUnwrap(result.captures.first { $0.name == "raw-only" })
        let unavailable = await loader.image(for: raw, root: root)
        XCTAssertNil(unavailable) // Synthetic bytes do not validate real RW2 decoding.
    }
}
