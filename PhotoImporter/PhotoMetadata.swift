import Foundation
import ImageIO

/// A camera's civil day, independent of the Mac's time zone or DST transitions.
struct PhotoDay: Hashable, Comparable, Sendable {
    let year: Int
    let month: Int
    let day: Int

    init?(year: Int, month: Int, day: Int) {
        guard (1...9999).contains(year), (1...12).contains(month), (1...31).contains(day) else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let components = DateComponents(year: year, month: month, day: day)
        guard let date = calendar.date(from: components),
              calendar.dateComponents([.year, .month, .day], from: date) == components else { return nil }
        self.year = year
        self.month = month
        self.day = day
    }

    init(date: Date, timeZone: TimeZone = .current) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        year = components.year!
        month = components.month!
        day = components.day!
    }

    static func < (lhs: Self, rhs: Self) -> Bool {
        (lhs.year, lhs.month, lhs.day) < (rhs.year, rhs.month, rhs.day)
    }

    var displayText: String { String(format: "%02d/%02d/%04d", day, month, year) }

    // Noon is only a bridge to DatePicker. Filtering compares civil days directly.
    var pickerDate: Date {
        Calendar(identifier: .gregorian).date(from: DateComponents(year: year, month: month, day: day, hour: 12))!
    }
}

struct PhotoTimestamp: Hashable, Sendable {
    let day: PhotoDay
    let hour: Int
    let minute: Int
    let second: Int

    static func parseEXIF(_ text: String?) -> Self? {
        guard let text else { return nil }
        let bytes = Array(text.utf8)
        guard bytes.count == 19, bytes[4] == 58, bytes[7] == 58, bytes[10] == 32,
              bytes[13] == 58, bytes[16] == 58 else { return nil }
        func number(_ range: Range<Int>) -> Int? {
            let digits = bytes[range]
            guard digits.allSatisfy({ (48...57).contains($0) }) else { return nil }
            return digits.reduce(0) { $0 * 10 + Int($1 - 48) }
        }
        guard let year = number(0..<4), let month = number(5..<7), let day = number(8..<10),
              let hour = number(11..<13), let minute = number(14..<16), let second = number(17..<19),
              let civilDay = PhotoDay(year: year, month: month, day: day),
              hour < 24, minute < 60, second < 60 else { return nil }
        return Self(day: civilDay, hour: hour, minute: minute, second: second)
    }

    static func fromFileDate(_ date: Date?) -> Self? {
        guard let date else { return nil }
        let components = Calendar(identifier: .gregorian).dateComponents([.hour, .minute, .second], from: date)
        return Self(day: PhotoDay(date: date), hour: components.hour!, minute: components.minute!, second: components.second!)
    }

    var displayText: String {
        day.displayText + String(format: " %02d:%02d:%02d", hour, minute, second)
    }
}

enum PhotoDateSource: CaseIterable, Sendable {
    // Declaration order is the priority, across all physical files in a capture.
    case original, digitized, fileCreation, fileModification

    var label: String {
        switch self {
        case .original: L10n.text("Capture (EXIF)")
        case .digitized: L10n.text("Digitized (EXIF) · fallback")
        case .fileCreation: L10n.text("File creation · fallback")
        case .fileModification: L10n.text("File modification · fallback")
        }
    }

    var isFallback: Bool { self != .original }
}

struct PhotoDate: Sendable {
    let timestamp: PhotoTimestamp
    let source: PhotoDateSource
    let relativePath: String
}

struct PhotoMetadata: Hashable, Sendable {
    var original: PhotoTimestamp?
    var digitized: PhotoTimestamp?
    var fileCreation: PhotoTimestamp?
    var fileModification: PhotoTimestamp?

    func timestamp(for source: PhotoDateSource) -> PhotoTimestamp? {
        switch source {
        case .original: original
        case .digitized: digitized
        case .fileCreation: fileCreation
        case .fileModification: fileModification
        }
    }
}

enum PhotoMetadataReader {
    // Called by PhotoScanner's actor while its read-only security scope is active.
    static func read(url: URL, values: URLResourceValues) -> PhotoMetadata {
        var metadata = PhotoMetadata(
            fileCreation: PhotoTimestamp.fromFileDate(values.creationDate),
            fileModification: PhotoTimestamp.fromFileDate(values.contentModificationDate)
        )
        guard let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
              CGImageSourceGetCount(source) > 0,
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any],
              let exif = properties[kCGImagePropertyExifDictionary as String] as? [String: Any] else { return metadata }

        // Read EXIF civil time directly: an offset must not shift the camera's day.
        metadata.original = PhotoTimestamp.parseEXIF(exif[kCGImagePropertyExifDateTimeOriginal as String] as? String)
        metadata.digitized = PhotoTimestamp.parseEXIF(exif[kCGImagePropertyExifDateTimeDigitized as String] as? String)
        return metadata
    }
}
