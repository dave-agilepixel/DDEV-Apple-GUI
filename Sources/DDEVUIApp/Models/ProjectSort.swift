import Foundation

/// How the project list is ordered (B5). Persisted as a preference. "Recently used" is backed by a
/// session-scoped recency list maintained by the view model.
public enum ProjectSort: String, CaseIterable, Identifiable, Codable, Sendable {
    case name
    case status
    case recentlyUsed = "recently-used"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .name: "Name"
        case .status: "Status"
        case .recentlyUsed: "Recently Used"
        }
    }

    public var systemImage: String {
        switch self {
        case .name: "textformat.abc"
        case .status: "circle.fill"
        case .recentlyUsed: "clock"
        }
    }

    /// Returns `projects` ordered for this sort. `recentIDs` is most-recent-first; unseen projects
    /// fall to the end. All modes break ties case-insensitively by name so ordering is stable.
    public func sort(_ projects: [DDEVProject], recentIDs: [String]) -> [DDEVProject] {
        switch self {
        case .name:
            return projects.sorted(by: Self.byName)
        case .status:
            return projects.sorted { a, b in
                let ra = a.status == .running ? 0 : 1
                let rb = b.status == .running ? 0 : 1
                if ra != rb { return ra < rb }
                return Self.byName(a, b)
            }
        case .recentlyUsed:
            return projects.sorted { a, b in
                let ra = recentIDs.firstIndex(of: a.id) ?? Int.max
                let rb = recentIDs.firstIndex(of: b.id) ?? Int.max
                if ra != rb { return ra < rb }
                return Self.byName(a, b)
            }
        }
    }

    private static func byName(_ a: DDEVProject, _ b: DDEVProject) -> Bool {
        a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
    }
}
