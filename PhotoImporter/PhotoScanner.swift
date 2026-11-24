import Foundation

struct ScanIssue: Identifiable, Sendable {
    let path: String
    let message: String
    var id: String { path + ":" + message }
}

struct ScanResult: Sendable {
    let captures: [PhotoCapture]
    let issues: [ScanIssue]
    var fileCount: Int { captures.reduce(0) { $0 + $1.files.count } }
    var byteCount: Int64 { captures.flatMap(\.files).reduce(0) { $0 + $1.byteCount } }
}

enum ScanError: LocalizedError {
    case notDirectory
    case cannotEnumerate

    var errorDescription: String? {
        switch self {
        case .notDirectory: L10n.text("The selected source is not a folder.")
        case .cannotEnumerate: L10n.text("Could not list the source. Check the connection and read permission.")
        }
    }
}

actor PhotoScanner {
    func scan(root: URL) throws -> ScanResult {
        try Task.checkCancellation()
        let accessing = root.startAccessingSecurityScopedResource()
        defer { if accessing { root.stopAccessingSecurityScopedResource() } }

        let directory = root.standardizedFileURL
        let rootValues = try directory.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        guard rootValues.isDirectory == true, rootValues.isSymbolicLink != true else {
            throw ScanError.notDirectory
        }

        let keys: [URLResourceKey] = [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey,
                                      .creationDateKey, .contentModificationDateKey]
        var issues: [ScanIssue] = []
        let prefix = directory.path.hasSuffix("/") ? directory.path : directory.path + "/"
        guard let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles, .skipsPackageDescendants],
            errorHandler: { url, error in
                issues.append(ScanIssue(path: url.path, message: error.localizedDescription))
                return true
            }
        ) else { throw ScanError.cannotEnumerate }

        var files: [PhotoFile] = []
        for case let enumeratedURL as URL in enumerator {
            // Foundation enumeration can return /private/tmp for a standardized /tmp root.
            let url = enumeratedURL.standardizedFileURL
            try Task.checkCancellation()
            do {
                let values = try url.resourceValues(forKeys: Set(keys))
                guard values.isSymbolicLink != true else {
                    enumerator.skipDescendants()
                    continue
                }
                guard values.isRegularFile == true,
                      let format = PhotoFormat(extension: url.pathExtension) else { continue }
                guard url.path.hasPrefix(prefix) else { continue }
                files.append(PhotoFile(
                    url: url,
                    relativePath: String(url.path.dropFirst(prefix.count)),
                    format: format,
                    byteCount: Int64(values.fileSize ?? 0),
                    metadata: PhotoMetadataReader.read(url: url, values: values)
                ))
            } catch {
                issues.append(ScanIssue(path: url.path, message: error.localizedDescription))
            }
        }
        try Task.checkCancellation()
        return ScanResult(captures: PhotoGrouper.group(files), issues: issues)
    }
}
