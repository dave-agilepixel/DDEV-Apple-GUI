import Foundation

/// Decides what is safe to reclaim. Deliberately pure and I/O-free so the entire safety
/// policy is unit-testable without Docker running.
///
/// **The safety rule** — a volume is bulk-eligible if and only if it is `.mutagen` and not
/// `.running`, or it belongs to an `.orphaned` project. A `.database` volume for a registered
/// project is never in a bulk plan. This rule exists in this file and nowhere else.
public enum ReclaimPlanner {
    private static let mutagenSuffix = "_project_mutagen"
    private static let databaseSuffix = "-mariadb"

    /// Attributes each volume to a project and works out what it holds.
    ///
    /// Matching strips the exact suffix and then requires exact membership of the project set.
    /// Prefix matching would be wrong: `thethreeswords` is a strict prefix of
    /// `thethreeswordsguiseley`, and both are real projects.
    public static func classify(volumes: [DockerVolume], projects: [DDEVProject]) -> [ClassifiedVolume] {
        classify(volumes: volumes, projectsByName: index(projects))
    }

    /// Indexes projects by name. `ddev list -j` offers no uniqueness guarantee, so duplicate
    /// names must not trap at runtime — the first occurrence wins.
    private static func index(_ projects: [DDEVProject]) -> [String: DDEVProject] {
        Dictionary(projects.map { ($0.name, $0) }, uniquingKeysWith: { first, _ in first })
    }

    private static func classify(
        volumes: [DockerVolume],
        projectsByName: [String: DDEVProject]
    ) -> [ClassifiedVolume] {
        volumes.map { volume in
            let (kind, projectName): (VolumeKind, String?) = {
                if volume.name.hasSuffix(mutagenSuffix) {
                    let stripped = String(volume.name.dropLast(mutagenSuffix.count))
                    // A volume named exactly `_project_mutagen` strips to an empty name. That is
                    // not an attribution to any project, so it must not reach the orphan branch.
                    return stripped.isEmpty ? (.other, nil) : (.mutagen, stripped)
                }
                if volume.name.hasSuffix(databaseSuffix) {
                    let stripped = String(volume.name.dropLast(databaseSuffix.count))
                    return stripped.isEmpty ? (.other, nil) : (.database, stripped)
                }
                return (.other, nil)
            }()

            let state: ProjectState = {
                // Docker's own link count is the authority on whether the volume is mounted,
                // regardless of what DDEV believes the project's status to be.
                if volume.isInUse { return .running }
                guard let projectName, let project = projectsByName[projectName] else {
                    return projectName == nil ? .stopped : .orphaned
                }
                // Fail narrow: only an explicitly stopped project yields `.stopped`. `.paused`
                // and `.unknown` (what a failed status parse produces) are treated as running,
                // so a parse failure can never widen eligibility.
                return project.status == .stopped ? .stopped : .running
            }()

            return ClassifiedVolume(volume: volume, kind: kind, projectName: projectName, state: state)
        }
    }

    /// Builds the safe-by-default bulk plan.
    public static func plan(
        volumes: [DockerVolume],
        projects: [DDEVProject],
        usage: DockerUsage
    ) -> ReclaimPlan {
        var items: [ReclaimItem] = []
        let projectsByName = index(projects)

        if usage.buildCache.reclaimableBytes > 0 {
            items.append(ReclaimItem(
                action: .buildCache,
                label: "Build cache",
                detail: "Rebuilt automatically when needed",
                estimatedBytes: usage.buildCache.reclaimableBytes
            ))
        }

        if usage.images.reclaimableBytes > 0 {
            // Covers stale `ddev/ddev-*` images from earlier versions too — anything not
            // currently used by a container.
            items.append(ReclaimItem(
                action: .unusedImages,
                label: "Unused images",
                detail: "Re-pulled on next start",
                estimatedBytes: usage.images.reclaimableBytes
            ))
        }

        // An empty project list is indistinguishable from a failed `ddev list` that returned
        // nothing. Orphan detection is meaningless without a trustworthy project list — every
        // volume would look orphaned, including every registered project's database — so we fail
        // narrow and offer only the usage-derived items, never a volume.
        guard !projects.isEmpty else { return ReclaimPlan(items: items) }

        for classified in classify(volumes: volumes, projectsByName: projectsByName) {
            // An in-use volume can never be removed, whatever it holds.
            guard classified.state != .running else { continue }

            switch (classified.kind, classified.state) {
            case (.mutagen, .stopped):
                // A registered, stopped project — reset through DDEV so its own state stays
                // consistent. `ddev mutagen reset` is keyed by working directory.
                guard let projectName = classified.projectName,
                      let project = projectsByName[projectName] else { continue }
                items.append(ReclaimItem(
                    action: .mutagenReset(project: projectName, appRoot: project.appRoot),
                    label: "\(projectName) sync cache",
                    detail: "Rebuilt on next start",
                    estimatedBytes: classified.volume.sizeBytes
                ))

            case (.mutagen, .orphaned), (.database, .orphaned), (.other, .orphaned):
                // No DDEV project remains, so remove the volume directly.
                items.append(ReclaimItem(
                    action: .removeVolume(name: classified.volume.name),
                    label: classified.volume.name,
                    detail: "Orphaned — no such DDEV project",
                    estimatedBytes: classified.volume.sizeBytes
                ))

            default:
                // Registered projects' databases and unrecognised volumes are never
                // bulk-eligible. They are removable only by explicit per-item selection.
                continue
            }
        }

        return ReclaimPlan(items: items)
    }
}
