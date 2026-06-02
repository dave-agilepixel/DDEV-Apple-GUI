import XCTest
@testable import DDEVUIApp

@MainActor
final class ProjectConfigReloadTests: XCTestCase {
    func testReloadingConfigClearsCachedConfigWhileLoadIsInFlight() async throws {
        let configYAML = """
        php_version: "8.4"
        nodejs_version: "24"
        database:
          type: mariadb
          version: "11.8"
        webserver_type: nginx-fpm
        performance_mode: mutagen
        xdebug_enabled: false
        xhprof_mode: xhgui
        upload_dirs: [web/app/uploads]
        additional_hostnames: [www]
        """
        let service = SuspendedConfigDDEVService(configYAML: configYAML)
        let viewModel = ProjectDashboardViewModel(ddevService: service)
        viewModel.selectedProject = DDEVProject.configReloadSample
        viewModel.projectConfig = try DDEVConfig.parseYAML(configYAML)

        let loadTask = Task {
            await viewModel.loadConfigForSelectedProject()
        }

        await service.waitUntilConfigLoadStarts()

        XCTAssertNil(viewModel.projectConfig)

        await service.resumeConfigLoad()
        await loadTask.value

        XCTAssertEqual(viewModel.projectConfig?.phpVersion, "8.4")
    }
}

private final class SuspendedConfigDDEVService: DDEVServicing, @unchecked Sendable {
    private let configYAML: String
    private let gate = AsyncGate()

    init(configYAML: String) {
        self.configYAML = configYAML
    }

    func utilityConfigYAML(omitKeys: [String], in appRoot: String) async throws -> CommandResult {
        await gate.pause()
        return CommandResult.success(stdout: configYAML)
    }

    func waitUntilConfigLoadStarts() async {
        await gate.waitUntilPaused()
    }

    func resumeConfigLoad() async {
        await gate.resume()
    }

    func listProjects() async throws -> [DDEVProject] { throw UnexpectedCallError() }
    func describe(projectName: String) async throws -> DDEVProjectDetails { throw UnexpectedCallError() }
    func start(projectName: String) async throws -> CommandResult { throw UnexpectedCallError() }
    func stop(projectName: String) async throws -> CommandResult { throw UnexpectedCallError() }
    func restart(projectName: String) async throws -> CommandResult { throw UnexpectedCallError() }
    func unlink(projectName: String) async throws -> CommandResult { throw UnexpectedCallError() }
    func deleteDDEVData(projectName: String) async throws -> CommandResult { throw UnexpectedCallError() }
    func startProject(in appRoot: String) async throws -> CommandResult { throw UnexpectedCallError() }
    func configureProject(in appRoot: String, name: String, type: DDEVProjectType, docroot: String) async throws -> CommandResult { throw UnexpectedCallError() }
    func setPHPVersion(_ version: String, in appRoot: String) async throws -> CommandResult { throw UnexpectedCallError() }
    func launchDatabaseTool(_ tool: DDEVDatabaseTool, in appRoot: String) async throws -> CommandResult { throw UnexpectedCallError() }
    func importDatabase(_ options: DDEVDatabaseImportOptions, in appRoot: String) async throws -> CommandResult { throw UnexpectedCallError() }
    func exportDatabase(_ options: DDEVDatabaseExportOptions, in appRoot: String) async throws -> CommandResult { throw UnexpectedCallError() }
    func createSnapshot(name: String?, in appRoot: String) async throws -> CommandResult { throw UnexpectedCallError() }
    func listSnapshots(in appRoot: String) async throws -> CommandResult { throw UnexpectedCallError() }
    func restoreSnapshot(named snapshotName: String, in appRoot: String) async throws -> CommandResult { throw UnexpectedCallError() }
    func restoreLatestSnapshot(in appRoot: String) async throws -> CommandResult { throw UnexpectedCallError() }
    func cleanupSnapshots(in appRoot: String) async throws -> CommandResult { throw UnexpectedCallError() }
    func cleanupSnapshot(named snapshotName: String, in appRoot: String) async throws -> CommandResult { throw UnexpectedCallError() }
    func logs(projectName: String, service: String, tail: Int, includeTimestamps: Bool, in appRoot: String) async throws -> CommandResult { throw UnexpectedCallError() }
    func listInstalledAddOns(projectName: String, in appRoot: String) async throws -> CommandResult { throw UnexpectedCallError() }
    func searchAddOns(query: String, in appRoot: String) async throws -> CommandResult { throw UnexpectedCallError() }
    func getAddOn(_ repository: String, projectName: String, in appRoot: String) async throws -> CommandResult { throw UnexpectedCallError() }
    func removeAddOn(named name: String, projectName: String, in appRoot: String) async throws -> CommandResult { throw UnexpectedCallError() }
    func applyConfigChange(_ change: DDEVConfigChange, in appRoot: String) async throws -> CommandResult { throw UnexpectedCallError() }
    func runProjectCommand(arguments: [String], in appRoot: String) async throws -> CommandResult { throw UnexpectedCallError() }
    func exec(command: String, service: DDEVExecService, in appRoot: String) async throws -> CommandResult { throw UnexpectedCallError() }
    func version() async throws -> CommandResult { throw UnexpectedCallError() }
    func utilityDiagnose(in appRoot: String?) async throws -> CommandResult { throw UnexpectedCallError() }
    func utilityCheckCustomConfig(in appRoot: String) async throws -> CommandResult { throw UnexpectedCallError() }
    func utilityCheckDBMatch(in appRoot: String) async throws -> CommandResult { throw UnexpectedCallError() }
    func mutagen(_ command: DDEVMutagenCommand, in appRoot: String) async throws -> CommandResult { throw UnexpectedCallError() }
    func xhgui(_ command: DDEVXHGuiCommand, in appRoot: String) async throws -> CommandResult { throw UnexpectedCallError() }
    func xdebug(_ command: DDEVXdebugCommand, in appRoot: String) async throws -> CommandResult { throw UnexpectedCallError() }
    func updateWordPressCore(in appRoot: String) async throws -> CommandResult { throw UnexpectedCallError() }
    func updateWordPressPlugins(in appRoot: String) async throws -> CommandResult { throw UnexpectedCallError() }
    func updateWordPressThemes(in appRoot: String) async throws -> CommandResult { throw UnexpectedCallError() }
}

private actor AsyncGate {
    private var isPaused = false
    private var pauseWaiters: [CheckedContinuation<Void, Never>] = []
    private var resumeWaiter: CheckedContinuation<Void, Never>?

    func pause() async {
        isPaused = true
        pauseWaiters.forEach { $0.resume() }
        pauseWaiters.removeAll()

        await withCheckedContinuation { continuation in
            resumeWaiter = continuation
        }
    }

    func waitUntilPaused() async {
        if isPaused { return }

        await withCheckedContinuation { continuation in
            pauseWaiters.append(continuation)
        }
    }

    func resume() {
        resumeWaiter?.resume()
        resumeWaiter = nil
    }
}

private struct UnexpectedCallError: Error {}

private extension DDEVProject {
    static let configReloadSample = DDEVProject(
        name: "aqua-pura",
        appRoot: "/Users/dave/Development/agilepixel/aqua-pura",
        shortRoot: "~/Development/agilepixel/aqua-pura",
        status: .running,
        statusDescription: "running",
        projectType: .wordpress,
        docroot: "web",
        primaryURL: nil,
        httpURL: nil,
        httpsURL: nil,
        mailpitURL: nil,
        mailpitHTTPSURL: nil,
        xhguiURL: nil,
        xhguiHTTPSURL: nil,
        mutagenEnabled: false,
        mutagenStatus: nil
    )
}
