import Foundation

/// Decides what is safe to reclaim. Deliberately pure and I/O-free so the entire safety
/// policy is unit-testable without Docker running.
///
/// **The safety rule** — a volume is bulk-eligible if and only if it is `.mutagen` and not
/// `.running`, or it belongs to an `.orphaned` project. A `.database` volume for a registered
/// project is never in a bulk plan. This rule exists in this file and nowhere else.
public enum ReclaimPlanner {
    private static let mutagenSuffix = "_project_mutagen"

    /// Every suffix DDEV gives a project's database volume.
    ///
    /// Verified against DDEV v1.25.3 rather than guessed. Its compose template picks the volume
    /// name with `{{ if eq .DBType "postgres" }}{{ .PostgresVolumeName }}{{ else }}{{
    /// .MariaDBVolumeName }}{{ end }}` — so PostgreSQL projects get `<project>-postgres` and
    /// *every other* database type, MySQL included, gets `<project>-mariadb`. There is
    /// deliberately no `-mysql` suffix: MySQL projects share the MariaDB volume name, so adding
    /// one would match nothing.
    ///
    /// Getting this list wrong is a safety bug in both directions. Too narrow and a real database
    /// classifies `.other`, which renders the generic "This permanently deletes <name>."
    /// confirmation with no snapshot warning. Too wide and a non-database volume gets alarming
    /// copy it does not warrant.
    private static let databaseSuffixes = ["-mariadb", "-postgres"]

    /// Attributes each volume to a project and works out what it holds.
    ///
    /// Matching strips the exact suffix and then requires exact membership of the project set.
    /// Prefix matching would be wrong: `thethreeswords` is a strict prefix of
    /// `thethreeswordsguiseley`, and both are real projects.
    ///
    /// An empty `projects` list never yields `.orphaned` — see the guard inside the `state`
    /// closure below for why. This matters beyond `plan(volumes:projects:usage:)`: this public
    /// entry point is also used to render an "all volumes" list with a delete button on every
    /// orphaned row, so it must refuse to attribute orphan status on its own, independent of
    /// the `plan` guard.
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
                for databaseSuffix in databaseSuffixes where volume.name.hasSuffix(databaseSuffix) {
                    let stripped = String(volume.name.dropLast(databaseSuffix.count))
                    // As with the mutagen suffix above, a volume named exactly `-mariadb` strips
                    // to an empty name and is not an attribution to any project.
                    return stripped.isEmpty ? (.other, nil) : (.database, stripped)
                }
                return (.other, nil)
            }()

            let state: ProjectState = {
                // Docker's own link count is the authority on whether the volume is mounted,
                // regardless of what DDEV believes the project's status to be. This check must
                // keep winning even when the project list is empty: an in-use volume is
                // observably running, whatever we can or can't say about its owning project.
                if volume.isInUse { return .running }
                // An empty project list is indistinguishable from a failed `ddev list` that
                // returned nothing, rather than genuine proof no DDEV projects exist. Attributing
                // `.orphaned` here would be untrustworthy: every database volume for a real,
                // registered project would be classified "no such DDEV project" and rendered
                // with a delete button beside it. So refuse orphan status outright until the
                // project list is non-empty and therefore trustworthy. `.stopped` is the
                // narrowest available state — it already means "not known to be in use, not
                // orphaned" for unattributed volumes above, and every existing switch over
                // `ProjectState` treats it as non-deletable without a project to act against.
                guard !projectsByName.isEmpty else { return .stopped }
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
                //
                // `(.other, .orphaned)` is unreachable today: `.other` is exactly the branch in
                // `classify` that returns a `nil` project name, and the `state` closure maps a
                // `nil` project name to `.stopped`, never `.orphaned`. It is kept deliberately as
                // a statement of policy — *if* an unrecognised volume ever became attributable to
                // a deleted project, removing it is the right call — so that a future change to
                // the classifier does not silently fall through to `default` and quietly drop it.
                items.append(ReclaimItem(
                    action: .removeVolume(name: classified.volume.name),
                    label: classified.volume.name,
                    detail: "Orphaned — no such DDEV project",
                    estimatedBytes: classified.volume.sizeBytes,
                    isDatabase: classified.kind == .database
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
