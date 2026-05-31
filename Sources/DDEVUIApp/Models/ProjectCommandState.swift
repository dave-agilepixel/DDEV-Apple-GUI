import Foundation

public struct CommandHistoryEntry: Identifiable, Equatable, Sendable {
    /// Stable identity set at creation so SwiftUI keeps row state correct as the capped
    /// history window slides (audit M8). Keying a ForEach on the array offset reused a
    /// row's identity for a different command once `removeFirst` shifted indices.
    public let id: UUID
    public let result: CommandResult

    public init(result: CommandResult) {
        self.id = UUID()
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
