import Foundation

/// Result of attempting to remove one volume. Removal is reported per item so a single
/// stuck volume neither aborts the batch nor leaves it ambiguous what actually happened.
public struct VolumeRemovalResult: Equatable, Sendable {
    public let name: String
    public let succeeded: Bool
    public let message: String?

    public init(name: String, succeeded: Bool, message: String?) {
        self.name = name
        self.succeeded = succeeded
        self.message = message
    }
}

/// Reads Docker's disk usage and performs reclaim operations that DDEV cannot express.
/// Mirrors `DDEVCommandService`: inject a `CommandRunning`, resolve the executable once.
public final class DockerSystemService: Sendable {
    /// Prefix for the throwaway volume used to measure headroom when nothing is running. The
    /// full name appends a UUID per invocation (finding 4) so two concurrent `headroom()` calls
    /// never share a volume, and so a real user volume can never collide with it. Still satisfies
    /// Docker's `[a-zA-Z0-9][a-zA-Z0-9_.-]` rule — starts with a letter, and a UUID's hyphens are
    /// permitted mid-name (never leading).
    static let probeVolumePrefix = "ddevui-diskprobe-"

    /// Wall-clock cap for fast local reads/writes (`docker ps`, `system df`, `volume create`/`rm`,
    /// `exec … df`) that never touch the network. Generous enough to absorb a slow daemon without
    /// risking an indefinite hang (audit precedent: `DDEVCommandService.listAllAddOns`).
    private static let quickTimeout: Duration = .seconds(10)

    /// Wall-clock cap for the `alpine df` probe, which may pull the `alpine` image over the
    /// network if it isn't already cached. Matches the 45s precedent used for `add-on list`
    /// in `DDEVCommandService`, which hits the network for the same reason.
    private static let probeTimeout: Duration = .seconds(45)

    /// Wall-clock cap for `docker system df -v`, deliberately longer than `quickTimeout`.
    /// Unlike the other local reads, this one stats every volume individually: on a machine with
    /// 100+ volumes (the development machine this was built against has ~110) it takes seconds
    /// rather than milliseconds, so the 10s quick cap is close enough to the real runtime to time
    /// out a read that would have succeeded. This is a user-visible inventory read, not a
    /// background poll, so a longer wait is cheaper than a spurious failure.
    private static let inventoryTimeout: Duration = .seconds(60)

    private let commandRunner: CommandRunning
    private let dockerExecutable: String

    public init(
        commandRunner: CommandRunning = ProcessCommandRunner(),
        dockerExecutable: String = DockerExecutableResolver().resolve()
    ) {
        self.commandRunner = commandRunner
        self.dockerExecutable = dockerExecutable
    }

    // MARK: - Reads

    /// Category totals. Emits JSON-lines, one object per category.
    public func usage() async throws -> DockerUsage {
        let result = try await runDocker(["system", "df", "--format", "json"], timeout: Self.quickTimeout)
        return try DockerUsage.decode(result.stdout)
    }

    /// Per-volume inventory. Walks every volume, so this takes seconds on a machine with
    /// many projects — call it on demand, never on a background refresh cycle.
    public func volumes() async throws -> [DockerVolume] {
        let result = try await runDocker(["system", "df", "-v", "--format", "json"], timeout: Self.inventoryTimeout)
        return try DockerVolume.decodeList(result.stdout)
    }

    /// Free space on the Docker VM's filesystem.
    ///
    /// Prefers `docker exec` into an already-running container — effectively free. Falls back
    /// to mounting a throwaway volume, which is slower and may pull `alpine`.
    ///
    /// `allowingProbeVolume` gates that fallback, and exists because the two paths differ in
    /// cost by orders of magnitude. The exec path is a `docker ps` and a `df` inside a container
    /// that is already running. The probe path is a `docker volume create` + `docker run --rm
    /// alpine df` + `docker volume rm` — it *launches a container*. On an idle machine with no
    /// DDEV project running, the exec path always throws (there is no container to exec into),
    /// so an unguarded call falls through to the probe every single time. Driven from a periodic
    /// refresh that means launching a container on a short loop, forever.
    ///
    /// So the periodic caller passes `false` and simply reports "headroom unavailable" when
    /// nothing is running, while explicit, user-initiated refreshes pass `true` and pay for the
    /// real measurement. That keeps the expensive path bounded by user actions rather than by a
    /// timer, without needing a cache or a second cadence to reason about.
    public func headroom(allowingProbeVolume: Bool) async throws -> DockerHeadroom {
        // Any failure of the exec path — container selection, the exec itself, or a container
        // whose image has no `df` — falls through to the probe volume (finding 2). Only a
        // successful measurement short-circuits the fallback.
        if let container = try? await firstRunningContainer(),
           let headroom = try? await headroomViaExec(in: container) {
            return headroom
        }
        guard allowingProbeVolume else {
            throw DockerSystemError.malformedOutput(
                "no running DDEV container to measure headroom from"
            )
        }
        return try await headroomViaProbeVolume()
    }

    private func headroomViaExec(in container: String) async throws -> DockerHeadroom {
        let result = try await runDocker(["exec", container, "df", "-Pk", "/"], timeout: Self.quickTimeout)
        return try DockerHeadroom.parse(result.stdout)
    }

    private func firstRunningContainer() async throws -> String {
        // Scoped to DDEV's own containers (finding 3): an unfiltered `docker ps` could select any
        // container on the machine, including a distroless image with no `df` binary. DDEV's
        // container images are known to contain `df`.
        let result = try await runDocker(["ps", "--filter", "name=ddev-", "--format", "{{.Names}}"], timeout: Self.quickTimeout)
        let names = result.stdout
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        guard let first = names.first else {
            throw DockerSystemError.malformedOutput("no running containers")
        }
        return first
    }

    private func headroomViaProbeVolume() async throws -> DockerHeadroom {
        // Unique per invocation (finding 4): a fixed name would let a real user volume of the
        // same name be silently destroyed, and would let two concurrent headroom() calls race to
        // remove the volume the other is still using.
        let volumeName = "\(Self.probeVolumePrefix)\(UUID().uuidString)"
        _ = try await runDocker(["volume", "create", volumeName], timeout: Self.quickTimeout)

        // Cleanup is awaited on both paths rather than dispatched into a detached Task: a leaked
        // probe volume is never swept, and would later surface in volumes() as an ordinary user
        // volume that the reclaim UI offers for deletion (finding 5).
        do {
            let result = try await runDocker([
                "run", "--rm", "-v", "\(volumeName):/probe", "alpine", "df", "-Pk", "/probe"
            ], timeout: Self.probeTimeout)
            let headroom = try DockerHeadroom.parse(result.stdout)
            await removeProbeVolume(named: volumeName)
            return headroom
        } catch {
            await removeProbeVolume(named: volumeName)
            throw error
        }
    }

    private func removeProbeVolume(named volumeName: String) async {
        _ = try? await runDocker(["volume", "rm", volumeName], timeout: Self.quickTimeout)
    }

    // MARK: - Reclaim

    // No timeout: on a large build cache this legitimately runs for minutes reclaiming disk, and
    // the caller drives this from an explicit user action (not a background refresh), so there is
    // no risk of it silently pinning a hidden thread — the user can see and cancel it.
    @discardableResult
    public func pruneBuildCache() async throws -> CommandResult {
        try await runDocker(["builder", "prune", "-af"])
    }

    // No timeout, for the same reason as pruneBuildCache(): reclaiming a large image cache
    // legitimately takes minutes and is a deliberate, user-visible action.
    @discardableResult
    public func pruneUnusedImages() async throws -> CommandResult {
        try await runDocker(["image", "prune", "-af"])
    }

    /// Removes volumes one at a time, reporting each outcome. Never throws — a volume that
    /// became in-use mid-run must not abort the remaining removals.
    public func removeVolumes(_ names: [String]) async -> [VolumeRemovalResult] {
        var results: [VolumeRemovalResult] = []
        for name in names {
            do {
                _ = try await runDocker(["volume", "rm", name], timeout: Self.quickTimeout)
                results.append(VolumeRemovalResult(name: name, succeeded: true, message: nil))
            } catch {
                results.append(VolumeRemovalResult(
                    name: name,
                    succeeded: false,
                    message: error.presentableMessage
                ))
            }
        }
        return results
    }

    // MARK: - Plumbing

    private func runDocker(_ arguments: [String], timeout: Duration? = nil) async throws -> CommandResult {
        try await commandRunner.run(
            CommandSpec(executable: dockerExecutable, arguments: arguments, timeout: timeout)
        )
    }
}
