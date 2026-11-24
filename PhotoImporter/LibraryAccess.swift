import AppKit
import Observation

struct SavedLibrary: Codable, Sendable {
    let bookmark: Data
    let path: String // Display only; never used to restore access.
    let volumeID: String?
    let inode: UInt64
    let device: UInt64
    let createdSeconds: Int64?
    let createdNanos: Int64?

    static func capture(_ url: URL, bookmark: Data) throws -> Self {
        try PlanningPaths.validateRoot(url)
        guard let snapshot = try PlanningPaths.node(at: url)?.snapshot else {
            throw PlanningError.message(L10n.text("The archive folder is unavailable."))
        }
        return Self(bookmark: bookmark, path: url.path,
                    volumeID: try url.resourceValues(forKeys: [.volumeUUIDStringKey]).volumeUUIDString,
                    inode: snapshot.identity.inode, device: snapshot.identity.device,
                    createdSeconds: snapshot.createdSeconds, createdNanos: snapshot.createdNanos)
    }

    func validate(_ url: URL) throws {
        let current = try Self.capture(url, bookmark: bookmark)
        guard inode == current.inode,
              volumeID != nil ? volumeID == current.volumeID : device == current.device,
              createdSeconds == current.createdSeconds, createdNanos == current.createdNanos else {
            throw PlanningError.message(L10n.text("The archive identity changed. Choose the folder again."))
        }
    }
}

@MainActor @Observable
final class LibraryAccess {
    static let shared = LibraryAccess()
    private(set) var url: URL?
    private(set) var volume: LibraryVolumeInfo?
    private(set) var status = L10n.text("Choose your default archive.")
    private(set) var savedPath: String?
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var scopedURL: URL?
    @ObservationIgnored private var saved: SavedLibrary?
    @ObservationIgnored private var invalidRecord = false

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: "libraryBookmark") {
            saved = try? JSONDecoder().decode(SavedLibrary.self, from: data)
            invalidRecord = saved == nil
        }
        savedPath = saved?.path
        reconnect()
    }

    deinit { if let scopedURL { scopedURL.stopAccessingSecurityScopedResource() } }

    func choose(_ selected: URL) {
        let scoped = selected.startAccessingSecurityScopedResource()
        defer { if scoped { selected.stopAccessingSecurityScopedResource() } }
        do {
            let bookmark = try selected.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil)
            let record = try SavedLibrary.capture(selected, bookmark: bookmark)
            let data = try JSONEncoder().encode(record)
            defaults.set(data, forKey: "libraryBookmark")
            saved = record
            invalidRecord = false
            savedPath = record.path
            reconnect()
        } catch { status = L10n.text("Could not save the archive: %@", String(describing: error.localizedDescription)) }
    }

    func reconnect() {
        // Release the previous lease before resolving a fresh one. No path/name fallback or mounting.
        if let scopedURL { scopedURL.stopAccessingSecurityScopedResource() }
        scopedURL = nil
        url = nil
        volume = nil
        guard let saved else {
            status = invalidRecord ? L10n.text("Invalid archive preference. Choose the folder again.") : L10n.text("Choose your default archive.")
            return
        }
        do {
            var stale = false
            let resolved = try URL(resolvingBookmarkData: saved.bookmark,
                                   options: [.withSecurityScope, .withoutUI, .withoutMounting],
                                   relativeTo: nil, bookmarkDataIsStale: &stale)
            let scoped = resolved.startAccessingSecurityScopedResource()
            do {
                try saved.validate(resolved)
                guard FileManager.default.isReadableFile(atPath: resolved.path), FileManager.default.isWritableFile(atPath: resolved.path) else {
                    throw PlanningError.message(L10n.text("No read/write permission or a read-only volume. Choose the folder again."))
                }
                if stale {
                    let data = try resolved.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil)
                    let renewed = try SavedLibrary.capture(resolved, bookmark: data)
                    defaults.set(try JSONEncoder().encode(renewed), forKey: "libraryBookmark")
                    self.saved = renewed
                }
                if scoped { scopedURL = resolved }
                volume = try? LibraryVolumeInfo.read(at: resolved)
                url = resolved
                savedPath = resolved.path
                status = L10n.text("Archive connected · read/write access available; space will be checked in the preview.")
            } catch {
                if scoped { resolved.stopAccessingSecurityScopedResource() }
                throw error
            }
        } catch {
            status = L10n.text("Archive disconnected or inaccessible: %@", String(describing: error.localizedDescription))
        }
    }

    func forget() {
        if let scopedURL { scopedURL.stopAccessingSecurityScopedResource() }
        scopedURL = nil; saved = nil; url = nil; volume = nil; savedPath = nil; invalidRecord = false
        defaults.removeObject(forKey: "libraryBookmark")
        status = L10n.text("Choose your default archive.")
    }
}

@MainActor @Observable
final class VolumeMonitor: NSObject {
    private(set) var volumes: [URL] = []
    @ObservationIgnored var onChange: (() -> Void)?

    override init() {
        super.init()
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didMountNotification, NSWorkspace.didUnmountNotification, NSWorkspace.didRenameVolumeNotification] {
            center.addObserver(self, selector: #selector(changed), name: name, object: nil)
        }
        refresh()
    }

    deinit { NSWorkspace.shared.notificationCenter.removeObserver(self) }

    @objc private func changed(_ notification: Notification) {
        refresh()
        onChange?()
    }

    func refresh() {
        volumes = (FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: [.volumeIsInternalKey, .volumeIsRemovableKey, .volumeIsEjectableKey], options: [.skipHiddenVolumes]) ?? [])
            .filter { url in
                guard let values = try? url.resourceValues(forKeys: [.volumeIsInternalKey, .volumeIsRemovableKey, .volumeIsEjectableKey]) else { return false }
                return values.volumeIsInternal == false || values.volumeIsRemovable == true || values.volumeIsEjectable == true
            }.sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
    }
}
