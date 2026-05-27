import XCTest
@testable import DDEVUIApp

final class DDEVCommandServiceTests: XCTestCase {
    func testListProjectsRunsDDEVListJSON() async throws {
        let runner = RecordingCommandRunner(result: .success(CommandResult.success(stdout: #"{"raw":[]}"#)))
        let service = DDEVCommandService(commandRunner: runner, ddevExecutable: "/opt/homebrew/bin/ddev")

        _ = try await service.listProjects()

        XCTAssertEqual(runner.commands, [
            CommandSpec(executable: "/opt/homebrew/bin/ddev", arguments: ["list", "-j"], workingDirectory: nil)
        ])
    }

    func testDescribeProjectRunsDDEVDescribeJSON() async throws {
        let runner = RecordingCommandRunner(result: .success(CommandResult.success(stdout: #"{"raw":{"php_version":"8.4"}}"#)))
        let service = DDEVCommandService(commandRunner: runner, ddevExecutable: "ddev")

        let details = try await service.describe(projectName: "aqua-pura")

        XCTAssertEqual(details.phpVersion, "8.4")
        XCTAssertEqual(runner.commands, [
            CommandSpec(executable: "ddev", arguments: ["describe", "aqua-pura", "-j"], workingDirectory: nil)
        ])
    }

    func testLifecycleCommandsUseProjectName() async throws {
        let runner = RecordingCommandRunner(result: .success(CommandResult.success()))
        let service = DDEVCommandService(commandRunner: runner, ddevExecutable: "ddev")

        _ = try await service.start(projectName: "aqua-pura")
        _ = try await service.stop(projectName: "aqua-pura")
        _ = try await service.restart(projectName: "aqua-pura")
        _ = try await service.unlink(projectName: "aqua-pura")
        _ = try await service.deleteDDEVData(projectName: "aqua-pura")

        XCTAssertEqual(runner.commands, [
            CommandSpec(executable: "ddev", arguments: ["start", "aqua-pura"], workingDirectory: nil),
            CommandSpec(executable: "ddev", arguments: ["stop", "aqua-pura"], workingDirectory: nil),
            CommandSpec(executable: "ddev", arguments: ["restart", "aqua-pura"], workingDirectory: nil),
            CommandSpec(executable: "ddev", arguments: ["stop", "--unlist", "aqua-pura"], workingDirectory: nil),
            CommandSpec(executable: "ddev", arguments: ["delete", "aqua-pura"], workingDirectory: nil)
        ])
    }

    func testDatabaseToolCommandsRunInProjectDirectory() async throws {
        let runner = RecordingCommandRunner(result: .success(CommandResult.success()))
        let service = DDEVCommandService(commandRunner: runner, ddevExecutable: "ddev")

        _ = try await service.launchDatabaseTool(.tablePlus, in: "/Users/dave/site")
        _ = try await service.launchDatabaseTool(.sequelAce, in: "/Users/dave/site")
        _ = try await service.launchDatabaseTool(.querious, in: "/Users/dave/site")
        _ = try await service.launchDatabaseTool(.dbeaver, in: "/Users/dave/site")

        XCTAssertEqual(runner.commands, [
            CommandSpec(executable: "ddev", arguments: ["tableplus"], workingDirectory: "/Users/dave/site"),
            CommandSpec(executable: "ddev", arguments: ["sequelace"], workingDirectory: "/Users/dave/site"),
            CommandSpec(executable: "ddev", arguments: ["querious"], workingDirectory: "/Users/dave/site"),
            CommandSpec(executable: "ddev", arguments: ["dbeaver"], workingDirectory: "/Users/dave/site")
        ])
    }

    func testWordPressPresetCommandsRunInProjectDirectory() async throws {
        let runner = RecordingCommandRunner(result: .success(CommandResult.success()))
        let service = DDEVCommandService(commandRunner: runner, ddevExecutable: "ddev")

        _ = try await service.updateWordPressCore(in: "/Users/dave/site")
        _ = try await service.updateWordPressPlugins(in: "/Users/dave/site")
        _ = try await service.updateWordPressThemes(in: "/Users/dave/site")

        XCTAssertEqual(runner.commands, [
            CommandSpec(executable: "ddev", arguments: ["wp", "core", "update"], workingDirectory: "/Users/dave/site"),
            CommandSpec(executable: "ddev", arguments: ["wp", "plugin", "update", "--all"], workingDirectory: "/Users/dave/site"),
            CommandSpec(executable: "ddev", arguments: ["wp", "theme", "update", "--all"], workingDirectory: "/Users/dave/site")
        ])
    }

    func testAddFolderCommandsUseSelectedFolderAsWorkingDirectory() async throws {
        let runner = RecordingCommandRunner(result: .success(CommandResult.success()))
        let service = DDEVCommandService(commandRunner: runner, ddevExecutable: "ddev")

        _ = try await service.startProject(in: "/Users/dave/new-site")
        _ = try await service.configureProject(
            in: "/Users/dave/new-site",
            name: "new-site",
            type: .wordpress,
            docroot: "web"
        )

        XCTAssertEqual(runner.commands, [
            CommandSpec(executable: "ddev", arguments: ["start"], workingDirectory: "/Users/dave/new-site"),
            CommandSpec(
                executable: "ddev",
                arguments: ["config", "--project-name=new-site", "--project-type=wordpress", "--docroot=web"],
                workingDirectory: "/Users/dave/new-site"
            )
        ])
    }

    func testPHPVersionCommandRunsInProjectDirectory() async throws {
        let runner = RecordingCommandRunner(result: .success(CommandResult.success()))
        let service = DDEVCommandService(commandRunner: runner, ddevExecutable: "ddev")

        _ = try await service.setPHPVersion("8.3", in: "/Users/dave/site")

        XCTAssertEqual(runner.commands, [
            CommandSpec(executable: "ddev", arguments: ["config", "--php-version=8.3"], workingDirectory: "/Users/dave/site")
        ])
    }
}

private final class RecordingCommandRunner: CommandRunning, @unchecked Sendable {
    private let lock = NSLock()
    private let result: Result<CommandResult, Error>
    private var recordedCommands: [CommandSpec] = []

    var commands: [CommandSpec] {
        lock.withLock { recordedCommands }
    }

    init(result: Result<CommandResult, Error>) {
        self.result = result
    }

    func run(_ spec: CommandSpec) async throws -> CommandResult {
        lock.withLock {
            recordedCommands.append(spec)
        }
        return try result.get()
    }
}
