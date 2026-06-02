import AppKit
import Foundation

public protocol PrerequisiteChecking: Sendable {
    func check() async -> PrerequisiteState
    func launch(_ runtime: DockerRuntime) async throws
    /// Runs `ddev utility dockercheck` and returns its (ANSI-stripped) diagnostic report (B7).
    func dockerCheck() async -> DockerCheckReport
}

public extension PrerequisiteChecking {
    // Default for conformers that don't support the troubleshoot path (test doubles, previews).
    func dockerCheck() async -> DockerCheckReport {
        DockerCheckReport(output: "", succeeded: false)
    }
}

public final class WorkspacePrerequisiteService: PrerequisiteChecking, @unchecked Sendable {
    private let commandRunner: CommandRunning
    private let ddevResolver: DDEVExecutableResolver
    private let dockerResolver: DockerExecutableResolver
    private let installedRuntimeLookup: @Sendable (DockerRuntime) -> Bool
    private let runningRuntimeLookup: @Sendable (DockerRuntime) -> Bool

    public init(
        commandRunner: CommandRunning = ProcessCommandRunner(),
        ddevResolver: DDEVExecutableResolver = DDEVExecutableResolver(),
        dockerResolver: DockerExecutableResolver = DockerExecutableResolver(),
        installedRuntimeLookup: @escaping @Sendable (DockerRuntime) -> Bool = { runtime in
            NSWorkspace.shared.urlForApplication(withBundleIdentifier: runtime.bundleIdentifier) != nil
        },
        runningRuntimeLookup: @escaping @Sendable (DockerRuntime) -> Bool = { runtime in
            !NSRunningApplication.runningApplications(withBundleIdentifier: runtime.bundleIdentifier).isEmpty
        }
    ) {
        self.commandRunner = commandRunner
        self.ddevResolver = ddevResolver
        self.dockerResolver = dockerResolver
        self.installedRuntimeLookup = installedRuntimeLookup
        self.runningRuntimeLookup = runningRuntimeLookup
    }

    public func check() async -> PrerequisiteState {
        async let docker = checkDocker()
        async let ddev = checkDDEV()
        return PrerequisiteState(docker: await docker, ddev: await ddev)
    }

    public func launch(_ runtime: DockerRuntime) async throws {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: runtime.bundleIdentifier) else { return }
        let config = NSWorkspace.OpenConfiguration()
        config.activates = false
        // Propagate launch failures (app damaged, Gatekeeper block) instead of swallowing them,
        // so the prerequisite sheet can tell the user why Docker never started (audit L5).
        _ = try await NSWorkspace.shared.openApplication(at: url, configuration: config)
    }

    public func dockerCheck() async -> DockerCheckReport {
        let spec = CommandSpec(
            executable: ddevResolver.resolve(),
            arguments: ["utility", "dockercheck"],
            timeout: .seconds(60)
        )
        do {
            return Self.report(from: try await commandRunner.run(spec))
        } catch let CommandRunnerError.nonZeroExit(result) {
            return Self.report(from: result)
        } catch let CommandRunnerError.timedOut(result) {
            return Self.report(from: result)
        } catch {
            return DockerCheckReport(
                output: "Couldn't run `ddev utility dockercheck`: \(error.presentableMessage)",
                succeeded: false
            )
        }
    }

    private static func report(from result: CommandResult) -> DockerCheckReport {
        let combined = [result.stdout, result.stderr]
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
        return DockerCheckReport(output: stripANSI(combined), succeeded: result.succeeded)
    }

    /// Strips ANSI CSI escape sequences (e.g. colour codes) so the diagnostic renders as plain
    /// text — `dockercheck` colourises its output even over a pipe.
    static func stripANSI(_ string: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: "\u{1B}\\[[0-9;]*[A-Za-z]") else { return string }
        let range = NSRange(string.startIndex..., in: string)
        return regex.stringByReplacingMatches(in: string, range: range, withTemplate: "")
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
                CommandSpec(
                    executable: dockerResolver.resolve(),
                    arguments: ["info", "--format", "{{.ServerVersion}}"],
                    timeout: .seconds(15)
                )
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
                CommandSpec(executable: path, arguments: ["version", "--json-output"], timeout: .seconds(15))
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
    private let stubbedDockerCheckReport: DockerCheckReport?
    private let lock = NSLock()
    private var callCount = 0

    public init(
        states: [PrerequisiteState],
        onLaunch: (@Sendable (DockerRuntime) -> Void)? = nil,
        dockerCheckReport: DockerCheckReport? = nil
    ) {
        precondition(!states.isEmpty, "StaticPrerequisiteService requires at least one state")
        self.states = states
        self.launchHandler = onLaunch
        self.stubbedDockerCheckReport = dockerCheckReport
    }

    public convenience init(
        state: PrerequisiteState,
        onLaunch: (@Sendable (DockerRuntime) -> Void)? = nil,
        dockerCheckReport: DockerCheckReport? = nil
    ) {
        self.init(states: [state], onLaunch: onLaunch, dockerCheckReport: dockerCheckReport)
    }

    public func dockerCheck() async -> DockerCheckReport {
        stubbedDockerCheckReport ?? DockerCheckReport(output: "", succeeded: false)
    }

    public func check() async -> PrerequisiteState {
        lock.withLock {
            let state = states[min(callCount, states.count - 1)]
            callCount += 1
            return state
        }
    }

    public func launch(_ runtime: DockerRuntime) async throws {
        launchHandler?(runtime)
    }
}
