import Foundation

/// A user-defined DDEV custom command (A13) — a script in `.ddev/commands/{host,web,db}/` (project)
/// or `~/.ddev/commands/{host,web,db}/` (global). The command name is the filename; `ddev <name>`
/// runs it. A GUI can't know these statically, so they're discovered at runtime.
public struct DDEVCustomCommand: Equatable, Sendable, Identifiable {
    public enum Scope: String, Equatable, Sendable {
        case host, web, db
    }

    public let name: String
    public let description: String?
    public let scope: Scope

    public var id: String { "\(scope.rawValue):\(name)" }

    public init(name: String, description: String?, scope: Scope) {
        self.name = name
        self.description = description
        self.scope = scope
    }

    /// Extracts the `## Description:` annotation DDEV custom commands conventionally carry.
    public static func parseDescription(from contents: String) -> String? {
        for line in contents.split(separator: "\n", omittingEmptySubsequences: false) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("## Description:") else { continue }
            let value = trimmed.dropFirst("## Description:".count).trimmingCharacters(in: .whitespaces)
            return value.isEmpty ? nil : value
        }
        return nil
    }

    /// Whether a filename in a commands directory is an executable command (vs. docs/examples). DDEV
    /// excludes `README*`, `*.example` (must be renamed to activate), and dotfiles like `.gitattributes`.
    public static func isCommandFile(_ filename: String) -> Bool {
        guard !filename.isEmpty, !filename.hasPrefix(".") else { return false }
        if filename.hasSuffix(".example") { return false }
        if filename.lowercased().hasPrefix("readme") { return false }
        return true
    }
}

/// Discovers custom commands at runtime by scanning the project and global commands directories.
public protocol CustomCommandDiscovering: Sendable {
    func discoverCustomCommands(appRoot: String) async -> [DDEVCustomCommand]
}

public struct FileSystemCustomCommandDiscovery: CustomCommandDiscovering {
    private let globalCommandsRoot: String
    private let listDirectory: @Sendable (String) -> [String]
    private let readFile: @Sendable (String) -> String?

    public init(
        globalCommandsRoot: String = (NSHomeDirectory() as NSString).appendingPathComponent(".ddev/commands"),
        listDirectory: @escaping @Sendable (String) -> [String] = { path in
            (try? FileManager.default.contentsOfDirectory(atPath: path)) ?? []
        },
        readFile: @escaping @Sendable (String) -> String? = { path in
            try? String(contentsOfFile: path, encoding: .utf8)
        }
    ) {
        self.globalCommandsRoot = globalCommandsRoot
        self.listDirectory = listDirectory
        self.readFile = readFile
    }

    public func discoverCustomCommands(appRoot: String) async -> [DDEVCustomCommand] {
        let scopes: [(dir: String, scope: DDEVCustomCommand.Scope)] = [
            ("host", .host), ("web", .web), ("db", .db)
        ]
        let projectRoot = (appRoot as NSString).appendingPathComponent(".ddev/commands")
        var byName: [String: DDEVCustomCommand] = [:]

        // Global first, then project — so a project command of the same name overrides the global one.
        for root in [globalCommandsRoot, projectRoot] {
            for (dir, scope) in scopes {
                let dirPath = (root as NSString).appendingPathComponent(dir)
                for filename in listDirectory(dirPath) where DDEVCustomCommand.isCommandFile(filename) {
                    let filePath = (dirPath as NSString).appendingPathComponent(filename)
                    let description = readFile(filePath).flatMap(DDEVCustomCommand.parseDescription)
                    byName[filename] = DDEVCustomCommand(name: filename, description: description, scope: scope)
                }
            }
        }

        return byName.values.sorted { $0.name < $1.name }
    }
}
