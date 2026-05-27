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

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        let data = try encoder.encode(projects)
        let cacheFileURL = cacheDirectory.appendingPathComponent(cacheFileName, isDirectory: false)
        try data.write(to: cacheFileURL, options: .atomic)
    }
}

public final class InMemoryProjectCacheStore: ProjectCacheStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var storedProjects: [DDEVProject]

    public var loadError: Error?
    public var saveError: Error?

    public init(projects: [DDEVProject] = [], loadError: Error? = nil, saveError: Error? = nil) {
        self.storedProjects = projects
        self.loadError = loadError
        self.saveError = saveError
    }

    public func loadProjects() throws -> [DDEVProject] {
        try lock.withLock {
            if let loadError {
                throw loadError
            }

            return storedProjects
        }
    }

    public func saveProjects(_ projects: [DDEVProject]) throws {
        try lock.withLock {
            if let saveError {
                throw saveError
            }

            storedProjects = projects
        }
    }
}
