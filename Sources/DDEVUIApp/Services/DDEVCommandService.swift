import Foundation

public final class DDEVCommandService: Sendable {
    private let commandRunner: CommandRunning
    private let ddevExecutable: String

    public init(
        commandRunner: CommandRunning = ProcessCommandRunner(),
        ddevExecutable: String = DDEVExecutableResolver().resolve()
    ) {
        self.commandRunner = commandRunner
        self.ddevExecutable = ddevExecutable
    }

    public func listProjects() async throws -> [DDEVProject] {
        let result = try await runDDEV(["list", "-j"])
        return try DDEVProject.decodeListPayload(Data(result.stdout.utf8))
    }

    public func describe(projectName: String) async throws -> DDEVProjectDetails {
        let result = try await runDDEV(["describe", projectName, "-j"])
        return try DDEVProjectDetails.decodeDescribePayload(Data(result.stdout.utf8))
    }

    @discardableResult
    public func start(projectName: String) async throws -> CommandResult {
        try await runDDEV(["start", projectName])
    }

    @discardableResult
    public func stop(projectName: String) async throws -> CommandResult {
        try await runDDEV(["stop", projectName])
    }

    @discardableResult
    public func restart(projectName: String) async throws -> CommandResult {
        try await runDDEV(["restart", projectName])
    }

    @discardableResult
    public func unlink(projectName: String) async throws -> CommandResult {
        try await runDDEV(["stop", "--unlist", projectName])
    }

    @discardableResult
    public func deleteDDEVData(projectName: String) async throws -> CommandResult {
        try await runDDEV(["delete", projectName])
    }

    @discardableResult
    public func startProject(in appRoot: String) async throws -> CommandResult {
        try await runDDEV(["start"], workingDirectory: appRoot)
    }

    @discardableResult
    public func configureProject(
        in appRoot: String,
        name: String,
        type: DDEVProjectType,
        docroot: String
    ) async throws -> CommandResult {
        try await runDDEV(
            ["config", "--project-name=\(name)", "--project-type=\(type.rawValue)", "--docroot=\(docroot)"],
            workingDirectory: appRoot
        )
    }

    @discardableResult
    public func setPHPVersion(_ version: String, in appRoot: String) async throws -> CommandResult {
        try await runDDEV(["config", "--php-version=\(version)"], workingDirectory: appRoot)
    }

    @discardableResult
    public func launchDatabaseTool(_ tool: DDEVDatabaseTool, in appRoot: String) async throws -> CommandResult {
        try await runDDEV([tool.rawValue], workingDirectory: appRoot)
    }

    @discardableResult
    public func importDatabase(_ options: DDEVDatabaseImportOptions, in appRoot: String) async throws -> CommandResult {
        var arguments = [
            "import-db",
            "--file=\(options.filePath)",
            "--database=\(options.database)"
        ]

        if let extractPath = options.extractPath {
            arguments.append("--extract-path=\(extractPath)")
        }

        if !options.dropExistingDatabase {
            arguments.append("--no-drop")
        }

        return try await runDDEV(arguments, workingDirectory: appRoot)
    }

    @discardableResult
    public func exportDatabase(_ options: DDEVDatabaseExportOptions, in appRoot: String) async throws -> CommandResult {
        try await runDDEV(
            [
                "export-db",
                "--file=\(options.outputPath)",
                "--database=\(options.database)"
            ] + options.compression.ddevArguments,
            workingDirectory: appRoot
        )
    }

    @discardableResult
    public func importFiles(_ options: DDEVFileImportOptions, in appRoot: String) async throws -> CommandResult {
        var arguments = ["import-files", "--source=\(options.sourcePath)"]

        if let targetPath = options.targetPath {
            arguments.append("--target=\(targetPath)")
        }

        if let extractPath = options.extractPath {
            arguments.append("--extract-path=\(extractPath)")
        }

        return try await runDDEV(arguments, workingDirectory: appRoot)
    }

    @discardableResult
    public func createSnapshot(name: String? = nil, in appRoot: String) async throws -> CommandResult {
        var arguments = ["snapshot"]

        if let name = name?.nilIfBlank {
            arguments.append("--name=\(name)")
        }

        return try await runDDEV(arguments, workingDirectory: appRoot)
    }

    @discardableResult
    public func listSnapshots(in appRoot: String) async throws -> CommandResult {
        try await runDDEV(["snapshot", "--list"], workingDirectory: appRoot)
    }

    @discardableResult
    public func restoreSnapshot(named snapshotName: String, in appRoot: String) async throws -> CommandResult {
        try await runDDEV(["snapshot", "restore", snapshotName], workingDirectory: appRoot)
    }

    @discardableResult
    public func restoreLatestSnapshot(in appRoot: String) async throws -> CommandResult {
        try await runDDEV(["snapshot", "restore", "--latest"], workingDirectory: appRoot)
    }

    @discardableResult
    public func cleanupSnapshots(in appRoot: String) async throws -> CommandResult {
        try await runDDEV(["snapshot", "--cleanup", "-y"], workingDirectory: appRoot)
    }

    @discardableResult
    public func cleanupSnapshot(named snapshotName: String, in appRoot: String) async throws -> CommandResult {
        try await runDDEV(["snapshot", "--cleanup", "--name=\(snapshotName)", "-y"], workingDirectory: appRoot)
    }

    @discardableResult
    public func logs(
        projectName: String,
        service: String,
        tail: Int,
        includeTimestamps: Bool = false,
        in appRoot: String
    ) async throws -> CommandResult {
        var arguments = ["logs", projectName, "--service=\(service)", "--tail=\(tail)"]

        if includeTimestamps {
            arguments.append("--time")
        }

        return try await runDDEV(arguments, workingDirectory: appRoot)
    }

    @discardableResult
    public func listInstalledAddOns(in appRoot: String) async throws -> CommandResult {
        try await runDDEV(["add-on", "list", "--installed"], workingDirectory: appRoot)
    }

    @discardableResult
    public func searchAddOns(query: String, in appRoot: String) async throws -> CommandResult {
        try await runDDEV(["add-on", "search", query], workingDirectory: appRoot)
    }

    @discardableResult
    public func getAddOn(_ repository: String, in appRoot: String) async throws -> CommandResult {
        try await runDDEV(["add-on", "get", repository], workingDirectory: appRoot)
    }

    @discardableResult
    public func removeAddOn(named name: String, in appRoot: String) async throws -> CommandResult {
        try await runDDEV(["add-on", "remove", name], workingDirectory: appRoot)
    }

    @discardableResult
    public func config(flags: [String], in appRoot: String) async throws -> CommandResult {
        guard flags.allSatisfy(\.isValidDDEVConfigFlag) else {
            throw DDEVCommandValidationError.invalidConfigFlags(flags)
        }

        return try await runDDEV(["config"] + flags, workingDirectory: appRoot)
    }

    @discardableResult
    public func runProjectCommand(arguments: [String], in appRoot: String) async throws -> CommandResult {
        guard !arguments.isEmpty else {
            throw DDEVCommandValidationError.emptyProjectCommand
        }

        return try await runDDEV(arguments, workingDirectory: appRoot)
    }

    @discardableResult
    public func utilityDiagnose(in appRoot: String) async throws -> CommandResult {
        try await runDDEV(["utility", "diagnose"], workingDirectory: appRoot)
    }

    @discardableResult
    public func utilityConfigYAML(omitKeys: [String] = [], in appRoot: String) async throws -> CommandResult {
        var arguments = ["utility", "configyaml", "--full-yaml"]

        if !omitKeys.isEmpty {
            arguments.append("--omit-keys=\(omitKeys.joined(separator: ","))")
        }

        return try await runDDEV(arguments, workingDirectory: appRoot)
    }

    @discardableResult
    public func mutagen(_ command: DDEVMutagenCommand, in appRoot: String) async throws -> CommandResult {
        try await runDDEV(["mutagen", command.rawValue], workingDirectory: appRoot)
    }

    @discardableResult
    public func xhgui(_ command: DDEVXHGuiCommand, in appRoot: String) async throws -> CommandResult {
        try await runDDEV(["xhgui", command.rawValue], workingDirectory: appRoot)
    }

    @discardableResult
    public func updateWordPressCore(in appRoot: String) async throws -> CommandResult {
        try await runDDEV(["wp", "core", "update"], workingDirectory: appRoot)
    }

    @discardableResult
    public func updateWordPressPlugins(in appRoot: String) async throws -> CommandResult {
        try await runDDEV(["wp", "plugin", "update", "--all"], workingDirectory: appRoot)
    }

    @discardableResult
    public func updateWordPressThemes(in appRoot: String) async throws -> CommandResult {
        try await runDDEV(["wp", "theme", "update", "--all"], workingDirectory: appRoot)
    }

    private func runDDEV(_ arguments: [String], workingDirectory: String? = nil) async throws -> CommandResult {
        try await commandRunner.run(CommandSpec(executable: ddevExecutable, arguments: arguments, workingDirectory: workingDirectory))
    }
}

public enum DDEVDatabaseTool: String, CaseIterable, Codable, Identifiable, Sendable {
    case sequelAce = "sequelace"
    case tablePlus = "tableplus"
    case querious
    case dbeaver

    public var id: String {
        rawValue
    }

    public var displayName: String {
        switch self {
        case .sequelAce:
            "Sequel Ace"
        case .tablePlus:
            "TablePlus"
        case .querious:
            "Querious"
        case .dbeaver:
            "DBeaver"
        }
    }

    public var bundleIdentifier: String {
        switch self {
        case .sequelAce:
            "com.sequel-ace.sequel-ace"
        case .tablePlus:
            "com.tinyapp.TablePlus"
        case .querious:
            "com.araeliumgroup.querious"
        case .dbeaver:
            "org.jkiss.dbeaver.core.product"
        }
    }
}

public struct DDEVFileImportOptions: Equatable, Sendable {
    public let sourcePath: String
    public let targetPath: String?
    public let extractPath: String?

    public init(sourcePath: String, targetPath: String? = nil, extractPath: String? = nil) {
        self.sourcePath = sourcePath
        self.targetPath = targetPath?.nilIfBlank
        self.extractPath = extractPath?.nilIfBlank
    }
}

public enum DDEVMutagenCommand: String, CaseIterable, Sendable {
    case status
    case sync
    case reset
    case logs
}

public enum DDEVXHGuiCommand: String, CaseIterable, Sendable {
    case on
    case off
    case launch
    case status
}

public enum DDEVCommandValidationError: Error, Equatable, Sendable {
    case invalidConfigFlags([String])
    case emptyProjectCommand
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    var isValidDDEVConfigFlag: Bool {
        hasPrefix("--") && count > 2
    }
}
