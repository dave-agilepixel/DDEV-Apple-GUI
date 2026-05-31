import Foundation

extension Error {
    /// A concise, user-facing message. Crucially, for `CommandRunnerError` it extracts the
    /// child's stderr (or exit code) rather than letting `String(describing:)` dump the entire
    /// `CommandResult` struct — stdout, stderr, timestamps, args — into a UI banner (audit M10).
    var presentableMessage: String {
        if let commandError = self as? CommandRunnerError {
            switch commandError {
            case let .nonZeroExit(result):
                return result.stderr.nilIfBlank ?? "Command failed with exit code \(result.exitCode)."
            case .timedOut:
                return "Command timed out."
            }
        }
        if self is CancellationError {
            return "Command was cancelled."
        }
        return localizedDescription
    }
}
