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
                workingDirectory: nil
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

        let headroom = try await service.headroom()

        XCTAssertEqual(runner.commands.count, 2)
        XCTAssertEqual(runner.commands[0].arguments, ["ps", "--format", "{{.Names}}"])
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

        let headroom = try await service.headroom()

        XCTAssertEqual(runner.commands[1].arguments, ["volume", "create", "ddevui-diskprobe"])
        XCTAssertEqual(runner.commands[2].arguments, [
            "run", "--rm", "-v", "ddevui-diskprobe:/probe", "alpine", "df", "-Pk", "/probe"
        ])
        // The probe volume must always be cleaned up.
        XCTAssertEqual(runner.commands[3].arguments, ["volume", "rm", "ddevui-diskprobe"])
        XCTAssertEqual(headroom.availableBytes, 27_111_892 * 1024)
    }

    func testHeadroomRemovesProbeVolumeEvenWhenDFFails() async {
        struct Boom: Error {}
        let runner = RecordingCommandRunner(results: [
            .success(CommandResult.success(stdout: "")),
            .success(CommandResult.success()),
            .failure(Boom()),
            .success(CommandResult.success())
        ])
        let service = DockerSystemService(commandRunner: runner, dockerExecutable: "docker")

        _ = try? await service.headroom()

        XCTAssertTrue(
            runner.commands.contains { $0.arguments == ["volume", "rm", "ddevui-diskprobe"] },
            "probe volume must be cleaned up even on failure"
        )
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
