import XCTest
import ImageIO
import UniformTypeIdentifiers
@testable import PhotoImporter

enum TestPhotoFixtures {
    @MainActor
    static func model(importer: ImportService = .shared) -> DiscoveryModel {
        // No test reads the user's saved library or preferences.
        let defaults = UserDefaults(suiteName: "PhotoImporterFixture.\(UUID())")!
        return DiscoveryModel(importer: importer, preferences: AppPreferences(defaults: defaults),
                              libraryAccess: LibraryAccess(defaults: defaults))
    }

    static func directory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @discardableResult
    static func write(_ name: String, root: URL) throws -> URL {
        let url = root.appendingPathComponent(name)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("fixture:\(name)".utf8).write(to: url)
        return url
    }

    @discardableResult
    static func jpeg(_ name: String, root: URL, original: String? = nil,
                     digitized: String? = nil, offset: String? = nil) throws -> URL {
        let url = root.appendingPathComponent(name)
        let context = try XCTUnwrap(CGContext(data: nil, width: 40, height: 20, bitsPerComponent: 8,
                                              bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                              bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
        context.setFillColor(CGColor(red: 0, green: 0.5, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 40, height: 20))
        let image = try XCTUnwrap(context.makeImage())
        let destination = try XCTUnwrap(CGImageDestinationCreateWithURL(url as CFURL, UTType.jpeg.identifier as CFString, 1, nil))
        var exif: [String: Any] = [:]
        exif[kCGImagePropertyExifDateTimeOriginal as String] = original
        exif[kCGImagePropertyExifDateTimeDigitized as String] = digitized
        exif[kCGImagePropertyExifOffsetTimeOriginal as String] = offset
        CGImageDestinationAddImage(destination, image, [kCGImagePropertyExifDictionary: exif] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw CocoaError(.fileWriteUnknown) }
        return url
    }

    static func file(_ name: String, metadata: PhotoMetadata = PhotoMetadata(), byteCount: Int64 = 10) -> PhotoFile {
        PhotoFile(url: URL(fileURLWithPath: "/fixture/" + name), relativePath: name,
                  format: PhotoFormat(extension: (name as NSString).pathExtension)!,
                  byteCount: byteCount, metadata: metadata)
    }

    @MainActor
    static func waitForDiscovery(_ model: DiscoveryModel) async throws {
        for _ in 0..<500 {
            if !model.isScanning { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertFalse(model.isScanning, "Discovery did not finish within five seconds")
        XCTAssertNil(model.errorMessage)
        _ = try XCTUnwrap(model.result)
    }
}
