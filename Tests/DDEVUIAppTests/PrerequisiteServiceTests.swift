import XCTest
@testable import DDEVUIApp

final class PrerequisiteServiceTests: XCTestCase {
    func testStateInitialIsCheckingAndNotSatisfied() {
        let state = PrerequisiteState.initial
        XCTAssertTrue(state.isStillChecking)
        XCTAssertFalse(state.allSatisfied)
    }

    func testAllSatisfiedRequiresBothOk() {
        XCTAssertTrue(PrerequisiteState(docker: .ok, ddev: .ok(version: "v1.24.0")).allSatisfied)
        XCTAssertFalse(PrerequisiteState(docker: .ok, ddev: .missing).allSatisfied)
        XCTAssertFalse(PrerequisiteState(docker: .starting(.dockerDesktop), ddev: .ok(version: nil)).allSatisfied)
        XCTAssertFalse(PrerequisiteState(docker: .notRunning(.dockerDesktop), ddev: .ok(version: nil)).allSatisfied)
        XCTAssertFalse(PrerequisiteState(docker: .missing, ddev: .ok(version: nil)).allSatisfied)
    }

    func testIsStillCheckingOnEitherSide() {
        XCTAssertTrue(PrerequisiteState(docker: .checking, ddev: .ok(version: nil)).isStillChecking)
        XCTAssertTrue(PrerequisiteState(docker: .ok, ddev: .checking).isStillChecking)
        XCTAssertFalse(PrerequisiteState(docker: .ok, ddev: .ok(version: nil)).isStillChecking)
    }

    func testDockerBundleIdentifiers() {
        XCTAssertEqual(DockerRuntime.dockerDesktop.bundleIdentifier, "com.docker.docker")
        XCTAssertEqual(DockerRuntime.orbstack.bundleIdentifier, "dev.kdrag0n.OrbStack")
    }

    func testParseDDEVVersionFromRawRoot() {
        let json = #"{"raw":{"DDEV version":"v1.24.0","architecture":"arm64"},"DDEV version":"v1.24.0"}"#
        XCTAssertEqual(WorkspacePrerequisiteService.parseDDEVVersion(from: json), "v1.24.0")
    }

    func testParseDDEVVersionFromTopLevel() {
        let json = #"{"DDEV version":"v1.23.5"}"#
        XCTAssertEqual(WorkspacePrerequisiteService.parseDDEVVersion(from: json), "v1.23.5")
    }

    func testParseDDEVVersionReturnsNilOnUnexpectedShape() {
        XCTAssertNil(WorkspacePrerequisiteService.parseDDEVVersion(from: "not json"))
        XCTAssertNil(WorkspacePrerequisiteService.parseDDEVVersion(from: #"{"other":"value"}"#))
    }

    func testWorkspaceServiceReportsDockerOkWhenDaemonResponds() async {
        let runner = StubCommandRunner(behaviors: [
            "docker info": .success("28.0.1"),
            "ddev version": .success(#"{"DDEV version":"v1.24.0"}"#)
        ])
        let service = WorkspacePrerequisiteService(
            commandRunner: runner,
            ddevResolver: DDEVExecutableResolver(environment: [:], fileExists: { _ in false }),
            installedRuntimeLookup: { _ in false },
            runningRuntimeLookup: { _ in false }
        )

        let state = await service.check()
        XCTAssertEqual(state.docker, .ok)
        XCTAssertEqual(state.ddev, .ok(version: "v1.24.0"))
    }

    func testWorkspaceServiceReportsStartingWhenDaemonDownButAppRunning() async {
        let runner = StubCommandRunner(behaviors: [
            "docker info": .failure,
            "ddev version": .success(#"{"DDEV version":"v1.24.0"}"#)
        ])
        let service = WorkspacePrerequisiteService(
            commandRunner: runner,
            installedRuntimeLookup: { $0 == .dockerDesktop },
            runningRuntimeLookup: { $0 == .dockerDesktop }
        )

        let state = await service.check()
        XCTAssertEqual(state.docker, .starting(.dockerDesktop))
    }

    func testWorkspaceServiceReportsNotRunningWhenInstalledButProcessAbsent() async {
        let runner = StubCommandRunner(behaviors: [
            "docker info": .failure,
            "ddev version": .failure
        ])
        let service = WorkspacePrerequisiteService(
            commandRunner: runner,
            installedRuntimeLookup: { $0 == .dockerDesktop },
            runningRuntimeLookup: { _ in false }
        )

        let state = await service.check()
        XCTAssertEqual(state.docker, .notRunning(.dockerDesktop))
        XCTAssertEqual(state.ddev, .missing)
    }

    func testWorkspaceServicePrefersOrbStackWhenDockerDesktopAbsent() async {
        let runner = StubCommandRunner(behaviors: [
            "docker info": .failure,
            "ddev version": .failure
        ])
        let service = WorkspacePrerequisiteService(
            commandRunner: runner,
            installedRuntimeLookup: { $0 == .orbstack },
            runningRuntimeLookup: { _ in false }
        )

        let state = await service.check()
        XCTAssertEqual(state.docker, .notRunning(.orbstack))
    }

    func testWorkspaceServiceReportsMissingWhenNothingInstalled() async {
        let runner = StubCommandRunner(behaviors: [
            "docker info": .failure,
            "ddev version": .failure
        ])
        let service = WorkspacePrerequisiteService(
            commandRunner: runner,
            installedRuntimeLookup: { _ in false },
            runningRuntimeLookup: { _ in false }
        )

        let state = await service.check()
        XCTAssertEqual(state.docker, .missing)
        XCTAssertEqual(state.ddev, .missing)
    }

    @MainActor
    func testMonitorBlocksUIOnlyAfterFirstCheckCompletes() async {
        let service = StaticPrerequisiteService(state: PrerequisiteState(docker: .missing, ddev: .missing))
        let monitor = PrerequisiteMonitor(service: service, pollInterval: .seconds(60))

        XCTAssertFalse(monitor.shouldBlockUI)

        await monitor.refresh()
        XCTAssertTrue(monitor.shouldBlockUI)
    }

    @MainActor
    func testMonitorClearsBlockOnceAllSatisfied() async {
        let service = StaticPrerequisiteService(states: [
            PrerequisiteState(docker: .notRunning(.dockerDesktop), ddev: .ok(version: "v1.24.0")),
            PrerequisiteState(docker: .ok, ddev: .ok(version: "v1.24.0"))
        ])
        let monitor = PrerequisiteMonitor(service: service, pollInterval: .seconds(60))

        await monitor.refresh()
        XCTAssertTrue(monitor.shouldBlockUI)

        await monitor.refresh()
        XCTAssertFalse(monitor.shouldBlockUI)
    }

    @MainActor
    func testMonitorInvokesLaunchHandler() async {
        let launchedRuntimes = LaunchRecorder()
        let service = StaticPrerequisiteService(
            state: PrerequisiteState(docker: .notRunning(.dockerDesktop), ddev: .ok(version: nil)),
            onLaunch: { runtime in launchedRuntimes.record(runtime) }
        )
        let monitor = PrerequisiteMonitor(service: service, pollInterval: .seconds(60))

        await monitor.launch(.dockerDesktop)

        XCTAssertEqual(launchedRuntimes.snapshot, [.dockerDesktop])
        XCTAssertFalse(monitor.isLaunching)
    }

    @MainActor
    func testPollLoopStopsOncePrerequisitesSatisfied() async throws {
        let service = CountingPrerequisiteService(state: PrerequisiteState(docker: .ok, ddev: .ok(version: "v1.24.0")))
        let monitor = PrerequisiteMonitor(service: service, pollInterval: .milliseconds(10))

        monitor.start()
        // Far more than one poll interval — a non-terminating loop would rack up ~20 checks.
        try await Task.sleep(for: .milliseconds(200))

        XCTAssertEqual(service.callCount, 1, "Loop must stop after the first satisfied check, not poll forever")
        XCTAssertTrue(monitor.state.allSatisfied)
    }

    @MainActor
    func testPollLoopKeepsPollingWhileUnsatisfiedAndStopsOnStop() async throws {
        let service = CountingPrerequisiteService(state: PrerequisiteState(docker: .notRunning(.dockerDesktop), ddev: .missing))
        let monitor = PrerequisiteMonitor(service: service, pollInterval: .milliseconds(10))

        monitor.start()
        try await Task.sleep(for: .milliseconds(120))
        XCTAssertGreaterThan(service.callCount, 1, "Loop keeps polling while prerequisites are unmet")

        monitor.stop()
        // Let any in-flight check settle, then confirm the count is frozen — i.e. polling halted.
        try await Task.sleep(for: .milliseconds(60))
        let afterStop = service.callCount
        try await Task.sleep(for: .milliseconds(80))
        XCTAssertEqual(service.callCount, afterStop, "stop() halts further polling")
    }

    @MainActor
    func testStartReArmsAfterSelfTerminating() async throws {
        let service = CountingPrerequisiteService(state: PrerequisiteState(docker: .ok, ddev: .ok(version: "v1.24.0")))
        let monitor = PrerequisiteMonitor(service: service, pollInterval: .milliseconds(10))

        monitor.start()
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(service.callCount, 1)

        // The self-terminated loop cleared pollTask, so start() can re-validate on demand.
        monitor.start()
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(service.callCount, 2, "start() re-arms after the loop self-terminated")
    }

    @MainActor
    func testLaunchSurfacesErrorWhenServiceLaunchFails() async {
        let service = ThrowingLaunchPrerequisiteService()
        let monitor = PrerequisiteMonitor(service: service, pollInterval: .seconds(60))

        await monitor.launch(.dockerDesktop)

        XCTAssertNotNil(monitor.launchErrorMessage, "A launch failure is surfaced, not silently swallowed")
        XCTAssertTrue(monitor.launchErrorMessage?.contains("Docker Desktop") ?? false)
        XCTAssertFalse(monitor.isLaunching)
    }
}

private final class StubCommandRunner: CommandRunning, @unchecked Sendable {
    enum Behavior {
        case success(String)
        case failure
    }

    private let behaviors: [String: Behavior]

    init(behaviors: [String: Behavior]) {
        self.behaviors = behaviors
    }

    func run(_ spec: CommandSpec) async throws -> CommandResult {
        let executableTail = (spec.executable as NSString).lastPathComponent
        let firstArg = spec.arguments.first ?? ""
        let key = "\(executableTail) \(firstArg)"

        let behavior = behaviors[key] ?? .failure
        let result = CommandResult(
            executable: spec.executable,
            arguments: spec.arguments,
            workingDirectory: spec.workingDirectory,
            exitCode: { if case .success = behavior { return 0 } else { return 1 } }(),
            stdout: { if case .success(let value) = behavior { return value } else { return "" } }(),
            stderr: "",
            startedAt: Date(),
            finishedAt: Date(),
            wasCancelled: false
        )

        if result.succeeded {
            return result
        }
        throw CommandRunnerError.nonZeroExit(result)
    }
}

/// A fake that records how many times `check()` runs so tests can assert the poll loop's
/// start/stop/self-terminate lifecycle (audit H1).
private final class CountingPrerequisiteService: PrerequisiteChecking, @unchecked Sendable {
    private let state: PrerequisiteState
    private let lock = NSLock()
    private var count = 0

    init(state: PrerequisiteState) { self.state = state }

    var callCount: Int { lock.withLock { count } }

    func check() async -> PrerequisiteState {
        lock.withLock { count += 1 }
        return state
    }

    func launch(_ runtime: DockerRuntime) async throws {}
}

/// A fake whose `launch` always fails, to verify the monitor surfaces the error (audit L5).
private final class ThrowingLaunchPrerequisiteService: PrerequisiteChecking, @unchecked Sendable {
    struct LaunchFailure: Error {}
    func check() async -> PrerequisiteState {
        PrerequisiteState(docker: .notRunning(.dockerDesktop), ddev: .ok(version: nil))
    }
    func launch(_ runtime: DockerRuntime) async throws { throw LaunchFailure() }
}

private final class LaunchRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var runtimes: [DockerRuntime] = []

    func record(_ runtime: DockerRuntime) {
        lock.withLock { runtimes.append(runtime) }
    }

    var snapshot: [DockerRuntime] {
        lock.withLock { runtimes }
    }
}
