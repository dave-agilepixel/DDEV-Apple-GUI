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
    /// Name of the throwaway volume used to measure headroom when nothing is running.
    /// Must satisfy Docker's `[a-zA-Z0-9][a-zA-Z0-9_.-]` rule — no leading underscore.
    static let probeVolumeName = "ddevui-diskprobe"

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
        let result = try await runDocker(["system", "df", "--format", "json"])
        return try DockerUsage.decode(result.stdout)
    }

    /// Per-volume inventory. Walks every volume, so this takes seconds on a machine with
    /// many projects — call it on demand, never on a background refresh cycle.
    public func volumes() async throws -> [DockerVolume] {
        let result = try await runDocker(["system", "df", "-v", "--format", "json"])
        return try DockerVolume.decodeList(result.stdout)
    }

    /// Free space on the Docker VM's filesystem.
    ///
    /// Prefers `docker exec` into an already-running container — effectively free. Falls back
    /// to mounting a throwaway volume, which is slower and may pull `alpine`.
    public func headroom() async throws -> DockerHeadroom {
        if let container = try? await firstRunningContainer() {
            let result = try await runDocker(["exec", container, "df", "-Pk", "/"])
            return try DockerHeadroom.parse(result.stdout)
        }
        return try await headroomViaProbeVolume()
    }

    private func firstRunningContainer() async throws -> String {
        let result = try await runDocker(["ps", "--format", "{{.Names}}"])
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
        _ = try await runDocker(["volume", "create", Self.probeVolumeName])

        // Cleanup is awaited on both paths rather than dispatched into a detached Task: the
        // probe volume must be gone before this function returns, or a later run finds it
        // already present and the caller sees a stale measurement.
        do {
            let result = try await runDocker([
                "run", "--rm", "-v", "\(Self.probeVolumeName):/probe", "alpine", "df", "-Pk", "/probe"
            ])
            let headroom = try DockerHeadroom.parse(result.stdout)
            await removeProbeVolume()
            return headroom
        } catch {
            await removeProbeVolume()
            throw error
        }
    }

    private func removeProbeVolume() async {
        _ = try? await runDocker(["volume", "rm", Self.probeVolumeName])
    }

    // MARK: - Reclaim

    @discardableResult
    public func pruneBuildCache() async throws -> CommandResult {
        try await runDocker(["builder", "prune", "-af"])
    }

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
                _ = try await runDocker(["volume", "rm", name])
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

    private func runDocker(_ arguments: [String]) async throws -> CommandResult {
        try await commandRunner.run(CommandSpec(executable: dockerExecutable, arguments: arguments))
    }
}
