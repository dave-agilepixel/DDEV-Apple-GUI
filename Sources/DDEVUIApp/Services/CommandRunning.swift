import Foundation

public struct CommandSpec: Equatable, Sendable {
    public let executable: String
    public let arguments: [String]
    public let workingDirectory: String?

    public init(executable: String, arguments: [String], workingDirectory: String? = nil) {
        self.executable = executable
        self.arguments = arguments
        self.workingDirectory = workingDirectory
    }
}

public protocol CommandRunning: Sendable {
    func run(_ spec: CommandSpec) async throws -> CommandResult
}

public enum CommandRunnerError: Error, Equatable {
    case nonZeroExit(CommandResult)
}

public final class ProcessCommandRunner: CommandRunning, @unchecked Sendable {
    public init() {}

    public func run(_ spec: CommandSpec) async throws -> CommandResult {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<CommandResult, Error>) in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let result = try Self.executeBlocking(spec)
                    if result.succeeded {
                        continuation.resume(returning: result)
                    } else {
                        continuation.resume(throwing: CommandRunnerError.nonZeroExit(result))
                    }
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    // Blocking implementation, intended to run on a background dispatch queue.
    // Drains stdout and stderr concurrently while the child runs so we don't deadlock
    // on output larger than the pipe kernel buffer (16-64 KiB).
    private static func executeBlocking(_ spec: CommandSpec) throws -> CommandResult {
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
        process.waitUntilExit()
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
            wasCancelled: false
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

    private static func environmentForGUIApp() -> [String: String] {
        var environment = ProcessInfo.processInfo.environment
        let existingPath = environment["PATH", default: ""]
        let standardPath = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        environment["PATH"] = existingPath.isEmpty ? standardPath : "\(standardPath):\(existingPath)"
        return environment
    }
}
