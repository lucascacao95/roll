import Foundation
import CryptoKit
import Darwin

/// Owned descriptor. All source opens are read-only; directory traversal never follows symlinks.
final class ImportDescriptor {
    let raw: Int32
    init(_ raw: Int32) throws {
        guard raw >= 0 else { throw SafeImportFiles.posixError() }
        self.raw = raw
    }
    deinit { Darwin.close(raw) }
}

enum SafeImportFiles {
    static func posixError() -> NSError { NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }

    static func root(_ url: URL) throws -> ImportDescriptor {
        try ImportDescriptor(Darwin.open(url.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC))
    }

    static func snapshot(_ file: ImportDescriptor, directory: Bool = false) throws -> FileSnapshot {
        var info = stat()
        guard fstat(file.raw, &info) == 0 else { throw posixError() }
        guard info.st_mode & S_IFMT == (directory ? S_IFDIR : S_IFREG) else {
            throw PlanningError.message(L10n.text("The path is not of the expected type."))
        }
        return FileSnapshot(info)
    }

    static func node(_ name: String, in directory: ImportDescriptor) throws -> FileSnapshot? {
        var info = stat()
        guard fstatat(directory.raw, name, &info, AT_SYMLINK_NOFOLLOW) == 0 else {
            if errno == ENOENT { return nil }
            throw posixError()
        }
        guard info.st_mode & S_IFMT == S_IFREG else {
            throw PlanningError.message(L10n.text("The destination contains a link, folder or another file type."))
        }
        return FileSnapshot(info)
    }

    static func components(_ relative: String) throws -> [String] {
        let parts = relative.components(separatedBy: "/")
        guard !relative.hasPrefix("/"), parts.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." && !$0.contains("\0") }) else {
            throw PlanningError.message(L10n.text("Invalid relative path."))
        }
        return parts
    }

    static func matchingName(_ wanted: String, in directory: ImportDescriptor, caseSensitive: Bool) throws -> String? {
        let duplicate = dup(directory.raw)
        guard duplicate >= 0 else { throw posixError() }
        guard let stream = fdopendir(duplicate) else {
            let error = posixError()
            Darwin.close(duplicate)
            throw error
        }
        defer { closedir(stream) }
        // dup shares the directory offset, so rewind before every fresh lookup.
        rewinddir(stream)
        let key = ImportNaming.key(wanted, caseSensitive: caseSensitive)
        var matches: [String] = []
        while true {
            errno = 0
            guard let entry = readdir(stream) else {
                if errno != 0 { throw posixError() }
                break
            }
            let name = withUnsafeBytes(of: entry.pointee.d_name) {
                String(cString: $0.baseAddress!.assumingMemoryBound(to: CChar.self))
            }
            if ImportNaming.key(name, caseSensitive: caseSensitive) == key { matches.append(name) }
        }
        guard matches.count <= 1 else { throw PlanningError.message(L10n.text("Ambiguous equivalent names at the destination.")) }
        return matches.first
    }

    static func directory(_ parts: [String], in root: ImportDescriptor, create: Bool, caseSensitive: Bool) throws -> ImportDescriptor {
        var current = try ImportDescriptor(dup(root.raw))
        for component in parts {
            try Task.checkCancellation()
            let existing = try matchingName(component, in: current, caseSensitive: caseSensitive)
            if existing == nil, create {
                guard mkdirat(current.raw, component, 0o755) == 0 || errno == EEXIST else { throw posixError() }
            }
            current = try ImportDescriptor(openat(current.raw, existing ?? component, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC))
        }
        return current
    }

    static func readFile(_ name: String, in directory: ImportDescriptor) throws -> ImportDescriptor {
        let file = try ImportDescriptor(openat(directory.raw, name, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC))
        _ = try snapshot(file)
        return file
    }

    static func synchronize(_ file: ImportDescriptor) throws {
        while fsync(file.raw) != 0 {
            if errno == EINTR { continue }
            throw posixError()
        }
    }

    static func hash(relative: String, in root: ImportDescriptor, caseSensitive: Bool) throws -> HashedImportFile? {
        let parts = try components(relative)
        do {
            let parents = Array(parts.dropLast())
            let parent = try directory(parents, in: root, create: false, caseSensitive: caseSensitive)
            let parentIdentity = try snapshot(parent, directory: true).identity
            guard let name = try matchingName(parts.last!, in: parent, caseSensitive: caseSensitive) else { return nil }
            let file = try readFile(name, in: parent)
            let before = try snapshot(file)
            let sha = try digest(file, expectedSize: before.size) { _ in }
            let currentParent = try directory(parents, in: root, create: false, caseSensitive: caseSensitive)
            guard try snapshot(currentParent, directory: true).identity == parentIdentity,
                  try snapshot(file) == before, try node(name, in: parent) == before else {
                throw PlanningError.message(L10n.text("The file changed during verification."))
            }
            return HashedImportFile(snapshot: before, sha256: sha)
        } catch let error as NSError where error.domain == NSPOSIXErrorDomain && error.code == Int(ENOENT) {
            return nil
        }
    }

    /// Bounded 1 MiB buffer; handles short writes, interruptions, cancellation and read errors.
    static func digest(_ input: ImportDescriptor, copyingTo output: ImportDescriptor? = nil,
                       expectedSize: Int64, progress: (Int64) throws -> Void) throws -> String {
        guard lseek(input.raw, 0, SEEK_SET) >= 0 else { throw posixError() }
        var hasher = SHA256()
        var buffer = [UInt8](repeating: 0, count: 1_024 * 1_024)
        var total: Int64 = 0
        while true {
            try Task.checkCancellation()
            let count = buffer.withUnsafeMutableBytes { Darwin.read(input.raw, $0.baseAddress, $0.count) }
            if count < 0 {
                if errno == EINTR { continue }
                throw posixError()
            }
            if count == 0 { break }
            total += Int64(count)
            guard total <= expectedSize else { throw PlanningError.message(L10n.text("The source size changed while reading.")) }
            try buffer.withUnsafeBytes { bytes in
                let chunk = UnsafeRawBufferPointer(rebasing: bytes[..<count])
                hasher.update(bufferPointer: chunk)
                if let output {
                    var written = 0
                    while written < count {
                        try Task.checkCancellation()
                        let size = Darwin.write(output.raw, chunk.baseAddress!.advanced(by: written), count - written)
                        if size < 0 {
                            if errno == EINTR { continue }
                            throw posixError()
                        }
                        guard size > 0 else { throw PlanningError.message(L10n.text("Writing to the destination made no progress.")) }
                        written += size
                    }
                }
            }
            try progress(total)
        }
        guard total == expectedSize else { throw PlanningError.message(L10n.text("Incomplete read: the size differs from the expected size.")) }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
