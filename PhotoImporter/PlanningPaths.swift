import Foundation
import Darwin

/// Read-only inspection. Missing nodes and inaccessible nodes are deliberately distinct.
struct PlanningPaths {
    enum NodeKind { case directory, file, symlink, other }
    struct Node {
        let kind: NodeKind
        let size: Int64
        let snapshot: FileSnapshot
    }

    let caseSensitive: Bool
    private var listings: [URL: [String]] = [:]

    init(caseSensitive: Bool) { self.caseSensitive = caseSensitive }

    static func node(at url: URL) throws -> Node? {
        var info = stat()
        let result = url.withUnsafeFileSystemRepresentation { path in
            guard let path else { return Int32(-1) }
            return lstat(path, &info)
        }
        if result != 0 {
            let code = errno
            if code == ENOENT { return nil }
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(code), userInfo: [NSFilePathErrorKey: url.path])
        }
        let kind: NodeKind
        switch info.st_mode & S_IFMT {
        case S_IFDIR: kind = .directory
        case S_IFREG: kind = .file
        case S_IFLNK: kind = .symlink
        default: kind = .other
        }
        return Node(kind: kind, size: info.st_size, snapshot: FileSnapshot(info))
    }

    static func validateRoot(_ url: URL) throws {
        guard try node(at: url)?.kind == .directory else {
            throw PlanningError.message(L10n.text("Choose an existing folder that is not itself a symbolic link."))
        }
        _ = try FileManager.default.contentsOfDirectory(atPath: url.path)
    }

    static func rootsOverlap(_ source: URL, _ library: URL) -> Bool {
        // Resolve aliases in ancestors, including /var and /tmp, before comparing components.
        // Conservatively reject case-equivalent roots even if volume capabilities are unavailable.
        let a = source.resolvingSymlinksInPath().standardizedFileURL.pathComponents.map {
            ImportNaming.key($0, caseSensitive: false)
        }
        let b = library.resolvingSymlinksInPath().standardizedFileURL.pathComponents.map {
            ImportNaming.key($0, caseSensitive: false)
        }
        return a.starts(with: b) || b.starts(with: a)
    }

    static func validateSource(_ file: PhotoFile, root: URL) throws {
        let components = file.relativePath.components(separatedBy: "/")
        guard !file.relativePath.hasPrefix("/"), components.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }),
              root.appendingPathComponent(file.relativePath).standardizedFileURL == file.url.standardizedFileURL else {
            throw PlanningError.message(L10n.text("The file does not belong to the expected source path."))
        }
        var current = root
        for (index, component) in components.enumerated() {
            try Task.checkCancellation()
            current.appendPathComponent(component)
            guard let node = try node(at: current) else {
                throw PlanningError.message(L10n.text("Source file missing. Scan the source again."))
            }
            if index == components.count - 1 {
                guard node.kind == .file, node.size == file.byteCount,
                      FileManager.default.isReadableFile(atPath: current.path) else {
                    throw PlanningError.message(L10n.text("The source file changed, is inaccessible or was replaced by a link. Scan the source again."))
                }
            } else if node.kind != .directory {
                throw PlanningError.message(L10n.text("The source path contains a link or a component that is not a folder."))
            }
        }
    }

    mutating func inspectDestination(_ relativePath: String, root: URL) throws -> PlannedFileState {
        var directory = root
        let components = relativePath.components(separatedBy: "/")
        for (index, component) in components.enumerated() {
            try Task.checkCancellation()
            let names: [String]
            if let cached = listings[directory] {
                names = cached
            } else {
                names = try FileManager.default.contentsOfDirectory(atPath: directory.path)
                listings[directory] = names
            }
            let wanted = ImportNaming.key(component, caseSensitive: caseSensitive)
            let matches = names.filter { ImportNaming.key($0, caseSensitive: caseSensitive) == wanted }
            guard let name = matches.first else { return .newFile }
            guard matches.count == 1 else { return .blocked(L10n.text("Ambiguous equivalent names at the destination: %@.", String(describing: component))) }
            let url = directory.appendingPathComponent(name)
            guard let node = try Self.node(at: url) else {
                return .blocked(L10n.text("The destination changed during verification. Generate a new preview."))
            }
            if node.kind == .symlink { return .blocked(L10n.text("Symbolic link at the destination: %@.", String(describing: url.path))) }
            if index == components.count - 1 {
                return node.kind == .file ? .existing : .blocked(L10n.text("The final path is already a folder or another file type."))
            }
            guard node.kind == .directory else { return .blocked(L10n.text("A file occupies a destination folder path: %@.", String(describing: name))) }
            directory = url
        }
        return .blocked(L10n.text("Invalid destination path."))
    }
}
