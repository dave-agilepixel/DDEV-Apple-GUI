import Foundation

public protocol ProjectCacheStoring: Sendable {
    func loadProjects() throws -> [DDEVProject]
    func saveProjects(_ projects: [DDEVProject]) throws
}

public struct FileProjectCacheStore: ProjectCacheStoring {
    private let cacheDirectory: URL
    private let cacheFileName = "projects-cache.json"

    public init(cacheDirectory: URL? = nil) {
        self.cacheDirectory = cacheDirectory ?? FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0].appendingPathComponent("DDEVUI", isDirectory: true)
    }

    public func loadProjects() throws -> [DDEVProject] {
        let cacheFileURL = cacheDirectory.appendingPathComponent(cacheFileName, isDirectory: false)
        guard FileManager.default.fileExists(atPath: cacheFileURL.path) else {
            return []
        }

        let data = try Data(contentsOf: cacheFileURL)
        return try JSONDecoder().decode([DDEVProject].self, from: data)
    }

    public func saveProjects(_ projects: [DDEVProject]) throws {
        try FileManager.default.createDirectory(
            at: cacheDirectory,
            withIntermediateDirectories: true
        )

        // Cache file is machine-only; pretty-printing + sorted keys doubled file size and
        // slowed every refresh's encode.
        let data = try JSONEncoder().encode(projects)
        let cacheFileURL = cacheDirectory.appendingPathComponent(cacheFileName, isDirectory: false)
        try data.write(to: cacheFileURL, options: .atomic)
    }
}

public final class InMemoryProjectCacheStore: ProjectCacheStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var storedProjects: [DDEVProject]
    private var storedLoadError: Error?
    private var storedSaveError: Error?

    public var projects: [DDEVProject] {
        get {
            lock.withLock {
                storedProjects
            }
        }
        set {
            lock.withLock {
                storedProjects = newValue
            }
        }
    }

    public var loadError: Error? {
        get {
            lock.withLock {
                storedLoadError
            }
        }
        set {
            lock.withLock {
                storedLoadError = newValue
            }
        }
    }

    public var saveError: Error? {
        get {
            lock.withLock {
                storedSaveError
            }
        }
        set {
            lock.withLock {
                storedSaveError = newValue
            }
        }
    }

    public init(projects: [DDEVProject] = [], loadError: Error? = nil, saveError: Error? = nil) {
        self.storedProjects = projects
        self.storedLoadError = loadError
        self.storedSaveError = saveError
    }

    public func loadProjects() throws -> [DDEVProject] {
        try lock.withLock {
            if let storedLoadError {
                throw storedLoadError
            }

            return storedProjects
        }
    }

    public func saveProjects(_ projects: [DDEVProject]) throws {
        try lock.withLock {
            if let storedSaveError {
                throw storedSaveError
            }

            storedProjects = projects
        }
    }
}
