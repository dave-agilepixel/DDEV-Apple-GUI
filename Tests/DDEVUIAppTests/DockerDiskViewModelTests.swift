import XCTest
@testable import DDEVUIApp

private final class FakeDockerSystemService: DockerSystemServicing, @unchecked Sendable {
    var headroomResult: Result<DockerHeadroom, Error> = .success(
        DockerHeadroom(totalBytes: 100_000, usedBytes: 50_000, availableBytes: 50_000)
    )
    var usageResult: Result<DockerUsage, Error>
    var volumesResult: Result<[DockerVolume], Error> = .success([])
    private(set) var prunedBuildCache = false
    private(set) var prunedImages = false
    private(set) var removedVolumes: [String] = []

    init() {
        let zero = DockerUsageCategory(totalCount: 0, active: 0, sizeBytes: 0, reclaimableBytes: 0)
        usageResult = .success(DockerUsage(images: zero, containers: zero, volumes: zero, buildCache: zero))
    }

    func usage() async throws -> DockerUsage { try usageResult.get() }
    func headroom() async throws -> DockerHeadroom { try headroomResult.get() }
    func volumes() async throws -> [DockerVolume] { try volumesResult.get() }

    func pruneBuildCache() async throws -> CommandResult {
        prunedBuildCache = true
        return CommandResult.success()
    }

    func pruneUnusedImages() async throws -> CommandResult {
        prunedImages = true
        return CommandResult.success()
    }

    func removeVolumes(_ names: [String]) async -> [VolumeRemovalResult] {
        removedVolumes.append(contentsOf: names)
        return names.map { VolumeRemovalResult(name: $0, succeeded: true, message: nil) }
    }
}

@MainActor
final class DockerDiskViewModelTests: XCTestCase {

    private func makeViewModel(
        docker: FakeDockerSystemService = FakeDockerSystemService()
    ) -> DockerDiskViewModel {
        DockerDiskViewModel(dockerService: docker, warnThreshold: 0.85, criticalThreshold: 0.93)
    }

    /// A minimal registered, running project — used to give `ReclaimPlanner` a trustworthy,
    /// non-empty project list so it will actually classify orphaned volumes rather than
    /// refusing to (see `testExecuteReclaimRunsPlannedActions` and
    /// `testEmptyProjectListReclaimsNoVolumes` below for why that distinction matters).
    private func makeProject(named name: String) -> DDEVProject {
        DDEVProject(
            name: name,
            appRoot: "/tmp/\(name)",
            shortRoot: "~/\(name)",
            status: .running,
            statusDescription: "running",
            projectType: .php,
            docroot: "",
            primaryURL: nil,
            httpURL: nil,
            httpsURL: nil,
            mailpitURL: nil,
            mailpitHTTPSURL: nil,
            xhguiURL: nil,
            xhguiHTTPSURL: nil,
            mutagenEnabled: false,
            mutagenStatus: nil
        )
    }

    func testAlertLevelIsNormalBelowWarnThreshold() async {
        let docker = FakeDockerSystemService()
        docker.headroomResult = .success(
            DockerHeadroom(totalBytes: 1000, usedBytes: 700, availableBytes: 300)  // 70%
        )
        let viewModel = makeViewModel(docker: docker)

        await viewModel.refreshHeadroom()

        XCTAssertEqual(viewModel.alertLevel, .normal)
    }

    func testAlertLevelIsWarningAtWarnThreshold() async {
        let docker = FakeDockerSystemService()
        docker.headroomResult = .success(
            DockerHeadroom(totalBytes: 1000, usedBytes: 870, availableBytes: 130)  // 87%
        )
        let viewModel = makeViewModel(docker: docker)

        await viewModel.refreshHeadroom()

        XCTAssertEqual(viewModel.alertLevel, .warning)
    }

    func testAlertLevelIsCriticalAtCriticalThreshold() async {
        let docker = FakeDockerSystemService()
        docker.headroomResult = .success(
            DockerHeadroom(totalBytes: 1000, usedBytes: 950, availableBytes: 50)  // 95%
        )
        let viewModel = makeViewModel(docker: docker)

        await viewModel.refreshHeadroom()

        XCTAssertEqual(viewModel.alertLevel, .critical)
    }

    func testFailedHeadroomProbeProducesNoWarning() async {
        // Critical: a failed probe must never be read as "0% free".
        struct Boom: Error {}
        let docker = FakeDockerSystemService()
        docker.headroomResult = .failure(Boom())
        let viewModel = makeViewModel(docker: docker)

        await viewModel.refreshHeadroom()

        XCTAssertNil(viewModel.headroom)
        XCTAssertEqual(viewModel.alertLevel, .normal, "unmeasurable disk must not raise an alert")
    }

    func testExecuteReclaimRunsPlannedActions() async {
        // A non-empty project list that does *not* include "westlife" is required here: only
        // then does `ReclaimPlanner` trust the list enough to classify `westlife_project_mutagen`
        // as `.orphaned` and offer it for removal (see `testEmptyProjectListReclaimsNoVolumes`
        // below for what happens with an empty list instead).
        let docker = FakeDockerSystemService()
        docker.usageResult = .success(DockerUsage(
            images: DockerUsageCategory(totalCount: 5, active: 1, sizeBytes: 10_000, reclaimableBytes: 5_000),
            containers: DockerUsageCategory(totalCount: 0, active: 0, sizeBytes: 0, reclaimableBytes: 0),
            volumes: DockerUsageCategory(totalCount: 0, active: 0, sizeBytes: 0, reclaimableBytes: 0),
            buildCache: DockerUsageCategory(totalCount: 3, active: 0, sizeBytes: 2_000, reclaimableBytes: 2_000)
        ))
        docker.volumesResult = .success([
            DockerVolume(name: "westlife_project_mutagen", sizeBytes: 1_000, links: 0)
        ])
        let viewModel = makeViewModel(docker: docker)

        await viewModel.refreshFullInventory(projects: [makeProject(named: "aqua-pura")])
        await viewModel.executeReclaim()

        XCTAssertTrue(docker.prunedBuildCache)
        XCTAssertTrue(docker.prunedImages)
        XCTAssertEqual(docker.removedVolumes, ["westlife_project_mutagen"])
    }

    func testEmptyProjectListReclaimsNoVolumes() async {
        // Pins the interaction discovered while writing the test above: `ReclaimPlanner`
        // treats an empty project list as untrustworthy (indistinguishable from a failed
        // `ddev list`) and refuses to offer any volume for removal, even one that would
        // otherwise look orphaned. This must hold at the view-model layer too, not just
        // inside the planner — a regression here would silently start removing volumes
        // whenever the project list failed to load.
        let docker = FakeDockerSystemService()
        docker.usageResult = .success(DockerUsage(
            images: DockerUsageCategory(totalCount: 5, active: 1, sizeBytes: 10_000, reclaimableBytes: 5_000),
            containers: DockerUsageCategory(totalCount: 0, active: 0, sizeBytes: 0, reclaimableBytes: 0),
            volumes: DockerUsageCategory(totalCount: 0, active: 0, sizeBytes: 0, reclaimableBytes: 0),
            buildCache: DockerUsageCategory(totalCount: 3, active: 0, sizeBytes: 2_000, reclaimableBytes: 2_000)
        ))
        docker.volumesResult = .success([
            DockerVolume(name: "westlife_project_mutagen", sizeBytes: 1_000, links: 0)
        ])
        let viewModel = makeViewModel(docker: docker)

        await viewModel.refreshFullInventory(projects: [])
        await viewModel.executeReclaim()

        XCTAssertTrue(docker.prunedBuildCache)
        XCTAssertTrue(docker.prunedImages)
        XCTAssertTrue(docker.removedVolumes.isEmpty, "an untrustworthy (empty) project list must never yield a volume removal")
    }

    func testErrorMessageIsSetWhenInventoryFails() async {
        struct Boom: Error {}
        let docker = FakeDockerSystemService()
        docker.usageResult = .failure(Boom())
        let viewModel = makeViewModel(docker: docker)

        await viewModel.refreshFullInventory(projects: [])

        XCTAssertNotNil(viewModel.errorMessage)
    }

    // MARK: - Threshold clamping

    // Preferences impose no range or ordering validation on these values before they reach
    // the view model, so the view model itself must defend against nonsensical input.

    func testZeroOrNegativeWarnThresholdIsClamped() async {
        // Unclamped, a warn threshold of 0 (or below) would mean "warn always", since
        // `usedFraction` is never negative. Confirm a modest, realistic usage level still
        // reads as `.normal` once the threshold is clamped into range.
        let docker = FakeDockerSystemService()
        docker.headroomResult = .success(
            DockerHeadroom(totalBytes: 1000, usedBytes: 300, availableBytes: 700)  // 30%
        )
        let viewModel = DockerDiskViewModel(dockerService: docker, warnThreshold: -1.0, criticalThreshold: 0.93)

        await viewModel.refreshHeadroom()

        XCTAssertEqual(viewModel.alertLevel, .normal)
    }

    func testThresholdAboveOneIsClamped() async {
        // `usedFraction` never exceeds 1.0, so a threshold above 1.0 would unclamped mean
        // "never warn". Confirm a near-full disk still raises `.critical` once clamped.
        let docker = FakeDockerSystemService()
        docker.headroomResult = .success(
            DockerHeadroom(totalBytes: 1000, usedBytes: 990, availableBytes: 10)  // 99%
        )
        let viewModel = DockerDiskViewModel(dockerService: docker, warnThreshold: 1.4, criticalThreshold: 2.0)

        await viewModel.refreshHeadroom()

        XCTAssertEqual(viewModel.alertLevel, .critical)
    }

    func testWarnGreaterThanCriticalIsCorrected() async {
        // warn > critical is incoherent — warning must fire before critical. The view model
        // treats the pair as transposed and swaps them, which preserves a genuine warning
        // band instead of collapsing both thresholds to the same value.
        let docker = FakeDockerSystemService()
        docker.headroomResult = .success(
            DockerHeadroom(totalBytes: 1000, usedBytes: 800, availableBytes: 200)  // 80%
        )
        let viewModel = DockerDiskViewModel(dockerService: docker, warnThreshold: 0.95, criticalThreshold: 0.7)

        await viewModel.refreshHeadroom()

        XCTAssertEqual(
            viewModel.alertLevel, .warning,
            "swapping the transposed thresholds should put 80% usage in the warning band (0.7–0.95)"
        )
    }
}
