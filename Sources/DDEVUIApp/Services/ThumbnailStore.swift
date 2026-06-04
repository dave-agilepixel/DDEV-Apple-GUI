import Foundation

public protocol ThumbnailStoring: Sendable {
    /// All cached thumbnails, keyed by project id. Read once on launch. Missing dir → empty.
    func loadAll() async -> [String: Data]
    /// Persist (overwrite) one project's PNG.
    func save(_ data: Data, projectID: String) async throws
    /// Delete cached files for projects no longer present.
    func prune(keeping liveIDs: Set<String>) async
}

/// Disk-backed PNG cache, one `<id>.png` per project. Non-actor-isolated value type with `async`
/// members, so encode + disk I/O run off the `@MainActor` caller (mirrors `FileProjectCacheStore`).
public struct FileThumbnailStore: ThumbnailStoring {
    private let directory: URL

    public init(directory: URL? = nil) {
        self.directory = directory ?? FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        )[0]
            .appendingPathComponent("DDEVUI", isDirectory: true)
            .appendingPathComponent("thumbnails", isDirectory: true)
    }

    /// Project ids are ddev project names; replace path separators so an id can't escape `directory`.
    private func fileURL(for projectID: String) -> URL {
        let safe = projectID.replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: ":", with: "_")
        return directory.appendingPathComponent("\(safe).png", isDirectory: false)
    }

    public func loadAll() async -> [String: Data] {
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil
        ) else { return [:] }

        var result: [String: Data] = [:]
        for url in entries where url.pathExtension == "png" {
            if let data = try? Data(contentsOf: url) {
                result[url.deletingPathExtension().lastPathComponent] = data
            }
        }
        return result
    }

    public func save(_ data: Data, projectID: String) async throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = fileURL(for: projectID)
        try data.write(to: url, options: .atomic)
        // Owner-only: machine-only cache, not world-readable (mirrors the project cache, audit S1).
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    public func prune(keeping liveIDs: Set<String>) async {
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil
        ) else { return }
        for url in entries where url.pathExtension == "png" {
            let id = url.deletingPathExtension().lastPathComponent
            if !liveIDs.contains(id) {
                try? FileManager.default.removeItem(at: url)
            }
        }
    }
}

public final class InMemoryThumbnailStore: ThumbnailStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [String: Data]

    public init(thumbnails: [String: Data] = [:]) { self.storage = thumbnails }

    public func loadAll() async -> [String: Data] { lock.withLock { storage } }

    public func save(_ data: Data, projectID: String) async throws {
        lock.withLock { storage[projectID] = data }
    }

    public func prune(keeping liveIDs: Set<String>) async {
        lock.withLock { storage = storage.filter { liveIDs.contains($0.key) } }
    }
}
