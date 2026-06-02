import Foundation

/// Maps `ddev start` / `ddev restart` output lines to a coarse, **monotonic** progress fraction
/// for the project-row donut. This is a stage estimate, not a true percentage — DDEV emits no
/// percentage. When no stage is recognized (e.g. a future DDEV changes its wording), `fraction`
/// stays `nil` and the UI falls back to an indeterminate spinner rather than showing a wrong or
/// stuck number. `1.0` is reserved for `markCompleted()` (process exit), so a recognized run can
/// never visually "finish" before the command actually returns.
public struct StartProgressParser {
    /// Ordered stage needles → fraction. Matched case-insensitively; a line may match several,
    /// in which case the highest wins. Tuned against captured DDEV v1.25.2 output (see
    /// Tests/DDEVUIAppTests/Fixtures/ddev-start-output.txt).
    private static let stages: [(needle: String, fraction: Double)] = [
        ("starting", 0.10),
        ("building", 0.20),
        ("recreating", 0.30),
        ("creating", 0.30),
        ("started", 0.55),
        ("waiting for", 0.70),
        ("pushing", 0.82),
        ("syncing", 0.82),
        ("successfully started", 0.95),
        ("ready", 0.95)
    ]

    public private(set) var fraction: Double?

    public init() {}

    /// Feeds one output line. Returns the new fraction if this line advanced progress, else `nil`.
    public mutating func consume(_ line: String) -> Double? {
        let lower = line.lowercased()
        var matched: Double?
        for stage in Self.stages where lower.contains(stage.needle) {
            matched = max(matched ?? 0, stage.fraction)
        }
        guard let matched else { return nil }
        let next = max(fraction ?? 0, matched)
        guard next != fraction else { return nil } // no visible change
        fraction = next
        return next
    }

    /// Process exited successfully — pin to 100%.
    public mutating func markCompleted() { fraction = 1.0 }
}
