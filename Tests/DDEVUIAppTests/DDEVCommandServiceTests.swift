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

    func testDefaultDatabaseImportRunsInProjectDirectory() async throws {
        let runner = RecordingCommandRunner(result: .success(CommandResult.success()))
        let service = DDEVCommandService(commandRunner: runner, ddevExecutable: "ddev", fileExists: { _ in true })

        _ = try await service.importDatabase(
            DDEVDatabaseImportOptions(filePath: "/Users/dave/Downloads/db.sql.gz"),
            in: "/Users/dave/site"
        )

        XCTAssertEqual(runner.commands, [
            CommandSpec(
                executable: "ddev",
                arguments: ["import-db", "--file=/Users/dave/Downloads/db.sql.gz", "--database=db"],
                workingDirectory: "/Users/dave/site"
            )
        ])
    }

    func testNamedDatabaseImportIncludesArchiveOptionsAndNoDrop() async throws {
        let runner = RecordingCommandRunner(result: .success(CommandResult.success()))
        let service = DDEVCommandService(commandRunner: runner, ddevExecutable: "ddev", fileExists: { _ in true })

        _ = try await service.importDatabase(
            DDEVDatabaseImportOptions(
                filePath: "/Users/dave/Downloads/archive.tar.gz",
                database: "legacy",
                extractPath: "dump/database.sql",
                dropExistingDatabase: false
            ),
            in: "/Users/dave/site"
        )

        XCTAssertEqual(runner.commands, [
            CommandSpec(
                executable: "ddev",
                arguments: [
                    "import-db",
                    "--file=/Users/dave/Downloads/archive.tar.gz",
                    "--database=legacy",
                    "--extract-path=dump/database.sql",
                    "--no-drop"
                ],
                workingDirectory: "/Users/dave/site"
            )
        ])
    }

    func testDatabaseExportCompressionOptionsRunInProjectDirectory() async throws {
        let runner = RecordingCommandRunner(result: .success(CommandResult.success()))
        let service = DDEVCommandService(commandRunner: runner, ddevExecutable: "ddev")

        _ = try await service.exportDatabase(
            DDEVDatabaseExportOptions(outputPath: "/Users/dave/Backups/db.sql.gz"),
            in: "/Users/dave/site"
        )
        _ = try await service.exportDatabase(
            DDEVDatabaseExportOptions(outputPath: "/Users/dave/Backups/db.sql", compression: .none),
            in: "/Users/dave/site"
        )
        _ = try await service.exportDatabase(
            DDEVDatabaseExportOptions(outputPath: "/Users/dave/Backups/db.sql.bz2", compression: .bzip2),
            in: "/Users/dave/site"
        )
        _ = try await service.exportDatabase(
            DDEVDatabaseExportOptions(outputPath: "/Users/dave/Backups/db.sql.xz", database: "legacy", compression: .xz),
            in: "/Users/dave/site"
        )

        XCTAssertEqual(runner.commands, [
            CommandSpec(
                executable: "ddev",
                arguments: ["export-db", "--file=/Users/dave/Backups/db.sql.gz", "--database=db", "--gzip"],
                workingDirectory: "/Users/dave/site"
            ),
            CommandSpec(
                executable: "ddev",
                arguments: ["export-db", "--file=/Users/dave/Backups/db.sql", "--database=db", "--gzip=false"],
                workingDirectory: "/Users/dave/site"
            ),
            CommandSpec(
                executable: "ddev",
                arguments: ["export-db", "--file=/Users/dave/Backups/db.sql.bz2", "--database=db", "--bzip2"],
                workingDirectory: "/Users/dave/site"
            ),
            CommandSpec(
                executable: "ddev",
                arguments: ["export-db", "--file=/Users/dave/Backups/db.sql.xz", "--database=legacy", "--xz"],
                workingDirectory: "/Users/dave/site"
            )
        ])
    }

    func testDatabaseImportRejectsUnreadableFileWithClearError() async throws {
        let runner = RecordingCommandRunner(result: .success(CommandResult.success()))
        let service = DDEVCommandService(commandRunner: runner, ddevExecutable: "ddev", fileExists: { _ in false })

        do {
            _ = try await service.importDatabase(
                DDEVDatabaseImportOptions(filePath: "/Users/dave/Downloads/missing.sql.gz"),
                in: "/Users/dave/site"
            )
            XCTFail("Expected a precondition error for an unreadable file")
        } catch let error as DDEVCommandPreconditionError {
            XCTAssertEqual(error, .fileNotReadable(path: "/Users/dave/Downloads/missing.sql.gz"))
        }

        XCTAssertTrue(runner.commands.isEmpty, "ddev is not invoked when the source file is unreadable")
    }

    func testSnapshotCommandsRunInProjectDirectory() async throws {
        let runner = RecordingCommandRunner(result: .success(CommandResult.success()))
        let service = DDEVCommandService(commandRunner: runner, ddevExecutable: "ddev")

        _ = try await service.createSnapshot(in: "/Users/dave/site")
        _ = try await service.createSnapshot(name: "before-upgrade", in: "/Users/dave/site")
        _ = try await service.listSnapshots(in: "/Users/dave/site")
        _ = try await service.restoreSnapshot(named: "before-upgrade", in: "/Users/dave/site")
        _ = try await service.restoreLatestSnapshot(in: "/Users/dave/site")
        _ = try await service.cleanupSnapshots(in: "/Users/dave/site")
        _ = try await service.cleanupSnapshot(named: "before-upgrade", in: "/Users/dave/site")

        XCTAssertEqual(runner.commands, [
            CommandSpec(executable: "ddev", arguments: ["snapshot"], workingDirectory: "/Users/dave/site"),
            CommandSpec(executable: "ddev", arguments: ["snapshot", "--name=before-upgrade"], workingDirectory: "/Users/dave/site"),
            CommandSpec(executable: "ddev", arguments: ["snapshot", "--list"], workingDirectory: "/Users/dave/site"),
            CommandSpec(executable: "ddev", arguments: ["snapshot", "restore", "before-upgrade"], workingDirectory: "/Users/dave/site"),
            CommandSpec(executable: "ddev", arguments: ["snapshot", "restore", "--latest"], workingDirectory: "/Users/dave/site"),
            CommandSpec(executable: "ddev", arguments: ["snapshot", "--cleanup", "-y"], workingDirectory: "/Users/dave/site"),
            CommandSpec(executable: "ddev", arguments: ["snapshot", "--cleanup", "--name=before-upgrade", "-y"], workingDirectory: "/Users/dave/site")
        ])
    }

    func testLogsCommandRunsInProjectDirectory() async throws {
        let runner = RecordingCommandRunner(result: .success(CommandResult.success()))
        let service = DDEVCommandService(commandRunner: runner, ddevExecutable: "ddev")

        _ = try await service.logs(projectName: "aqua-pura", service: "web", tail: 100, includeTimestamps: false, in: "/Users/dave/site")
        _ = try await service.logs(projectName: "aqua-pura", service: "db", tail: 50, includeTimestamps: true, in: "/Users/dave/site")

        XCTAssertEqual(runner.commands, [
            CommandSpec(
                executable: "ddev",
                arguments: ["logs", "aqua-pura", "--service=web", "--tail=100"],
                workingDirectory: "/Users/dave/site"
            ),
            CommandSpec(
                executable: "ddev",
                arguments: ["logs", "aqua-pura", "--service=db", "--tail=50", "--time"],
                workingDirectory: "/Users/dave/site"
            )
        ])
    }

    func testAddOnCommandsUseProjectNameAndJSONOutput() async throws {
        let runner = RecordingCommandRunner(result: .success(CommandResult.success()))
        let service = DDEVCommandService(commandRunner: runner, ddevExecutable: "ddev")

        _ = try await service.listInstalledAddOns(projectName: "aqua-pura", in: "/Users/dave/site")
        _ = try await service.searchAddOns(query: "redis", in: "/Users/dave/site")
        _ = try await service.getAddOn("ddev/ddev-redis", projectName: "aqua-pura", in: "/Users/dave/site")
        _ = try await service.removeAddOn(named: "redis", projectName: "aqua-pura", in: "/Users/dave/site")

        XCTAssertEqual(runner.commands, [
            CommandSpec(
                executable: "ddev",
                arguments: ["add-on", "list", "--installed", "--project", "aqua-pura", "--json-output"],
                workingDirectory: "/Users/dave/site"
            ),
            CommandSpec(
                executable: "ddev",
                arguments: ["add-on", "search", "redis", "--json-output"],
                workingDirectory: "/Users/dave/site"
            ),
            CommandSpec(
                executable: "ddev",
                arguments: ["add-on", "get", "ddev/ddev-redis", "--project", "aqua-pura"],
                workingDirectory: "/Users/dave/site"
            ),
            CommandSpec(
                executable: "ddev",
                arguments: ["add-on", "remove", "redis", "--project", "aqua-pura"],
                workingDirectory: "/Users/dave/site"
            )
        ])
    }

    func testProjectConfigChangesRunInProjectDirectory() async throws {
        let runner = RecordingCommandRunner(result: .success(CommandResult.success()))
        let service = DDEVCommandService(commandRunner: runner, ddevExecutable: "ddev")

        _ = try await service.applyConfigChange(.phpVersion("8.3"), in: "/Users/dave/site")
        _ = try await service.applyConfigChange(.nodeJSVersion("22"), in: "/Users/dave/site")
        _ = try await service.applyConfigChange(.database(type: .mariadb, version: "11.8"), in: "/Users/dave/site")
        _ = try await service.applyConfigChange(.webserverType(.apacheFPM), in: "/Users/dave/site")
        _ = try await service.applyConfigChange(.performanceMode(.mutagen), in: "/Users/dave/site")
        _ = try await service.applyConfigChange(.xdebugEnabled(true), in: "/Users/dave/site")
        _ = try await service.applyConfigChange(.xhprofMode(.prepend), in: "/Users/dave/site")
        _ = try await service.applyConfigChange(.uploadDirs(["web/app/uploads"]), in: "/Users/dave/site")
        _ = try await service.applyConfigChange(.additionalHostnames(["www", "admin"]), in: "/Users/dave/site")

        XCTAssertEqual(runner.commands, [
            CommandSpec(executable: "ddev", arguments: ["config", "--php-version=8.3"], workingDirectory: "/Users/dave/site"),
            CommandSpec(executable: "ddev", arguments: ["config", "--nodejs-version=22"], workingDirectory: "/Users/dave/site"),
            CommandSpec(executable: "ddev", arguments: ["config", "--database=mariadb:11.8"], workingDirectory: "/Users/dave/site"),
            CommandSpec(executable: "ddev", arguments: ["config", "--webserver-type=apache-fpm"], workingDirectory: "/Users/dave/site"),
            CommandSpec(executable: "ddev", arguments: ["config", "--performance-mode=mutagen"], workingDirectory: "/Users/dave/site"),
            CommandSpec(executable: "ddev", arguments: ["config", "--xdebug-enabled=true"], workingDirectory: "/Users/dave/site"),
            CommandSpec(executable: "ddev", arguments: ["config", "--xhprof-mode=prepend"], workingDirectory: "/Users/dave/site"),
            CommandSpec(executable: "ddev", arguments: ["config", "--upload-dirs=web/app/uploads"], workingDirectory: "/Users/dave/site"),
            CommandSpec(executable: "ddev", arguments: ["config", "--additional-hostnames=www,admin"], workingDirectory: "/Users/dave/site")
        ])
    }

    func testProjectCommandRunsArbitraryDDEVArgumentsInProjectDirectory() async throws {
        let runner = RecordingCommandRunner(result: .success(CommandResult.success()))
        let service = DDEVCommandService(commandRunner: runner, ddevExecutable: "ddev")

        _ = try await service.runProjectCommand(arguments: ["artisan", "migrate"], in: "/Users/dave/site")
        _ = try await service.runProjectCommand(arguments: ["composer", "install"], in: "/Users/dave/site")

        XCTAssertEqual(runner.commands, [
            CommandSpec(executable: "ddev", arguments: ["artisan", "migrate"], workingDirectory: "/Users/dave/site"),
            CommandSpec(executable: "ddev", arguments: ["composer", "install"], workingDirectory: "/Users/dave/site")
        ])
    }

    func testUtilityCommandsRunInProjectDirectory() async throws {
        let runner = RecordingCommandRunner(result: .success(CommandResult.success()))
        let service = DDEVCommandService(commandRunner: runner, ddevExecutable: "ddev")

        _ = try await service.version()
        _ = try await service.utilityDiagnose()
        _ = try await service.utilityDiagnose(in: "/Users/dave/site")
        _ = try await service.utilityConfigYAML(omitKeys: ["web_environment"], in: "/Users/dave/site")
        _ = try await service.utilityCheckCustomConfig(in: "/Users/dave/site")
        _ = try await service.utilityCheckDBMatch(in: "/Users/dave/site")

        XCTAssertEqual(runner.commands, [
            CommandSpec(executable: "ddev", arguments: ["version"], workingDirectory: nil),
            CommandSpec(executable: "ddev", arguments: ["utility", "diagnose"], workingDirectory: nil),
            CommandSpec(executable: "ddev", arguments: ["utility", "diagnose"], workingDirectory: "/Users/dave/site"),
            CommandSpec(
                executable: "ddev",
                arguments: ["utility", "configyaml", "--full-yaml", "--omit-keys=web_environment"],
                workingDirectory: "/Users/dave/site"
            ),
            CommandSpec(
                executable: "ddev",
                arguments: ["utility", "check-custom-config"],
                workingDirectory: "/Users/dave/site"
            ),
            CommandSpec(
                executable: "ddev",
                arguments: ["utility", "check-db-match"],
                workingDirectory: "/Users/dave/site"
            )
        ])
    }

    func testMutagenCommandsRunInProjectDirectory() async throws {
        let runner = RecordingCommandRunner(result: .success(CommandResult.success()))
        let service = DDEVCommandService(commandRunner: runner, ddevExecutable: "ddev")

        _ = try await service.mutagen(.status, in: "/Users/dave/site")
        _ = try await service.mutagen(.sync, in: "/Users/dave/site")
        _ = try await service.mutagen(.reset, in: "/Users/dave/site")
        _ = try await service.mutagen(.logs, in: "/Users/dave/site")

        XCTAssertEqual(runner.commands, [
            CommandSpec(executable: "ddev", arguments: ["mutagen", "status"], workingDirectory: "/Users/dave/site"),
            CommandSpec(executable: "ddev", arguments: ["mutagen", "sync"], workingDirectory: "/Users/dave/site"),
            CommandSpec(executable: "ddev", arguments: ["mutagen", "reset"], workingDirectory: "/Users/dave/site"),
            CommandSpec(executable: "ddev", arguments: ["mutagen", "logs"], workingDirectory: "/Users/dave/site")
        ])
    }

    func testRejectsDashPrefixedSnapshotName() async throws {
        let runner = RecordingCommandRunner(result: .success(CommandResult.success()))
        let service = DDEVCommandService(commandRunner: runner, ddevExecutable: "ddev")

        do {
            _ = try await service.restoreSnapshot(named: "--latest", in: "/Users/dave/site")
            XCTFail("Expected dashPrefixedArgument validation error")
        } catch DDEVCommandValidationError.dashPrefixedArgument(let field, let value) {
            XCTAssertEqual(field, "snapshot name")
            XCTAssertEqual(value, "--latest")
        }

        XCTAssertTrue(runner.commands.isEmpty, "Runner should not be invoked when validation rejects input")
    }

    func testRejectsDashPrefixedAddOnArguments() async throws {
        let runner = RecordingCommandRunner(result: .success(CommandResult.success()))
        let service = DDEVCommandService(commandRunner: runner, ddevExecutable: "ddev")

        await XCTAssertThrowsValidationError {
            _ = try await service.searchAddOns(query: "--help", in: "/Users/dave/site")
        }
        await XCTAssertThrowsValidationError {
            _ = try await service.getAddOn("--config=/etc/passwd", projectName: "aqua-pura", in: "/Users/dave/site")
        }
        await XCTAssertThrowsValidationError {
            _ = try await service.removeAddOn(named: "-all", projectName: "aqua-pura", in: "/Users/dave/site")
        }

        XCTAssertTrue(runner.commands.isEmpty)
    }

    func testXdebugCommandsRunInProjectDirectory() async throws {
        let runner = RecordingCommandRunner(result: .success(CommandResult.success()))
        let service = DDEVCommandService(commandRunner: runner, ddevExecutable: "ddev")

        _ = try await service.xdebug(.on, in: "/Users/dave/site")
        _ = try await service.xdebug(.off, in: "/Users/dave/site")
        _ = try await service.xdebug(.status, in: "/Users/dave/site")

        XCTAssertEqual(runner.commands, [
            CommandSpec(executable: "ddev", arguments: ["xdebug", "on"], workingDirectory: "/Users/dave/site"),
            CommandSpec(executable: "ddev", arguments: ["xdebug", "off"], workingDirectory: "/Users/dave/site"),
            CommandSpec(executable: "ddev", arguments: ["xdebug", "status"], workingDirectory: "/Users/dave/site")
        ])
    }

    func testXHGuiCommandsRunInProjectDirectory() async throws {
        let runner = RecordingCommandRunner(result: .success(CommandResult.success()))
        let service = DDEVCommandService(commandRunner: runner, ddevExecutable: "ddev")

        _ = try await service.xhgui(.on, in: "/Users/dave/site")
        _ = try await service.xhgui(.off, in: "/Users/dave/site")
        _ = try await service.xhgui(.launch, in: "/Users/dave/site")
        _ = try await service.xhgui(.status, in: "/Users/dave/site")

        XCTAssertEqual(runner.commands, [
            CommandSpec(executable: "ddev", arguments: ["xhgui", "on"], workingDirectory: "/Users/dave/site"),
            CommandSpec(executable: "ddev", arguments: ["xhgui", "off"], workingDirectory: "/Users/dave/site"),
            CommandSpec(executable: "ddev", arguments: ["xhgui", "launch"], workingDirectory: "/Users/dave/site"),
            CommandSpec(executable: "ddev", arguments: ["xhgui", "status"], workingDirectory: "/Users/dave/site")
        ])
    }
}

private func XCTAssertThrowsValidationError(
    _ expression: () async throws -> Void,
    file: StaticString = #filePath,
    line: UInt = #line
) async {
    do {
        try await expression()
        XCTFail("Expected DDEVCommandValidationError to be thrown", file: file, line: line)
    } catch is DDEVCommandValidationError {
        // Expected.
    } catch {
        XCTFail("Expected DDEVCommandValidationError, got \(error)", file: file, line: line)
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
