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

    /// The full invocation as a single line (e.g. `ddev composer install`), for display and copy (B4).
    public var commandLine: String {
        ([executable] + arguments).joined(separator: " ")
    }

    /// Whether re-running this exact invocation from the history list is safe without re-prompting
    /// (B4). Destructive/guarded data & lifecycle ops are excluded so a one-click history re-run can't
    /// bypass the confirmations their normal UI enforces (DB drop, project delete, snapshot restore…).
    public var isSafelyRerunnable: Bool {
        guard let first = arguments.first else { return false }
        switch first {
        case "delete", "import-db", "poweroff", "clean":
            return false
        case "snapshot" where arguments.contains("restore"):
            return false
        case "stop" where arguments.contains("--unlist"):
            return false
        default:
            return true
        }
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
