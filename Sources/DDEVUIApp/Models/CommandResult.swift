import Foundation

public struct CommandResult: Equatable, Sendable {
    public let executable: String
    public let arguments: [String]
    public let workingDirectory: String?
    public let exitCode: Int32
    public let stdout: String
    public let stderr: String
    public let startedAt: Date
    public let finishedAt: Date
    public let wasCancelled: Bool

    public init(
        executable: String,
        arguments: [String],
        workingDirectory: String?,
        exitCode: Int32,
        stdout: String,
        stderr: String,
        startedAt: Date,
        finishedAt: Date,
        wasCancelled: Bool
    ) {
        self.executable = executable
        self.arguments = arguments
        self.workingDirectory = workingDirectory
        self.exitCode = exitCode
        self.stdout = stdout
        self.stderr = stderr
        self.startedAt = startedAt
        self.finishedAt = finishedAt
        self.wasCancelled = wasCancelled
    }

    public var succeeded: Bool {
        exitCode == 0 && !wasCancelled
    }

    public static func success(stdout: String = "", stderr: String = "") -> CommandResult {
        let now = Date()
        return CommandResult(
            executable: "ddev",
            arguments: [],
            workingDirectory: nil,
            exitCode: 0,
            stdout: stdout,
            stderr: stderr,
            startedAt: now,
            finishedAt: now,
            wasCancelled: false
        )
    }
}
