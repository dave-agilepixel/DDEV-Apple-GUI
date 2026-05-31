import Foundation

public struct CommandSpec: Equatable, Sendable {
    public let executable: String
    public let arguments: [String]
    public let workingDirectory: String?
    /// Optional wall-clock cap. When set, a wedged child is terminated after this duration so
    /// it can never pin a dispatch-queue thread indefinitely (audit H2). `nil` means no cap —
    /// the child only ends on its own or on task cancellation.
    public let timeout: Duration?

    public init(
        executable: String,
        arguments: [String],
        workingDirectory: String? = nil,
        timeout: Duration? = nil
    ) {
        self.executable = executable
        self.arguments = arguments
        self.workingDirectory = workingDirectory
        self.timeout = timeout
    }
}

public protocol CommandRunning: Sendable {
    func run(_ spec: CommandSpec) async throws -> CommandResult
}

public enum CommandRunnerError: Error, Equatable {
    case nonZeroExit(CommandResult)
    /// The child exceeded its `CommandSpec.timeout` and was terminated. The carried result is
    /// flagged `wasCancelled`.
    case timedOut(CommandResult)
}

public final class ProcessCommandRunner: CommandRunning, @unchecked Sendable {
    public init() {}

    public func run(_ spec: CommandSpec) async throws -> CommandResult {
        let controller = ProcessController()
        let result: CommandResult = try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<CommandResult, Error>) in
                DispatchQueue.global(qos: .userInitiated).async {
                    do {
                        continuation.resume(returning: try Self.executeBlocking(spec, controller: controller))
                    } catch {
                        continuation.resume(throwing: error)
                    }
                }
            }
        } onCancel: {
            controller.terminate()
        }

        // The process was terminated by us — distinguish task cancellation from a timeout so
        // callers can react differently (cancellation is silent; a timeout is a real failure).
        if result.wasCancelled {
            if Task.isCancelled { throw CancellationError() }
            throw CommandRunnerError.timedOut(result)
        }
        if result.succeeded { return result }
        throw CommandRunnerError.nonZeroExit(result)
    }

    // Blocking implementation, intended to run on a background dispatch queue.
    // Drains stdout and stderr concurrently while the child runs so we don't deadlock
    // on output larger than the pipe kernel buffer (16-64 KiB).
    private static func executeBlocking(_ spec: CommandSpec, controller: ProcessController) throws -> CommandResult {
        let startedAt = Date()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [spec.executable] + spec.arguments
        process.environment = environmentForGUIApp()
        if let workingDirectory = spec.workingDirectory {
            process.currentDirectoryURL = URL(fileURLWithPath: workingDirectory)
        }

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        // If the owning task was cancelled before we even started, don't launch at all.
        guard controller.attach(process) else {
            return CommandResult(
                executable: spec.executable,
                arguments: spec.arguments,
                workingDirectory: spec.workingDirectory,
                exitCode: -1,
                stdout: "",
                stderr: "",
                startedAt: startedAt,
                finishedAt: Date(),
                wasCancelled: true
            )
        }

        let stdoutBuffer = PipeBuffer()
        let stderrBuffer = PipeBuffer()
        let group = DispatchGroup()
        let readQueue = DispatchQueue(label: "ddevui.process-reader", attributes: .concurrent)

        group.enter()
        readQueue.async {
            stdoutBuffer.append(stdoutPipe.fileHandleForReading.readDataToEndOfFile())
            group.leave()
        }

        group.enter()
        readQueue.async {
            stderrBuffer.append(stderrPipe.fileHandleForReading.readDataToEndOfFile())
            group.leave()
        }

        try process.run()
        // Cover the narrow window where cancellation/timeout fired between attach and run().
        if controller.didRequestTermination { process.terminate() }

        // Watchdog: terminate the child if it outlives its timeout.
        var watchdog: DispatchWorkItem?
        if let timeout = spec.timeout {
            let item = DispatchWorkItem { controller.terminate() }
            DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + timeout.timeInterval, execute: item)
            watchdog = item
        }

        process.waitUntilExit()
        watchdog?.cancel()
        group.wait()

        let stdout = String(data: stdoutBuffer.snapshot, encoding: .utf8) ?? ""
        let stderr = String(data: stderrBuffer.snapshot, encoding: .utf8) ?? ""
        return CommandResult(
            executable: spec.executable,
            arguments: spec.arguments,
            workingDirectory: spec.workingDirectory,
            exitCode: process.terminationStatus,
            stdout: stdout,
            stderr: stderr,
            startedAt: startedAt,
            finishedAt: Date(),
            wasCancelled: controller.didRequestTermination
        )
    }

    // Lock-guarded accumulator so the per-pipe drain on a background dispatch queue can
    // safely append without tripping Swift 6 Sendable checks on the @Sendable GCD closure.
    private final class PipeBuffer: @unchecked Sendable {
        private let lock = NSLock()
        private var data = Data()

        func append(_ chunk: Data) {
            lock.withLock { data.append(chunk) }
        }

        var snapshot: Data {
            lock.withLock { data }
        }
    }

    /// Thread-safe handle to the running child, shared between the blocking worker and the
    /// task-cancellation / timeout paths. Termination is latched so a cancel that arrives
    /// before the process launches still prevents (or stops) it.
    private final class ProcessController: @unchecked Sendable {
        private let lock = NSLock()
        private var process: Process?
        private var terminationRequested = false

        /// Stores the process for later termination. Returns `false` if termination was already
        /// requested (the task was cancelled before the process started) — the caller must not launch.
        func attach(_ process: Process) -> Bool {
            lock.lock(); defer { lock.unlock() }
            if terminationRequested { return false }
            self.process = process
            return true
        }

        /// Requests termination: SIGTERM now, escalating to SIGKILL after a short grace period.
        /// Safe to call before launch — the request is latched for `attach` to honour.
        func terminate() {
            let target: Process?
            lock.lock()
            terminationRequested = true
            target = process
            lock.unlock()

            guard let target, target.isRunning else { return }
            let pid = target.processIdentifier
            target.terminate()
            DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 2) { [weak target] in
                if let target, target.isRunning { kill(pid, SIGKILL) }
            }
        }

        var didRequestTermination: Bool {
            lock.lock(); defer { lock.unlock() }
            return terminationRequested
        }
    }

    private static func environmentForGUIApp() -> [String: String] {
        var environment = ProcessInfo.processInfo.environment
        let existingPath = environment["PATH", default: ""]
        let standardPath = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        environment["PATH"] = existingPath.isEmpty ? standardPath : "\(standardPath):\(existingPath)"
        return environment
    }
}

private extension Duration {
    /// The duration expressed as seconds for `DispatchTime` arithmetic.
    var timeInterval: TimeInterval {
        let (seconds, attoseconds) = components
        return Double(seconds) + Double(attoseconds) / 1e18
    }
}
