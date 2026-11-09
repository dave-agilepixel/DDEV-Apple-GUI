import Foundation

/// Maps `ddev start` / `ddev restart` output lines to a coarse, **monotonic** progress fraction
/// and a short label for the step in progress. This is a stage estimate, not a true percentage —
/// DDEV emits no percentage. When no stage is recognised (e.g. a future DDEV changes its wording),
/// `fraction` and `stage` stay `nil` and the UI falls back to an indeterminate spinner rather than
/// showing a wrong or stuck number. Progress is capped strictly below `1.0` while running; the
/// project row dismisses the donut the moment the command completes.
public struct StartProgressParser {
    /// Ordered stage needles → fraction and label. Matched case-insensitively; a line may match
    /// several, in which case the highest wins. Tuned against captured DDEV v1.25.2 output (see
    /// Tests/DDEVUIAppTests/Fixtures/ddev-start-output.txt). DDEV prints its slow steps as
    /// "Message..." and only ends the line when the step finishes, so the runner emits that
    /// unterminated "..." prefix early and the label describes the step while it is running.
    private static let stages: [(needle: String, fraction: Double, label: String)] = [
        ("starting", 0.05, "Starting"),
        ("building", 0.12, "Building images"),
        ("created", 0.25, "Creating containers"),
        ("started", 0.40, "Starting containers"),
        ("mutagen", 0.55, "Syncing files"),
        ("waiting for", 0.70, "Waiting for containers"),
        ("pushing", 0.82, "Starting router"),
        ("waiting for ddev-router", 0.90, "Waiting for router"),
        ("successfully started", 0.97, "Finishing")
    ]

    public private(set) var fraction: Double?
    /// Label for the furthest stage reached, e.g. "Syncing files".
    public private(set) var stage: String?

    public init() {}

    /// Feeds one output line. Returns the new fraction if this line advanced progress, else `nil`.
    public mutating func consume(_ line: String) -> Double? {
        let lower = line.lowercased()
        var matched: (fraction: Double, label: String)?
        for stage in Self.stages where lower.contains(stage.needle) {
            if stage.fraction > (matched?.fraction ?? 0) { matched = (stage.fraction, stage.label) }
        }
        guard let matched, matched.fraction > (fraction ?? 0) else { return nil }
        fraction = matched.fraction
        stage = matched.label
        return matched.fraction
    }
}
