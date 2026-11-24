// Regression for Foundation enumerating /private/tmp while the source standardizes to /tmp.
// Runs separately because the sandboxed XCTest host cannot create arbitrary /private/tmp fixtures.
import Foundation

@main struct DiscoveryAliasRegression {
    static func main() async throws {
        let root = URL(fileURLWithPath: "/private/tmp").appendingPathComponent("RollDiscovery-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("DCIM"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let expected = Data("disposable discovery fixture".utf8)
        let file = root.appendingPathComponent("DCIM/capture.JPG")
        try expected.write(to: file)
        let result = try await PhotoScanner().scan(root: root)
        guard result.fileCount == 1, result.issues.isEmpty,
              result.captures.first?.files.first?.relativePath == "DCIM/capture.JPG",
              result.captures.first?.files.first?.url == file.standardizedFileURL,
              try Data(contentsOf: file) == expected else { throw CocoaError(.fileReadCorruptFile) }
        print("PASS: /private/tmp discovery preserves relative paths and source bytes")
    }
}
