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
