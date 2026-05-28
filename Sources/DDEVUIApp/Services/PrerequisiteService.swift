import AppKit
import Foundation

public protocol PrerequisiteChecking: Sendable {
    func check() async -> PrerequisiteState
    func launch(_ runtime: DockerRuntime) async
}

public final class WorkspacePrerequisiteService: PrerequisiteChecking, @unchecked Sendable {
    private let commandRunner: CommandRunning
    private let ddevResolver: DDEVExecutableResolver
    private let installedRuntimeLookup: @Sendable (DockerRuntime) -> Bool
    private let runningRuntimeLookup: @Sendable (DockerRuntime) -> Bool

    public init(
        commandRunner: CommandRunning = ProcessCommandRunner(),
        ddevResolver: DDEVExecutableResolver = DDEVExecutableResolver(),
        installedRuntimeLookup: @escaping @Sendable (DockerRuntime) -> Bool = { runtime in
            NSWorkspace.shared.urlForApplication(withBundleIdentifier: runtime.bundleIdentifier) != nil
        },
        runningRuntimeLookup: @escaping @Sendable (DockerRuntime) -> Bool = { runtime in
            !NSRunningApplication.runningApplications(withBundleIdentifier: runtime.bundleIdentifier).isEmpty
        }
    ) {
        self.commandRunner = commandRunner
        self.ddevResolver = ddevResolver
        self.installedRuntimeLookup = installedRuntimeLookup
        self.runningRuntimeLookup = runningRuntimeLookup
    }

    public func check() async -> PrerequisiteState {
        async let docker = checkDocker()
        async let ddev = checkDDEV()
        return PrerequisiteState(docker: await docker, ddev: await ddev)
    }

    public func launch(_ runtime: DockerRuntime) async {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: runtime.bundleIdentifier) else { return }
        let config = NSWorkspace.OpenConfiguration()
        config.activates = false
        do {
            _ = try await NSWorkspace.shared.openApplication(at: url, configuration: config)
        } catch {
            // Subsequent polls will reflect whether the launch succeeded.
        }
    }

    private func checkDocker() async -> DockerStatus {
        if await dockerDaemonReady() {
            return .ok
        }

        for runtime in DockerRuntime.allCases where installedRuntimeLookup(runtime) {
            return runningRuntimeLookup(runtime) ? .starting(runtime) : .notRunning(runtime)
        }
        return .missing
    }

    private func dockerDaemonReady() async -> Bool {
        do {
            _ = try await commandRunner.run(
                CommandSpec(executable: "docker", arguments: ["info", "--format", "{{.ServerVersion}}"])
            )
            return true
        } catch {
            return false
        }
    }

    private func checkDDEV() async -> DDEVStatus {
        let path = ddevResolver.resolve()
        do {
            let result = try await commandRunner.run(
                CommandSpec(executable: path, arguments: ["version", "--json-output"])
            )
            return .ok(version: Self.parseDDEVVersion(from: result.stdout))
        } catch {
            return .missing
        }
    }

    static func parseDDEVVersion(from stdout: String) -> String? {
        guard let data = stdout.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }

        if let raw = root["raw"] as? [String: Any], let version = raw["DDEV version"] as? String {
            return version
        }
        if let version = root["DDEV version"] as? String {
            return version
        }
        return nil
    }
}

public final class StaticPrerequisiteService: PrerequisiteChecking, @unchecked Sendable {
    private let states: [PrerequisiteState]
    private let launchHandler: (@Sendable (DockerRuntime) -> Void)?
    private let lock = NSLock()
    private var callCount = 0

    public init(
        states: [PrerequisiteState],
        onLaunch: (@Sendable (DockerRuntime) -> Void)? = nil
    ) {
        precondition(!states.isEmpty, "StaticPrerequisiteService requires at least one state")
        self.states = states
        self.launchHandler = onLaunch
    }

    public convenience init(
        state: PrerequisiteState,
        onLaunch: (@Sendable (DockerRuntime) -> Void)? = nil
    ) {
        self.init(states: [state], onLaunch: onLaunch)
    }

    public func check() async -> PrerequisiteState {
        lock.withLock {
            let state = states[min(callCount, states.count - 1)]
            callCount += 1
            return state
        }
    }

    public func launch(_ runtime: DockerRuntime) async {
        launchHandler?(runtime)
    }
}
