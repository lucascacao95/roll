import Foundation
import ImageIO

// A serial actor bounds image decoding; the cache belongs to one discovery session.
actor ThumbnailLoader {
    private let cache = NSCache<NSURL, CGImage>()
    private var unavailable: Set<URL> = []

    init() {
        cache.countLimit = 200
        cache.totalCostLimit = 32 * 1_024 * 1_024
    }

    func image(for capture: PhotoCapture, root: URL) -> CGImage? {
        for file in capture.previewFiles {
            guard !Task.isCancelled else { return nil }
            if let image = image(for: file, root: root) { return image }
        }
        return nil
    }

    func image(for file: PhotoFile, root: URL) -> CGImage? {
        guard !Task.isCancelled, !unavailable.contains(file.url) else { return nil }
        if let image = cache.object(forKey: file.url as NSURL) { return image }

        let accessing = root.startAccessingSecurityScopedResource()
        defer { if accessing { root.stopAccessingSecurityScopedResource() } }
        guard let source = CGImageSourceCreateWithURL(
            file.url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary
        ), CGImageSourceGetCount(source) > 0, let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
            kCGImageSourceCreateThumbnailFromImageIfAbsent: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 400,
            kCGImageSourceShouldCacheImmediately: true
        ] as CFDictionary) else {
            if !Task.isCancelled { unavailable.insert(file.url) }
            return nil
        }
        guard !Task.isCancelled else { return nil }

        cache.setObject(image, forKey: file.url as NSURL, cost: image.bytesPerRow * image.height)
        return image
    }
}
