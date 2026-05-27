import Foundation

public final class DDEVCommandService: Sendable {
    private let commandRunner: CommandRunning

    public init(commandRunner: CommandRunning = ProcessCommandRunner()) {
        self.commandRunner = commandRunner
    }

    public func listProjects() async throws -> [DDEVProject] {
        let result = try await runDDEV(["list", "-j"])
        return try DDEVProject.decodeListPayload(Data(result.stdout.utf8))
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
    public func launchDatabaseTool(_ tool: DDEVDatabaseTool, in appRoot: String) async throws -> CommandResult {
        try await runDDEV([tool.rawValue], workingDirectory: appRoot)
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
        try await commandRunner.run(CommandSpec(executable: "ddev", arguments: arguments, workingDirectory: workingDirectory))
    }
}

public enum DDEVDatabaseTool: String, CaseIterable, Sendable {
    case sequelAce = "sequelace"
    case tablePlus = "tableplus"
    case querious
    case dbeaver
}
