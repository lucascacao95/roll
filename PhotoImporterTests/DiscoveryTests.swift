import XCTest
import ImageIO
import UniformTypeIdentifiers
@testable import PhotoImporter

@MainActor
final class DiscoveryTests: XCTestCase {
    func testRecursiveDiscoveryAndGrouping() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        for name in ["DCIM/100_PANA/P100001.RW2", "DCIM/100_PANA/P100001.JPG",
                     "DCIM/101_PANA/P100001.rw2", "outside.JpEg", "notes.txt", "video.MP4"] {
            try fixture(name, in: root)
        }
        let result = try await PhotoScanner().scan(root: root)
        XCTAssertEqual(result.captures.count, 3)
        XCTAssertEqual(result.fileCount, 4)
        XCTAssertTrue(result.issues.isEmpty)
        XCTAssertEqual(result.captures.first { $0.directory == "DCIM/100_PANA" }?.formatLabel, "RAW + JPEG")
        XCTAssertEqual(result.captures.first { $0.directory == "DCIM/101_PANA" }?.formatLabel, "RAW")
        XCTAssertEqual(result.captures.first { $0.directory.isEmpty }?.formatLabel, "JPEG")
    }

    func testBothJPEGExtensionsArePreserved() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        for name in ["capture.JPG", "capture.JPEG", "capture.RW2"] {
            try fixture(name, in: root)
        }
        let result = try await PhotoScanner().scan(root: root)
        XCTAssertEqual(result.captures.count, 1)
        XCTAssertEqual(result.fileCount, 3)
        XCTAssertEqual(result.captures[0].files.map(\.relativePath), ["capture.JPEG", "capture.JPG", "capture.RW2"])
    }

    func testGroupingPreservesCaseSensitiveStems() async {
        let files = ["photo.JPG", "PHOTO.RW2"].map { name in
            PhotoFile(url: URL(fileURLWithPath: "/fixture/" + name), relativePath: name,
                      format: PhotoFormat(extension: (name as NSString).pathExtension)!, byteCount: 1)
        }
        XCTAssertEqual(PhotoGrouper.group(files).count, 2)
    }

    func testHiddenFilesAndSymbolicLinksAreSkipped() async throws {
        let root = try temporaryDirectory()
        let outside = try temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: outside)
        }
        try fixture("visible.JPG", in: root)
        try fixture(".hidden.JPG", in: root)
        try fixture("._visible.JPG", in: root)
        try fixture(".hidden/secret.RW2", in: root)
        try fixture("external.JPG", in: outside)
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("linked.JPG"),
                                                   withDestinationURL: outside.appendingPathComponent("external.JPG"))
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("linked-folder"),
                                                   withDestinationURL: outside)
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("broken.RW2"),
                                                   withDestinationURL: outside.appendingPathComponent("missing"))
        let result = try await PhotoScanner().scan(root: root)
        XCTAssertEqual(result.fileCount, 1)
        XCTAssertEqual(result.captures[0].name, "visible")
        XCTAssertTrue(result.issues.isEmpty)
    }

    func testHundredsOfPairsAreDeterministicAndLeaveSourceUntouched() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        for index in 0..<360 {
            for ext in ["JPG", "RW2"] {
                try fixture("DCIM/100_PANA/P\(index).\(ext)", in: root)
            }
        }
        let before = try snapshot(root)
        let scanner = PhotoScanner()
        let first = try await scanner.scan(root: root)
        let second = try await scanner.scan(root: root)
        XCTAssertEqual(first.captures.count, 360)
        XCTAssertEqual(first.fileCount, 720)
        XCTAssertEqual(first.byteCount, Int64(before.values.reduce(0) { $0 + $1.data.count }))
        XCTAssertEqual(first.captures.map(\.id), second.captures.map(\.id))
        XCTAssertEqual(try snapshot(root), before)
    }

    func testMissingAndNonDirectorySourcesFail() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try fixture("file.JPG", in: root)
        for url in [root.appendingPathComponent("missing"), root.appendingPathComponent("file.JPG")] {
            do {
                _ = try await PhotoScanner().scan(root: url)
                XCTFail("Invalid source should fail")
            } catch {
                XCTAssertFalse(error is CancellationError)
            }
        }
    }

    func testEmptyDirectory() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let result = try await PhotoScanner().scan(root: root)
        XCTAssertTrue(result.captures.isEmpty)
        XCTAssertTrue(result.issues.isEmpty)
    }

    func testUnreadableSubdirectoryProducesPartialResult() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try fixture("visible.JPG", in: root)
        try fixture("unreadable/hidden.JPG", in: root)
        let unreadable = root.appendingPathComponent("unreadable")
        try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: unreadable.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: unreadable.path) }
        let result = try await PhotoScanner().scan(root: root)
        XCTAssertEqual(result.fileCount, 1)
        XCTAssertTrue(result.issues.contains { $0.path.hasSuffix("/unreadable") })
    }

    func testChangingSourceDoesNotPublishPreviousScan() async throws {
        let first = try temporaryDirectory()
        let second = try temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: first)
            try? FileManager.default.removeItem(at: second)
        }
        try fixture("first.JPG", in: first)
        try fixture("second.RW2", in: second)
        let model = TestPhotoFixtures.model()
        model.discover(first)
        model.discover(second)
        for _ in 0..<300 {
            if !model.isScanning { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertFalse(model.isScanning)
        XCTAssertNil(model.errorMessage)
        XCTAssertEqual(model.root, second)
        XCTAssertEqual(model.result?.captures.map(\.name), ["second"])
    }

    func testCancellationIsPropagated() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let scanner = PhotoScanner()
        // The task cannot enter its MainActor closure before cancellation below.
        let task = Task { try await scanner.scan(root: root) }
        task.cancel()
        do {
            _ = try await task.value
            XCTFail("Cancelled discovery should not return a complete result")
        } catch {
            XCTAssertTrue(error is CancellationError)
        }
    }

    func testJPEGThumbnailUsesOrientationAndDoesNotChangeOriginal() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("capture.JPG")
        let context = try XCTUnwrap(CGContext(data: nil, width: 800, height: 400, bitsPerComponent: 8,
                                              bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                              bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
        context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 800, height: 400))
        let image = try XCTUnwrap(context.makeImage())
        let destination = try XCTUnwrap(CGImageDestinationCreateWithURL(url as CFURL, UTType.jpeg.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, [kCGImagePropertyOrientation: 6] as CFDictionary)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        let before = try snapshot(root)
        let result = try await PhotoScanner().scan(root: root)
        let file = try XCTUnwrap(result.captures.first?.jpeg)
        let loader = ThumbnailLoader()
        let thumbnail = await loader.image(for: file, root: root)
        let decoded = try XCTUnwrap(thumbnail)
        XCTAssertGreaterThan(decoded.height, decoded.width)
        XCTAssertLessThanOrEqual(max(decoded.width, decoded.height), 400)
        let cached = await loader.image(for: file, root: root)
        XCTAssertNotNil(cached)
        XCTAssertEqual(try snapshot(root), before)
    }

    func testInvalidJPEGAndSyntheticRAWHaveNoThumbnail() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try fixture("broken.JPG", in: root)
        try fixture("synthetic.RW2", in: root)
        let result = try await PhotoScanner().scan(root: root)
        let loader = ThumbnailLoader()
        XCTAssertEqual(result.fileCount, 2)
        for capture in result.captures {
            let image = await loader.image(for: capture.files[0], root: root)
            XCTAssertNil(image)
        }
    }

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func fixture(_ path: String, in root: URL) throws {
        let url = root.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("fixture:\(path)".utf8).write(to: url)
    }

    private struct Snapshot: Equatable {
        let data: Data
        let created: Date?
        let modified: Date?
    }

    private func snapshot(_ root: URL) throws -> [String: Snapshot] {
        let enumerator = try XCTUnwrap(FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil))
        var result: [String: Snapshot] = [:]
        for case let url as URL in enumerator {
            let values = try url.resourceValues(forKeys: [.isRegularFileKey, .creationDateKey, .contentModificationDateKey])
            guard values.isRegularFile == true else { continue }
            result[url.path] = Snapshot(data: try Data(contentsOf: url), created: values.creationDate,
                                        modified: values.contentModificationDate)
        }
        return result
    }
}
