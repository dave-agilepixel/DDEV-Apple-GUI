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
        let startedAt = Date()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [spec.executable] + spec.arguments
        if let workingDirectory = spec.workingDirectory {
            process.currentDirectoryURL = URL(fileURLWithPath: workingDirectory)
        }

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        try process.run()
        process.waitUntilExit()

        let stdout = String(data: stdoutPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let stderr = String(data: stderrPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let result = CommandResult(
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

        if result.succeeded {
            return result
        }

        throw CommandRunnerError.nonZeroExit(result)
    }
}
