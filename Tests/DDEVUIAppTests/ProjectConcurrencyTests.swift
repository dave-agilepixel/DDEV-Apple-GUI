import XCTest
@testable import DDEVUIApp

@MainActor
final class ProjectConcurrencyTests: XCTestCase {
    func testTwoProjectsRunMutationsConcurrently() async {
        let service = GatedDDEVService(projects: [.sampleWordPress, .sampleLaravel])
        let viewModel = ProjectDashboardViewModel(ddevService: service)
        await viewModel.refresh()

        async let first: Void = viewModel.start(.sampleWordPress)
        async let second: Void = viewModel.start(.sampleLaravel)

        // Wait until both are reported running, then release both.
        await service.waitForInFlight(count: 2)
        XCTAssertEqual(viewModel.state(for: "aqua-pura").activity, .running)
        XCTAssertEqual(viewModel.state(for: "agilebugs").activity, .running)

        await service.releaseAll()
        _ = await (first, second)

        XCTAssertFalse(viewModel.isBusy(.sampleWordPress))
        XCTAssertFalse(viewModel.isBusy(.sampleLaravel))
    }

    func testSameProjectSecondMutationIgnoredWhileBusy() async {
        let service = GatedDDEVService(projects: [.sampleWordPress])
        let viewModel = ProjectDashboardViewModel(ddevService: service)
        await viewModel.refresh()

        async let first: Void = viewModel.start(.sampleWordPress)
        await service.waitForInFlight(count: 1)

        await viewModel.start(.sampleWordPress) // should be ignored (already running)

        await service.releaseAll()
        _ = await first

        let starts = await service.commands().filter { $0 == "start:aqua-pura" }
        XCTAssertEqual(starts.count, 1, "Second start while busy is ignored")
    }

    func testCapQueuesExcessMutations() async {
        let service = GatedDDEVService(projects: [.sampleWordPress, .sampleLaravel, .sampleDrupal])
        let viewModel = ProjectDashboardViewModel(
            ddevService: service,
            scheduler: CommandScheduler(maxConcurrent: 2)
        )
        await viewModel.refresh()

        async let a: Void = viewModel.start(.sampleWordPress)
        async let b: Void = viewModel.start(.sampleLaravel)
        async let c: Void = viewModel.start(.sampleDrupal)

        await service.waitForInFlight(count: 2)
        // Exactly two mutations run under the cap of 2; the third waits in the scheduler.
        // `async let` does not fix the order in which the three reach `scheduler.acquire()`,
        // so assert on the *counts* of activities, not which specific project is queued.
        // Yield until the third has registered as queued so the snapshot is stable.
        let ids = ["aqua-pura", "agilebugs", "drupal-demo"]
        for _ in 0..<1000 where ids.filter({ viewModel.state(for: $0).activity == .queued }).count < 1 {
            await Task.yield()
        }
        let activities = ids.map { viewModel.state(for: $0).activity }
        XCTAssertEqual(activities.filter { $0 == .running }.count, 2,
                       "Only maxConcurrent (2) mutations run at once")
        XCTAssertEqual(activities.filter { $0 == .queued }.count, 1,
                       "The excess mutation waits behind the cap of 2")

        await service.releaseAll()
        _ = await (a, b, c)
        let startCount = await service.commands().filter { $0.hasPrefix("start:") }.count
        XCTAssertEqual(startCount, 3)
    }

    func testBackgroundProjectMutationNotifies() async {
        let service = GatedDDEVService(projects: [.sampleWordPress, .sampleLaravel])
        let spy = SpyNotificationScheduler()
        let viewModel = ProjectDashboardViewModel(ddevService: service, notifier: spy)
        await viewModel.refresh()
        viewModel.selectedProject = .sampleWordPress // aqua-pura is focused

        let task = Task { await viewModel.stop(.sampleLaravel) } // background project
        await service.waitForInFlight(count: 1)
        await service.releaseAll()
        await task.value

        let calls = spy.snapshot()
        XCTAssertEqual(calls.map(\.projectName), ["agilebugs"])
        XCTAssertEqual(calls.first?.succeeded, true)
    }

    func testBackgroundProjectMutationFailureNotifies() async {
        let service = GatedDDEVService(
            projects: [.sampleWordPress, .sampleLaravel],
            failingLabels: ["stop:agilebugs"]
        )
        let spy = SpyNotificationScheduler()
        let viewModel = ProjectDashboardViewModel(ddevService: service, notifier: spy)
        await viewModel.refresh()
        viewModel.selectedProject = .sampleWordPress // aqua-pura is focused

        let task = Task { await viewModel.stop(.sampleLaravel) } // background project, will fail
        await service.waitForInFlight(count: 1)
        await service.releaseAll()
        await task.value

        let calls = spy.snapshot()
        XCTAssertEqual(calls.map(\.projectName), ["agilebugs"])
        XCTAssertEqual(calls.first?.succeeded, false, "Background failures notify too")
    }

    func testSelectedProjectMutationDoesNotNotify() async {
        let service = GatedDDEVService(projects: [.sampleWordPress])
        let spy = SpyNotificationScheduler()
        let viewModel = ProjectDashboardViewModel(ddevService: service, notifier: spy)
        await viewModel.refresh()
        viewModel.selectedProject = .sampleWordPress

        let task = Task { await viewModel.start(.sampleWordPress) }
        await service.waitForInFlight(count: 1)
        await service.releaseAll()
        await task.value

        XCTAssertTrue(spy.snapshot().isEmpty, "No notification for the focused project")
    }

    func testOverlappingRefreshIsDroppedByInFlightGuard() async {
        let service = GatedDDEVService(projects: [.sampleWordPress], gateList: true)
        let viewModel = ProjectDashboardViewModel(ddevService: service)

        async let first: Void = viewModel.refresh()
        await service.waitForInFlight(count: 1)           // first refresh parked inside listProjects
        async let second: Void = viewModel.refresh()      // should hit the in-flight guard and bail

        // While the first is still parked, let the second reach its guard decision.
        for _ in 0..<1000 { await Task.yield() }
        let listsWhileParked = await service.commands().filter { $0 == "list" }.count

        await service.releaseAll()
        _ = await (first, second)

        XCTAssertEqual(listsWhileParked, 1, "A second refresh while one is in flight is dropped, not stacked")
    }

    func testStateChangingMutationReDescribesOnlyThatProject() async {
        let service = GatedDDEVService(projects: [.sampleWordPress, .sampleLaravel])
        let viewModel = ProjectDashboardViewModel(ddevService: service)
        await viewModel.refresh()
        await service.resetCommands()

        let task = Task { await viewModel.stop(.sampleLaravel) }
        await service.waitForInFlight(count: 1)
        await service.releaseAll()
        await task.value

        let commands = await service.commands()
        XCTAssertEqual(commands, ["stop:agilebugs", "describe:agilebugs"],
                       "No global 'list'; only the affected project is re-described")
    }
}

// MARK: - Test doubles

private struct SpyCall: Equatable, Sendable { let projectName: String; let succeeded: Bool }

/// Records (projectName, succeeded) calls. Thread-safe via a lock so it can be observed
/// from the test (MainActor) after the awaited notifier calls complete.
private final class SpyNotificationScheduler: NotificationScheduling, @unchecked Sendable {
    private let lock = NSLock()
    private var calls: [SpyCall] = []

    func requestAuthorizationIfNeeded() async {}
    func notifyCommandFinished(projectName: String, summary: String, succeeded: Bool) async {
        lock.withLock { calls.append(SpyCall(projectName: projectName, succeeded: succeeded)) }
    }

    func snapshot() -> [SpyCall] {
        lock.withLock { calls }
    }
}

/// A DDEV service whose mutating calls block until the test releases them, so two commands
/// can be observed in flight simultaneously. Reads (list/describe) return immediately.
private actor GatedDDEVService: DDEVServicing {
    private let projects: [DDEVProject]
    /// Mutation labels that should fail with a non-zero exit (e.g. "stop:agilebugs").
    private let failingLabels: Set<String>
    /// When true, `listProjects` is gated like a mutation so overlapping refreshes can be observed.
    private let gateList: Bool
    private var recorded: [String] = []
    private var inFlight = 0
    private var gate: [CheckedContinuation<Void, Never>] = []
    /// Once opened, the gate stays open: any mutation that enters `runGated` afterward passes
    /// through immediately. This is required for the cap test, where a queued mutation only
    /// reaches `runGated` *after* `releaseAll()` has drained the initially in-flight ones.
    private var isOpen = false

    init(projects: [DDEVProject], failingLabels: Set<String> = [], gateList: Bool = false) {
        self.projects = projects
        self.failingLabels = failingLabels
        self.gateList = gateList
    }

    /// Snapshot of recorded commands. Async (not a blocking `nonisolated` accessor) to avoid
    /// deadlocking the MainActor test thread under Swift 6 strict concurrency.
    func commands() -> [String] { recorded }
    func resetCommands() { recorded = [] }

    func waitForInFlight(count: Int) async {
        while inFlight < count { await Task.yield() }
    }

    func releaseAll() {
        isOpen = true
        let waiters = gate; gate = []
        waiters.forEach { $0.resume() }
    }

    private func runGated(_ label: String) async throws -> CommandResult {
        recorded.append(label)
        if !isOpen {
            inFlight += 1
            await withCheckedContinuation { gate.append($0) }
            inFlight -= 1
        }
        let failed = failingLabels.contains(label)
        let result = CommandResult(executable: "ddev", arguments: label.split(separator: ":").map(String.init),
                                   workingDirectory: nil, exitCode: failed ? 1 : 0,
                                   stdout: "", stderr: failed ? "boom" : "",
                                   startedAt: .distantPast, finishedAt: .distantPast, wasCancelled: false)
        if failed { throw CommandRunnerError.nonZeroExit(result) }
        return result
    }

    private func runImmediate() -> CommandResult {
        CommandResult(executable: "ddev", arguments: [], workingDirectory: nil, exitCode: 0,
                      stdout: "", stderr: "", startedAt: .distantPast, finishedAt: .distantPast, wasCancelled: false)
    }

    func listProjects() async throws -> [DDEVProject] {
        recorded.append("list")
        if gateList, !isOpen {
            inFlight += 1
            await withCheckedContinuation { gate.append($0) }
            inFlight -= 1
        }
        return projects
    }
    func describe(projectName: String) async throws -> DDEVProjectDetails {
        recorded.append("describe:\(projectName)"); return DDEVProjectDetails(phpVersion: nil, xhguiStatus: nil)
    }
    func start(projectName: String) async throws -> CommandResult { try await runGated("start:\(projectName)") }
    func stop(projectName: String) async throws -> CommandResult { try await runGated("stop:\(projectName)") }
    func restart(projectName: String) async throws -> CommandResult { try await runGated("restart:\(projectName)") }

    // Remaining DDEVServicing methods are unused by these tests; gated unless they are reads.
    func unlink(projectName: String) async throws -> CommandResult { try await runGated("unlink:\(projectName)") }
    func deleteDDEVData(projectName: String) async throws -> CommandResult { try await runGated("delete:\(projectName)") }
    func startProject(in appRoot: String) async throws -> CommandResult { try await runGated("start-folder") }
    func configureProject(in appRoot: String, name: String, type: DDEVProjectType, docroot: String) async throws -> CommandResult { try await runGated("config") }
    func setPHPVersion(_ version: String, in appRoot: String) async throws -> CommandResult { try await runGated("php") }
    func launchDatabaseTool(_ tool: DDEVDatabaseTool, in appRoot: String) async throws -> CommandResult { try await runGated("db") }
    func importDatabase(_ options: DDEVDatabaseImportOptions, in appRoot: String) async throws -> CommandResult { try await runGated("import") }
    func exportDatabase(_ options: DDEVDatabaseExportOptions, in appRoot: String) async throws -> CommandResult { try await runGated("export") }
    func createSnapshot(name: String?, in appRoot: String) async throws -> CommandResult { try await runGated("snapshot") }
    func listSnapshots(in appRoot: String) async throws -> CommandResult { recorded.append("snapshot-list"); return runImmediate() }
    func restoreSnapshot(named snapshotName: String, in appRoot: String) async throws -> CommandResult { try await runGated("snapshot-restore") }
    func restoreLatestSnapshot(in appRoot: String) async throws -> CommandResult { try await runGated("snapshot-restore-latest") }
    func cleanupSnapshots(in appRoot: String) async throws -> CommandResult { try await runGated("snapshot-cleanup") }
    func cleanupSnapshot(named snapshotName: String, in appRoot: String) async throws -> CommandResult { try await runGated("snapshot-cleanup-one") }
    func logs(projectName: String, service: String, tail: Int, includeTimestamps: Bool, in appRoot: String) async throws -> CommandResult { recorded.append("logs"); return runImmediate() }
    func listInstalledAddOns(projectName: String, in appRoot: String) async throws -> CommandResult { recorded.append("addon-list"); return runImmediate() }
    func searchAddOns(query: String, in appRoot: String) async throws -> CommandResult { recorded.append("addon-search"); return runImmediate() }
    func getAddOn(_ repository: String, projectName: String, in appRoot: String) async throws -> CommandResult { try await runGated("addon-get") }
    func removeAddOn(named name: String, projectName: String, in appRoot: String) async throws -> CommandResult { try await runGated("addon-remove") }
    func applyConfigChange(_ change: DDEVConfigChange, in appRoot: String) async throws -> CommandResult { try await runGated("config-change") }
    func runProjectCommand(arguments: [String], in appRoot: String) async throws -> CommandResult { try await runGated("project-command") }
    func version() async throws -> CommandResult { recorded.append("version"); return runImmediate() }
    func utilityDiagnose(in appRoot: String?) async throws -> CommandResult { recorded.append("diagnose"); return runImmediate() }
    func utilityConfigYAML(omitKeys: [String], in appRoot: String) async throws -> CommandResult { recorded.append("configyaml"); return runImmediate() }
    func utilityCheckCustomConfig(in appRoot: String) async throws -> CommandResult { recorded.append("check-custom-config"); return runImmediate() }
    func utilityCheckDBMatch(in appRoot: String) async throws -> CommandResult { recorded.append("check-db-match"); return runImmediate() }
    func migrateDatabase(to type: DDEVDatabaseType, version: String, in appRoot: String) async throws -> CommandResult { try await runGated("migrate-database") }
    func mutagen(_ command: DDEVMutagenCommand, in appRoot: String) async throws -> CommandResult { recorded.append("mutagen"); return runImmediate() }
    func xhgui(_ command: DDEVXHGuiCommand, in appRoot: String) async throws -> CommandResult { try await runGated("xhgui") }
    func xdebug(_ command: DDEVXdebugCommand, in appRoot: String) async throws -> CommandResult { try await runGated("xdebug") }
    func updateWordPressCore(in appRoot: String) async throws -> CommandResult { try await runGated("wp-core") }
    func updateWordPressPlugins(in appRoot: String) async throws -> CommandResult { try await runGated("wp-plugins") }
    func updateWordPressThemes(in appRoot: String) async throws -> CommandResult { try await runGated("wp-themes") }
}

extension DDEVProject {
    static let sampleDrupal = DDEVProject(
        name: "drupal-demo",
        appRoot: "/Users/dave/Development/agilepixel/drupal-demo",
        shortRoot: "~/Development/agilepixel/drupal-demo",
        status: .running, statusDescription: "running",
        projectType: .drupal, docroot: "web",
        primaryURL: URL(string: "https://drupal-demo.ddev.site"),
        httpURL: nil, httpsURL: nil, mailpitURL: nil, mailpitHTTPSURL: nil,
        xhguiURL: nil, xhguiHTTPSURL: nil, xhguiStatus: nil,
        mutagenEnabled: true, mutagenStatus: "ok", phpVersion: nil
    )
}
