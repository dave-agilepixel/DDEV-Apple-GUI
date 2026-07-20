import Foundation

/// What a volume holds. Only `.mutagen` is disposable without consequence — it is a file-sync
/// cache that DDEV rebuilds on the next start.
public enum VolumeKind: Equatable, Sendable {
    case mutagen
    case database
    case other
}

/// The state of the DDEV project a volume belongs to.
public enum ProjectState: Equatable, Sendable {
    case running
    case stopped
    /// No DDEV project of this name is registered — a leftover from a deleted project.
    case orphaned
}

public struct ClassifiedVolume: Equatable, Sendable, Identifiable {
    public let volume: DockerVolume
    public let kind: VolumeKind
    /// `nil` when the volume name doesn't follow a DDEV naming convention at all.
    public let projectName: String?
    public let state: ProjectState

    public var id: String { volume.name }

    public init(volume: DockerVolume, kind: VolumeKind, projectName: String?, state: ProjectState) {
        self.volume = volume
        self.kind = kind
        self.projectName = projectName
        self.state = state
    }
}

/// A single reclaim operation. Which service executes it is decided by the view model:
/// `mutagenReset` goes through `DDEVServicing`, the rest through `DockerSystemServicing`.
///
/// There is deliberately no `staleDDEVImages` case. `docker image prune -af` already removes
/// every image not used by a container, which includes stale `ddev/ddev-*` images from earlier
/// DDEV versions — so `unusedImages` subsumes what the old "Delete DDEV Images" button did,
/// and running `ddev delete images` as well would be redundant.
public enum ReclaimAction: Equatable, Sendable {
    case buildCache
    case unusedImages
    /// `ddev mutagen reset` is keyed by working directory, not project name.
    case mutagenReset(project: String, appRoot: String)
    case removeVolume(name: String)
}

public struct ReclaimItem: Equatable, Sendable, Identifiable {
    public let action: ReclaimAction
    public let label: String
    public let detail: String
    public let estimatedBytes: Int64
    /// Whether this item removes an orphaned project's database. `ReclaimAction.removeVolume`
    /// alone doesn't carry that — it's just a volume name — so callers that need to warn about
    /// data loss (the reclaim confirmation dialog, the itemised plan row) must be able to ask
    /// without re-deriving it from the volume name's suffix.
    public let isDatabase: Bool

    public var id: String { label }

    public init(action: ReclaimAction, label: String, detail: String, estimatedBytes: Int64, isDatabase: Bool = false) {
        self.action = action
        self.label = label
        self.detail = detail
        self.estimatedBytes = estimatedBytes
        self.isDatabase = isDatabase
    }
}

public struct ReclaimPlan: Equatable, Sendable {
    public let items: [ReclaimItem]

    public init(items: [ReclaimItem]) {
        self.items = items
    }

    public var totalBytes: Int64 {
        items.reduce(0) { $0 + $1.estimatedBytes }
    }

    public var isEmpty: Bool { items.isEmpty }

    /// Orphaned-project databases in this plan — the one category the bulk Reclaim button can
    /// destroy that a user might reasonably assume is safe. Empty for every plan that doesn't
    /// contain one.
    ///
    /// The predicate checks the action as well as `isDatabase`, rather than filtering on
    /// `isDatabase` alone. `isDatabase` is currently only ever set on the orphaned
    /// `.removeVolume` branch of `ReclaimPlanner.plan`, which makes the shorter filter *happen*
    /// to be correct — but this property's name promises "a database that is removed outright
    /// because its project is gone", and the confirmation dialog's "cannot be undone, take a
    /// snapshot" copy depends on that being literally true. Requiring `.removeVolume` enforces
    /// the invariant here rather than relying on a distant call site never setting the flag on,
    /// say, a recoverable `.mutagenReset` item.
    public var orphanedDatabaseItems: [ReclaimItem] {
        items.filter { item in
            guard item.isDatabase else { return false }
            if case .removeVolume = item.action { return true }
            return false
        }
    }

    public var hasOrphanedDatabase: Bool { !orphanedDatabaseItems.isEmpty }
}
