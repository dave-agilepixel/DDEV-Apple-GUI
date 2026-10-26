import Foundation

/// One line of DDEV's project registry (`~/.ddev/project_list.yaml`), plus whether the folder it
/// points at is currently on disk.
public struct DDEVProjectRegistryEntry: Equatable, Sendable {
    public let name: String
    public let appRoot: String
    /// `false` when the folder is absent — typically because it lives on a drive that is not
    /// mounted, which to DDEV looks identical to a deleted project.
    public let folderExists: Bool

    public init(name: String, appRoot: String, folderExists: Bool) {
        self.name = name
        self.appRoot = appRoot
        self.folderExists = folderExists
    }
}

/// Read-only access to DDEV's own project registry.
///
/// Why this exists: `ddev list` (DDEV v1.25.4, `GetProjects` in `pkg/ddevapp/utils.go`)
/// permanently removes any registry entry whose approot does not exist at the moment it runs,
/// warning "no longer exists in the filesystem, removing it from registry". An unmounted external
/// drive therefore makes a single status poll silently unregister every project kept on it. The
/// app reads the registry itself before polling so it can hold off while any folder is missing.
public protocol DDEVProjectRegistryReading: Sendable {
    /// Every registered project. Empty when the registry cannot be read — DDEV would have
    /// nothing to prune in that case either.
    func entries() -> [DDEVProjectRegistryEntry]
}

public extension DDEVProjectRegistryReading {
    /// Registered projects whose folder is not currently on disk.
    func unavailableEntries() -> [DDEVProjectRegistryEntry] {
        entries().filter { !$0.folderExists }
    }
}

public enum DDEVProjectRegistry {
    /// Parses DDEV's registry format, which `yaml.v3` writes as:
    ///
    ///     name:
    ///         approot: /path/to/project
    ///
    /// Deliberately a line parser rather than a YAML library: the file has exactly one shape,
    /// and a dependency for it would be dead weight. Keys and values may be quoted; any other
    /// nested key is ignored, and an entry without an `approot` is skipped.
    public static func parse(_ yaml: String) -> [(name: String, appRoot: String)] {
        var entries: [(name: String, appRoot: String)] = []
        var currentName: String?

        for rawLine in yaml.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline) {
            let line = String(rawLine)
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty, !trimmed.hasPrefix("#") else { continue }

            let isIndented = line.first?.isWhitespace == true
            if !isIndented {
                guard trimmed.hasSuffix(":") else { currentName = nil; continue }
                currentName = unquote(String(trimmed.dropLast()))
                continue
            }

            guard let name = currentName, trimmed.hasPrefix("approot:") else { continue }
            let value = unquote(String(trimmed.dropFirst("approot:".count)).trimmingCharacters(in: .whitespaces))
            guard !value.isEmpty else { continue }
            entries.append((name: name, appRoot: value))
            currentName = nil
        }
        return entries
    }

    private static func unquote(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespaces)
        guard trimmed.count >= 2, let first = trimmed.first, let last = trimmed.last,
              first == last, first == "\"" || first == "'" else { return trimmed }
        return String(trimmed.dropFirst().dropLast())
    }
}

/// Reads `~/.ddev/project_list.yaml` on every call — it is tiny, and a stale answer would defeat
/// the purpose (the drive may have just been mounted or unmounted).
public struct FileDDEVProjectRegistry: DDEVProjectRegistryReading {
    private let path: String
    private let folderExists: @Sendable (String) -> Bool

    public init(
        path: String = (NSHomeDirectory() as NSString).appendingPathComponent(".ddev/project_list.yaml"),
        folderExists: @escaping @Sendable (String) -> Bool = { path in
            var isDirectory: ObjCBool = false
            return FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) && isDirectory.boolValue
        }
    ) {
        self.path = path
        self.folderExists = folderExists
    }

    public func entries() -> [DDEVProjectRegistryEntry] {
        guard let contents = try? String(contentsOfFile: path, encoding: .utf8) else { return [] }
        return DDEVProjectRegistry.parse(contents).map {
            DDEVProjectRegistryEntry(name: $0.name, appRoot: $0.appRoot, folderExists: folderExists($0.appRoot))
        }
    }
}

public struct InMemoryDDEVProjectRegistry: DDEVProjectRegistryReading {
    private let storedEntries: [DDEVProjectRegistryEntry]

    public init(entries: [DDEVProjectRegistryEntry]) {
        self.storedEntries = entries
    }

    public func entries() -> [DDEVProjectRegistryEntry] { storedEntries }
}
