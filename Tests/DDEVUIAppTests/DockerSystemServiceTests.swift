import XCTest
@testable import DDEVUIApp

private final class RecordingCommandRunner: CommandRunning, @unchecked Sendable {
    private let lock = NSLock()
    private var results: [Result<CommandResult, Error>]
    private var recordedCommands: [CommandSpec] = []

    var commands: [CommandSpec] {
        lock.withLock { recordedCommands }
    }

    init(result: Result<CommandResult, Error>) {
        self.results = [result]
    }

    init(results: [Result<CommandResult, Error>]) {
        self.results = results
    }

    func run(_ spec: CommandSpec) async throws -> CommandResult {
        let result = lock.withLock {
            recordedCommands.append(spec)
            if results.count > 1 {
                return results.removeFirst()
            }
            return results.first ?? .success(CommandResult.success())
        }
        return try result.get()
    }
}

final class DockerSystemServiceTests: XCTestCase {

    func testUsageRunsSystemDFWithJSONFormat() async throws {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "docker-system-df", withExtension: "json"))
        let stdout = try String(contentsOf: url, encoding: .utf8)
        let runner = RecordingCommandRunner(result: .success(CommandResult.success(stdout: stdout)))
        let service = DockerSystemService(commandRunner: runner, dockerExecutable: "/usr/local/bin/docker")

        let usage = try await service.usage()

        XCTAssertEqual(runner.commands, [
            CommandSpec(
                executable: "/usr/local/bin/docker",
                arguments: ["system", "df", "--format", "json"],
                workingDirectory: nil,
                timeout: .seconds(10)
            )
        ])
        XCTAssertEqual(usage.images.totalCount, 32)
    }

    func testVolumesRunsSystemDFVerbose() async throws {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "docker-system-df-v", withExtension: "json"))
        let stdout = try String(contentsOf: url, encoding: .utf8)
        let runner = RecordingCommandRunner(result: .success(CommandResult.success(stdout: stdout)))
        let service = DockerSystemService(commandRunner: runner, dockerExecutable: "docker")

        let volumes = try await service.volumes()

        XCTAssertEqual(runner.commands.first?.arguments, ["system", "df", "-v", "--format", "json"])
        XCTAssertEqual(volumes.count, 7)
    }

    /// F5 — `docker system df -v` stats every volume individually and takes seconds, not
    /// milliseconds, on a machine with 100+ of them. It must not share the 10s quick cap used
    /// by the genuinely fast local reads, or a read that would have succeeded times out.
    func testVolumesUsesALongerTimeoutThanTheQuickReads() async throws {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "docker-system-df-v", withExtension: "json"))
        let stdout = try String(contentsOf: url, encoding: .utf8)
        let runner = RecordingCommandRunner(result: .success(CommandResult.success(stdout: stdout)))
        let service = DockerSystemService(commandRunner: runner, dockerExecutable: "docker")

        _ = try await service.volumes()

        let timeout = try XCTUnwrap(runner.commands.first?.timeout, "the inventory read must still be capped")
        XCTAssertGreaterThan(timeout, .seconds(10), "must not reuse the quick-read timeout")
    }

    /// F1 — with the probe fallback disallowed, a machine with nothing running must fail
    /// outright rather than falling through to `docker volume create` + `docker run alpine`.
    /// Only `docker ps` may be issued.
    func testHeadroomWithoutProbeNeverLaunchesAContainer() async throws {
        let runner = RecordingCommandRunner(results: [
            .success(CommandResult.success(stdout: "\n"))  // docker ps — nothing running
        ])
        let service = DockerSystemService(commandRunner: runner, dockerExecutable: "docker")

        do {
            _ = try await service.headroom(allowingProbeVolume: false)
            XCTFail("expected headroom to throw when no container is available and probing is off")
        } catch {
            guard case DockerSystemError.malformedOutput = error else {
                return XCTFail("expected malformedOutput, got \(error)")
            }
        }

        XCTAssertEqual(runner.commands.count, 1, "only `docker ps` may run")
        XCTAssertEqual(runner.commands[0].arguments.first, "ps")
        XCTAssertFalse(
            runner.commands.contains { $0.arguments.first == "run" || $0.arguments.first == "volume" },
            "the probe fallback must not run: it creates a volume and launches a container"
        )
    }

    /// The cheap exec path still works with probing disabled — the restriction removes only the
    /// expensive fallback, not the measurement itself.
    func testHeadroomWithoutProbeStillUsesTheExecPath() async throws {
        let dfOutput = """
        Filesystem           1024-blocks    Used Available Capacity Mounted on
        overlay               98759140  66888912  26820732  71% /
        """
        let runner = RecordingCommandRunner(results: [
            .success(CommandResult.success(stdout: "ddev-router\n")),
            .success(CommandResult.success(stdout: dfOutput))
        ])
        let service = DockerSystemService(commandRunner: runner, dockerExecutable: "docker")

        let headroom = try await service.headroom(allowingProbeVolume: false)

        XCTAssertEqual(headroom.percentUsed, 71)
        XCTAssertEqual(runner.commands.count, 2)
    }

    func testHeadroomExecsIntoFirstRunningContainer() async throws {
        let dfOutput = """
        Filesystem           1024-blocks    Used Available Capacity Mounted on
        overlay               98759140  66888912  26820732  71% /
        """
        let runner = RecordingCommandRunner(results: [
            .success(CommandResult.success(stdout: "ddev-router\nddev-aqua-pura-web\n")),
            .success(CommandResult.success(stdout: dfOutput))
        ])
        let service = DockerSystemService(commandRunner: runner, dockerExecutable: "docker")

        let headroom = try await service.headroom(allowingProbeVolume: true)

        XCTAssertEqual(runner.commands.count, 2)
        XCTAssertEqual(runner.commands[0].arguments, ["ps", "--filter", "name=ddev-", "--format", "{{.Names}}"])
        XCTAssertEqual(runner.commands[1].arguments, ["exec", "ddev-router", "df", "-Pk", "/"])
        XCTAssertEqual(headroom.percentUsed, 71)
    }

    func testHeadroomFallsBackToProbeVolumeWhenNothingIsRunning() async throws {
        let dfOutput = """
        Filesystem           1024-blocks    Used Available Capacity Mounted on
        /dev/vda1             98759140  66597752  27111892  71% /probe
        """
        let runner = RecordingCommandRunner(results: [
            .success(CommandResult.success(stdout: "\n")),            // docker ps — nothing running
            .success(CommandResult.success()),                        // volume create
            .success(CommandResult.success(stdout: dfOutput)),        // run … df
            .success(CommandResult.success())                         // volume rm
        ])
        let service = DockerSystemService(commandRunner: runner, dockerExecutable: "docker")

        let headroom = try await service.headroom(allowingProbeVolume: true)

        // The probe volume name is generated per invocation (finding 4), so assert its shape
        // and that create/mount/remove all reference the SAME name, rather than a literal.
        let createArguments = runner.commands[1].arguments
        XCTAssertEqual(createArguments.first, "volume")
        XCTAssertEqual(createArguments[1], "create")
        let volumeName = try XCTUnwrap(createArguments.last)
        XCTAssertTrue(volumeName.hasPrefix("ddevui-diskprobe-"), "unexpected probe volume name: \(volumeName)")

        XCTAssertEqual(runner.commands[2].arguments, [
            "run", "--rm", "-v", "\(volumeName):/probe", "alpine", "df", "-Pk", "/probe"
        ])
        // The probe volume must always be cleaned up, using the exact name that was created.
        XCTAssertEqual(runner.commands[3].arguments, ["volume", "rm", volumeName])
        XCTAssertEqual(headroom.availableBytes, 27_111_892 * 1024)
    }

    func testAlpineProbeCommandCarriesATimeout() async throws {
        let dfOutput = """
        Filesystem           1024-blocks    Used Available Capacity Mounted on
        /dev/vda1             98759140  66597752  27111892  71% /probe
        """
        let runner = RecordingCommandRunner(results: [
            .success(CommandResult.success(stdout: "\n")),
            .success(CommandResult.success()),
            .success(CommandResult.success(stdout: dfOutput)),
            .success(CommandResult.success())
        ])
        let service = DockerSystemService(commandRunner: runner, dockerExecutable: "docker")

        _ = try await service.headroom(allowingProbeVolume: true)

        let probeCommand = try XCTUnwrap(
            runner.commands.first { $0.arguments.first == "run" },
            "expected the alpine df probe command to have been recorded"
        )
        XCTAssertNotNil(probeCommand.timeout, "the alpine probe may pull an image over the network and must not hang forever")
    }

    func testHeadroomRemovesProbeVolumeEvenWhenDFFails() async throws {
        struct Boom: Error {}
        let runner = RecordingCommandRunner(results: [
            .success(CommandResult.success(stdout: "")),
            .success(CommandResult.success()),
            .failure(Boom()),
            .success(CommandResult.success())
        ])
        let service = DockerSystemService(commandRunner: runner, dockerExecutable: "docker")

        _ = try? await service.headroom(allowingProbeVolume: true)

        let createArguments = runner.commands[1].arguments
        let volumeName = try XCTUnwrap(createArguments.last)
        XCTAssertTrue(
            runner.commands.contains { $0.arguments == ["volume", "rm", volumeName] },
            "probe volume must be cleaned up even on failure, using the name that was created"
        )
    }

    func testHeadroomFallsBackToProbeWhenExecFailsAfterContainerIsFound() async throws {
        struct Boom: Error {}
        let dfOutput = """
        Filesystem           1024-blocks    Used Available Capacity Mounted on
        /dev/vda1             98759140  66597752  27111892  71% /probe
        """
        let runner = RecordingCommandRunner(results: [
            .success(CommandResult.success(stdout: "ddev-router\n")), // docker ps — a container is running
            .failure(Boom()),                                        // exec into it fails (exited/no df)
            .success(CommandResult.success()),                       // volume create
            .success(CommandResult.success(stdout: dfOutput)),       // run … df
            .success(CommandResult.success())                        // volume rm
        ])
        let service = DockerSystemService(commandRunner: runner, dockerExecutable: "docker")

        let headroom = try await service.headroom(allowingProbeVolume: true)

        XCTAssertEqual(runner.commands[0].arguments, ["ps", "--filter", "name=ddev-", "--format", "{{.Names}}"])
        XCTAssertEqual(runner.commands[1].arguments, ["exec", "ddev-router", "df", "-Pk", "/"])
        XCTAssertEqual(runner.commands[2].arguments.first, "volume")
        XCTAssertEqual(headroom.availableBytes, 27_111_892 * 1024)
    }

    func testPruneCommands() async throws {
        let runner = RecordingCommandRunner(result: .success(CommandResult.success()))
        let service = DockerSystemService(commandRunner: runner, dockerExecutable: "docker")

        _ = try await service.pruneBuildCache()
        _ = try await service.pruneUnusedImages()

        XCTAssertEqual(runner.commands.map(\.arguments), [
            ["builder", "prune", "-af"],
            ["image", "prune", "-af"]
        ])
    }

    func testRemoveVolumesReportsPerItemResultsAndContinuesAfterFailure() async {
        struct Boom: Error {}
        let runner = RecordingCommandRunner(results: [
            .success(CommandResult.success()),
            .failure(Boom()),
            .success(CommandResult.success())
        ])
        let service = DockerSystemService(commandRunner: runner, dockerExecutable: "docker")

        let results = await service.removeVolumes(["a", "b", "c"])

        XCTAssertEqual(results.count, 3, "a failure must not abort the batch")
        XCTAssertTrue(results[0].succeeded)
        XCTAssertFalse(results[1].succeeded)
        XCTAssertTrue(results[2].succeeded)
    }
}
