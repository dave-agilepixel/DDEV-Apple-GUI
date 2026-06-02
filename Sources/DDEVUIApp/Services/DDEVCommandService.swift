import Foundation

public final class DDEVCommandService: Sendable {
    private let commandRunner: CommandRunning
    private let ddevExecutable: String
    private let fileExists: @Sendable (String) -> Bool

    public init(
        commandRunner: CommandRunning = ProcessCommandRunner(),
        ddevExecutable: String = DDEVExecutableResolver().resolve(),
        fileExists: @escaping @Sendable (String) -> Bool = { FileManager.default.isReadableFile(atPath: $0) }
    ) {
        self.commandRunner = commandRunner
        self.ddevExecutable = ddevExecutable
        self.fileExists = fileExists
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
    public func start(projectName: String, onOutputLine: (@Sendable (String) -> Void)?) async throws -> CommandResult {
        try await runDDEV(["start", projectName], onOutputLine: onOutputLine)
    }

    @discardableResult
    public func restart(projectName: String, onOutputLine: (@Sendable (String) -> Void)?) async throws -> CommandResult {
        try await runDDEV(["restart", projectName], onOutputLine: onOutputLine)
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
        // Surface a missing/unreadable file as a clear precondition error rather than an opaque
        // "exit code N" from ddev (audit L10).
        guard fileExists(options.filePath) else {
            throw DDEVCommandPreconditionError.fileNotReadable(path: options.filePath)
        }

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
    public func importFiles(_ options: DDEVImportFilesOptions, in appRoot: String) async throws -> CommandResult {
        // Surface a missing/unreadable source as a clear precondition error rather than an opaque
        // ddev exit code (mirrors importDatabase, audit L10). `isReadableFile` is true for both a
        // readable directory and a readable archive, which is exactly what import-files accepts.
        guard fileExists(options.source) else {
            throw DDEVCommandPreconditionError.fileNotReadable(path: options.source)
        }

        var arguments = ["import-files", "--source=\(options.source)"]

        if let target = options.target {
            arguments.append("--target=\(target)")
        }
        if let extractPath = options.extractPath {
            arguments.append("--extract-path=\(extractPath)")
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
        try Self.rejectDashPrefixed(snapshotName, field: "snapshot name")
        return try await runDDEV(["snapshot", "restore", snapshotName], workingDirectory: appRoot)
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
    public func listInstalledAddOns(projectName: String, in appRoot: String) async throws -> CommandResult {
        try await runDDEV(
            ["add-on", "list", "--installed", "--project", projectName, "--json-output"],
            workingDirectory: appRoot
        )
    }

    @discardableResult
    public func searchAddOns(query: String, in appRoot: String) async throws -> CommandResult {
        try Self.rejectDashPrefixed(query, field: "search query")
        return try await runDDEV(["add-on", "search", query, "--json-output"], workingDirectory: appRoot)
    }

    @discardableResult
    public func getAddOn(_ repository: String, projectName: String, in appRoot: String) async throws -> CommandResult {
        try Self.rejectDashPrefixed(repository, field: "add-on repository")
        return try await runDDEV(["add-on", "get", repository, "--project", projectName], workingDirectory: appRoot)
    }

    @discardableResult
    public func removeAddOn(named name: String, projectName: String, in appRoot: String) async throws -> CommandResult {
        try Self.rejectDashPrefixed(name, field: "add-on name")
        return try await runDDEV(["add-on", "remove", name, "--project", projectName], workingDirectory: appRoot)
    }

    // Refuse to forward user-controlled positional arguments that look like flags.
    // A value such as `--help` passed positionally to a cobra/pflag CLI like ddev would
    // be parsed as an option, not the intended snapshot/repository/query name. We don't
    // append a `--` separator because that requires a per-version compatibility audit.
    private static func rejectDashPrefixed(_ value: String, field: String) throws {
        if value.hasPrefix("-") {
            throw DDEVCommandValidationError.dashPrefixedArgument(field: field, value: value)
        }
    }

    @discardableResult
    public func applyConfigChange(_ change: DDEVConfigChange, in appRoot: String) async throws -> CommandResult {
        // Flags come exclusively from the closed DDEVConfigChange enum, so there is no untrusted
        // input to validate — the old isValidDDEVConfigFlag check was false safety (it accepted
        // "--" + anything) and the public arbitrary-flag config(flags:) entry point had no callers,
        // so both were removed (audit L8).
        try await runDDEV(["config"] + change.ddevFlags, workingDirectory: appRoot)
    }

    @discardableResult
    public func runProjectCommand(arguments: [String], in appRoot: String) async throws -> CommandResult {
        guard !arguments.isEmpty else {
            throw DDEVCommandValidationError.emptyProjectCommand
        }

        return try await runDDEV(arguments, workingDirectory: appRoot)
    }

    @discardableResult
    public func version() async throws -> CommandResult {
        try await runDDEV(["version"])
    }

    public func versionInfo() async throws -> DDEVVersionInfo {
        let result = try await runDDEV(["version", "-j"])
        return try DDEVVersionInfo.decodeVersionPayload(Data(result.stdout.utf8))
    }

    @discardableResult
    public func utilityDiagnose(in appRoot: String? = nil) async throws -> CommandResult {
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
    public func utilityCheckCustomConfig(in appRoot: String) async throws -> CommandResult {
        try await runDDEV(["utility", "check-custom-config"], workingDirectory: appRoot)
    }

    @discardableResult
    public func utilityCheckDBMatch(in appRoot: String) async throws -> CommandResult {
        try await runDDEV(["utility", "check-db-match"], workingDirectory: appRoot)
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
    public func xdebug(_ command: DDEVXdebugCommand, in appRoot: String) async throws -> CommandResult {
        try await runDDEV(["xdebug", command.rawValue], workingDirectory: appRoot)
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

    private func runDDEV(_ arguments: [String], workingDirectory: String? = nil,
                         onOutputLine: (@Sendable (String) -> Void)?) async throws -> CommandResult {
        try await commandRunner.run(
            CommandSpec(executable: ddevExecutable, arguments: arguments, workingDirectory: workingDirectory),
            onOutputLine: onOutputLine
        )
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

public enum DDEVCommandPreconditionError: LocalizedError, Equatable {
    case fileNotReadable(path: String)

    public var errorDescription: String? {
        switch self {
        case .fileNotReadable(let path):
            return "File not found or not readable: \(path)"
        }
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

public enum DDEVXdebugCommand: String, CaseIterable, Sendable {
    case on
    case off
    case status
}

public enum DDEVCommandValidationError: Error, Equatable, Sendable {
    case emptyProjectCommand
    case dashPrefixedArgument(field: String, value: String)
}
