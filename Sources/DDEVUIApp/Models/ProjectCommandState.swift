public struct CommandHistoryEntry: Equatable, Sendable {
    public let result: CommandResult

    public init(result: CommandResult) {
        self.result = result
    }
}

/// All command state scoped to a single project. Stored per project id in the view model's
/// `commandStates` dictionary (wired up in the per-project mutation/read pipelines).
public struct ProjectCommandState: Equatable, Sendable {
    /// Lifecycle of an in-flight *mutation* (start/stop/restart/…). Drives the cap, the
    /// row spinner, the single-command-per-project guard, and notifications.
    public enum Activity: Equatable, Sendable {
        case idle
        case queued
        case running
    }

    public var activity: Activity = .idle
    /// A *read* (logs/config/snapshot-list/addon-list) is in flight. Does not block lifecycle.
    public var isReadingData = false
    public var lastResult: CommandResult?
    public var lastErrorMessage: String?
    public var history: [CommandHistoryEntry] = []
    public var outputExpansionRequest = 0

    public init() {}

    public var isBusy: Bool { activity != .idle }
}
