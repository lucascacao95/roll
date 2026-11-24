import Foundation

enum PhotoFormat: String, Sendable {
    case raw
    case jpeg

    init?(extension value: String) {
        switch value.lowercased() {
        case "rw2": self = .raw
        case "jpg", "jpeg": self = .jpeg
        default: return nil
        }
    }
}

struct PhotoFile: Identifiable, Hashable, Sendable {
    let url: URL
    let relativePath: String
    let format: PhotoFormat
    let byteCount: Int64
    var metadata = PhotoMetadata()

    var id: String { relativePath }
    var baseName: String { url.deletingPathExtension().lastPathComponent }
    var relativeDirectory: String {
        relativePath.split(separator: "/").dropLast().joined(separator: "/")
    }
}

struct PhotoCapture: Identifiable, Sendable {
    let id: String
    let files: [PhotoFile]
    var representativeDate: PhotoDate?

    var name: String { files[0].baseName }
    var directory: String { files[0].relativeDirectory }
    var jpeg: PhotoFile? { files.first { $0.format == .jpeg } }
    var previewFiles: [PhotoFile] {
        files.sorted {
            if $0.format != $1.format { return $0.format == .jpeg }
            return $0.relativePath < $1.relativePath
        }
    }
    var captureDate: PhotoDate? {
        if let representativeDate { return representativeDate }
        let preferred = previewFiles
        for source in PhotoDateSource.allCases {
            for file in preferred {
                if let timestamp = file.metadata.timestamp(for: source) {
                    return PhotoDate(timestamp: timestamp, source: source, relativePath: file.relativePath)
                }
            }
        }
        return nil
    }
    var formatLabel: String {
        let raw = files.contains { $0.format == .raw }
        let jpeg = files.contains { $0.format == .jpeg }
        return raw && jpeg ? "RAW + JPEG" : (raw ? "RAW" : "JPEG")
    }
}

enum PhotoGrouper {
    static func group(_ files: [PhotoFile]) -> [PhotoCapture] {
        // Keep the stem's case: distinct files on case-sensitive media must not merge.
        let groups = Dictionary(grouping: files) { file in
            file.relativeDirectory + "/" + file.baseName
        }
        return groups.keys.sorted().map { key in
            PhotoCapture(id: key, files: groups[key]!.sorted { $0.relativePath < $1.relativePath })
        }
    }
}
