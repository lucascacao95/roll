import Foundation

enum PhotoFormatFilter: String, CaseIterable, Sendable {
    case all = "Todos (RAW e JPEG)"
    case raw = "RAW"
    case jpeg = "JPEG"

    var label: String { L10n.legacyLabel(rawValue) }

    func includes(_ file: PhotoFile) -> Bool {
        switch self {
        case .all: true
        case .raw: file.format == .raw
        case .jpeg: file.format == .jpeg
        }
    }
}

struct PhotoFilters: Equatable, Sendable {
    var format: PhotoFormatFilter = .all
    var startDay: PhotoDay?
    var endDay: PhotoDay?
    var onlyNotImported = false

    var hasDateRange: Bool { startDay != nil || endDay != nil }
    var isValid: Bool {
        guard let startDay, let endDay else { return true }
        return startDay <= endDay
    }

    func matches(_ capture: PhotoCapture) -> Bool {
        guard isValid, capture.files.contains(where: format.includes) else { return false }
        guard hasDateRange else { return true }
        guard let day = capture.captureDate?.timestamp.day else { return false }
        if let startDay, day < startDay { return false }
        if let endDay, day > endDay { return false }
        return true
    }
}

struct PhotoSummary {
    let captureCount: Int
    let fileCount: Int
    let byteCount: Int64

    init(captures: [PhotoCapture], format: PhotoFormatFilter) {
        let eligible = captures.map { $0.files.filter(format.includes) }.filter { !$0.isEmpty }
        captureCount = eligible.count
        fileCount = eligible.reduce(0) { $0 + $1.count }
        byteCount = eligible.reduce(0) { sum, files in sum + files.reduce(0) { $0 + $1.byteCount } }
    }
}
