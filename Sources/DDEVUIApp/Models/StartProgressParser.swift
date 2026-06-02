import Foundation

/// Maps `ddev start` / `ddev restart` output lines to a coarse, **monotonic** progress fraction
/// for the project-row donut. This is a stage estimate, not a true percentage — DDEV emits no
/// percentage. When no stage is recognized (e.g. a future DDEV changes its wording), `fraction`
/// stays `nil` and the UI falls back to an indeterminate spinner rather than showing a wrong or
/// stuck number. Progress is capped strictly below `1.0` while running; the project row dismisses the donut
/// (the project flips to a non-busy state) the moment the command completes, so there is no
/// separate 100% step to render.
public struct StartProgressParser {
    /// Ordered stage needles → fraction. Matched case-insensitively; a line may match several,
    /// in which case the highest wins. Tuned against captured DDEV v1.25.2 output (see
    /// Tests/DDEVUIAppTests/Fixtures/ddev-start-output.txt).
    private static let stages: [(needle: String, fraction: Double)] = [
        ("starting", 0.08),
        ("building", 0.18),
        ("created", 0.28),
        ("started", 0.45),
        ("waiting for", 0.70),
        ("pushing", 0.82),
        ("successfully started", 0.95)
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

}
