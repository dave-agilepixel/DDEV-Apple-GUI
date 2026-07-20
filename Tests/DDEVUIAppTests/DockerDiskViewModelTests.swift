import XCTest
@testable import DDEVUIApp

/// A minimal reusable one-shot gate: while armed, `wait()` suspends the caller until
/// `release()` is called. Used by the re-entrancy tests below to get a deterministic window in
/// which a second, overlapping call can be issued — instead of racing on `Task` scheduling
/// order, which this codebase's own concurrency tests note is unreliable (see
/// `GatedDDEVService` in `ProjectConcurrencyTests.swift`).
private final class Gate: @unchecked Sendable {
    private var waiters: [CheckedContinuation<Void, Never>] = []
    var isArmed = false
    var waiterCount: Int { waiters.count }

    func wait() async {
        guard isArmed else { return }
        await withCheckedContinuation { waiters.append($0) }
    }

    /// Busy-waits, bounded, until at least `count` callers are parked in `wait()`. Bounded
    /// rather than unconditional so a scenario where the expected count is never reached (e.g.
    /// a re-entrancy guard correctly stopping a second caller before it reaches the gate) cannot
    /// hang the test — it simply falls through after `maxAttempts` yields.
    func waitForWaiters(atLeast count: Int, maxAttempts: Int = 1000) async {
        for _ in 0..<maxAttempts where waiterCount < count {
            await Task.yield()
        }
    }

    func release() {
        isArmed = false
        let toResume = waiters
        waiters = []
        toResume.forEach { $0.resume() }
    }
}

private final class FakeDockerSystemService: DockerSystemServicing, @unchecked Sendable {
    var headroomResult: Result<DockerHeadroom, Error> = .success(
        DockerHeadroom(totalBytes: 100_000, usedBytes: 50_000, availableBytes: 50_000)
    )
    var usageResult: Result<DockerUsage, Error>
    var volumesResult: Result<[DockerVolume], Error> = .success([])
    var pruneBuildCacheResult: Result<CommandResult, Error> = .success(.success())
    var pruneUnusedImagesResult: Result<CommandResult, Error> = .success(.success())
    /// Volume names that should report a failed removal; every other name succeeds.
    var volumeNamesToFail: Set<String> = []

    /// Gates entry to `pruneBuildCache()` / `removeVolumes(_:)` respectively, for the
    /// re-entrancy tests. Left un-armed (a no-op) for every other test.
    let pruneBuildCacheGate = Gate()
    let removeVolumesGate = Gate()
    /// Gates entry to `headroom(allowingProbeVolume:)`, so the periodic-loop tests can park a
    /// tick and count how many loops are actually running. Left un-armed for every other test.
    let headroomGate = Gate()

    /// Every `allowingProbeVolume` argument seen, in call order. The expensive probe fallback
    /// only runs when this is `true`, so a periodic caller must never appear here as `true`.
    private(set) var headroomProbeAllowed: [Bool] = []

    private(set) var prunedBuildCache = false
    private(set) var prunedImages = false
    private(set) var removedVolumes: [String] = []
    private(set) var pruneBuildCacheCallCount = 0
    private(set) var removeVolumesCallCount = 0
    private(set) var headroomCallCount = 0

    init() {
        let zero = DockerUsageCategory(totalCount: 0, active: 0, sizeBytes: 0, reclaimableBytes: 0)
        usageResult = .success(DockerUsage(images: zero, containers: zero, volumes: zero, buildCache: zero))
    }

    func usage() async throws -> DockerUsage { try usageResult.get() }

    func headroom(allowingProbeVolume: Bool) async throws -> DockerHeadroom {
        headroomCallCount += 1
        headroomProbeAllowed.append(allowingProbeVolume)
        await headroomGate.wait()
        return try headroomResult.get()
    }

    func volumes() async throws -> [DockerVolume] { try volumesResult.get() }

    func pruneBuildCache() async throws -> CommandResult {
        prunedBuildCache = true
        pruneBuildCacheCallCount += 1
        await pruneBuildCacheGate.wait()
        return try pruneBuildCacheResult.get()
    }

    func pruneUnusedImages() async throws -> CommandResult {
        prunedImages = true
        return try pruneUnusedImagesResult.get()
    }

    func removeVolumes(_ names: [String]) async -> [VolumeRemovalResult] {
        removeVolumesCallCount += 1
        await removeVolumesGate.wait()
        removedVolumes.append(contentsOf: names)
        return names.map { name in
            let succeeded = !volumeNamesToFail.contains(name)
            return VolumeRemovalResult(
                name: name,
                succeeded: succeeded,
                message: succeeded ? nil : "Simulated failure removing \(name)."
            )
        }
    }
}

/// Minimal `DDEVServicing` conformer. `DockerDiskViewModel` only ever calls `downloadImages()`
/// (via `prefetchImages()`) and `mutagen(_:in:)` (for a `.mutagenReset` plan item) — both are
/// implemented and configurable here. Every other requirement is a `fatalError` tripwire so an
/// unexpected call surfaces immediately instead of silently returning a placeholder.
private final class FakeDDEVService: DDEVServicing, @unchecked Sendable {
    var downloadImagesResult: Result<CommandResult, Error> = .success(.success())
    var mutagenResult: Result<CommandResult, Error> = .success(.success())
    private(set) var downloadImagesCallCount = 0
    private(set) var mutagenCallCount = 0

    func downloadImages() async throws -> CommandResult {
        downloadImagesCallCount += 1
        return try downloadImagesResult.get()
    }

    /// Overridable rather than a `fatalError` tripwire, unlike the rest: `executeReclaim`
    /// genuinely routes `.mutagenReset` plan items here, and the F3 tests need to make it fail.
    func mutagen(_ command: DDEVMutagenCommand, in appRoot: String) async throws -> CommandResult {
        mutagenCallCount += 1
        return try mutagenResult.get()
    }

    private func unused(_ function: String = #function) -> Never {
        fatalError("\(function) is not used by DockerDiskViewModelTests")
    }

    func listProjects() async throws -> [DDEVProject] { unused() }
    func describe(projectName: String) async throws -> DDEVProjectDetails { unused() }
    func start(projectName: String) async throws -> CommandResult { unused() }
    func stop(projectName: String) async throws -> CommandResult { unused() }
    func restart(projectName: String) async throws -> CommandResult { unused() }
    func unlink(projectName: String) async throws -> CommandResult { unused() }
    func deleteDDEVData(projectName: String) async throws -> CommandResult { unused() }
    func startProject(in appRoot: String) async throws -> CommandResult { unused() }
    func configureProject(in appRoot: String, name: String, type: DDEVProjectType, docroot: String) async throws -> CommandResult { unused() }
    func setPHPVersion(_ version: String, in appRoot: String) async throws -> CommandResult { unused() }
    func launchDatabaseTool(_ tool: DDEVDatabaseTool, in appRoot: String) async throws -> CommandResult { unused() }
    func importDatabase(_ options: DDEVDatabaseImportOptions, in appRoot: String) async throws -> CommandResult { unused() }
    func importFiles(_ options: DDEVImportFilesOptions, in appRoot: String) async throws -> CommandResult { unused() }
    func exportDatabase(_ options: DDEVDatabaseExportOptions, in appRoot: String) async throws -> CommandResult { unused() }
    func createSnapshot(name: String?, in appRoot: String) async throws -> CommandResult { unused() }
    func listSnapshots(in appRoot: String) async throws -> CommandResult { unused() }
    func restoreSnapshot(named snapshotName: String, in appRoot: String) async throws -> CommandResult { unused() }
    func restoreLatestSnapshot(in appRoot: String) async throws -> CommandResult { unused() }
    func cleanupSnapshots(in appRoot: String) async throws -> CommandResult { unused() }
    func cleanupSnapshot(named snapshotName: String, in appRoot: String) async throws -> CommandResult { unused() }
    func logs(projectName: String, service: String, tail: Int, includeTimestamps: Bool, in appRoot: String) async throws -> CommandResult { unused() }
    func listInstalledAddOns(projectName: String, in appRoot: String) async throws -> CommandResult { unused() }
    func searchAddOns(query: String, in appRoot: String) async throws -> CommandResult { unused() }
    func listAllAddOns() async throws -> [DDEVAddon] { unused() }
    func getAddOn(_ repository: String, projectName: String, in appRoot: String) async throws -> CommandResult { unused() }
    func removeAddOn(named name: String, projectName: String, in appRoot: String) async throws -> CommandResult { unused() }
    func applyConfigChange(_ change: DDEVConfigChange, in appRoot: String) async throws -> CommandResult { unused() }
    func runProjectCommand(arguments: [String], in appRoot: String) async throws -> CommandResult { unused() }
    func exec(command: String, service: DDEVExecService, in appRoot: String) async throws -> CommandResult { unused() }
    func version() async throws -> CommandResult { unused() }
    func versionInfo() async throws -> DDEVVersionInfo { unused() }
    func poweroff() async throws -> CommandResult { unused() }
    func deleteImages() async throws -> CommandResult { unused() }
    func globalConfig() async throws -> DDEVGlobalConfig { unused() }
    func applyGlobalConfig(_ changes: [DDEVGlobalConfigChange]) async throws -> CommandResult { unused() }
    func utilityDiagnose(in appRoot: String?) async throws -> CommandResult { unused() }
    func utilityConfigYAML(omitKeys: [String], in appRoot: String) async throws -> CommandResult { unused() }
    func utilityCheckCustomConfig(in appRoot: String) async throws -> CommandResult { unused() }
    func utilityCheckDBMatch(in appRoot: String) async throws -> CommandResult { unused() }
    func migrateDatabase(to type: DDEVDatabaseType, version: String, in appRoot: String) async throws -> CommandResult { unused() }
    func xhgui(_ command: DDEVXHGuiCommand, in appRoot: String) async throws -> CommandResult { unused() }
    func xdebug(_ command: DDEVXdebugCommand, in appRoot: String) async throws -> CommandResult { unused() }
    func updateWordPressCore(in appRoot: String) async throws -> CommandResult { unused() }
    func updateWordPressPlugins(in appRoot: String) async throws -> CommandResult { unused() }
    func updateWordPressThemes(in appRoot: String) async throws -> CommandResult { unused() }
    func configureWordPressMultisite(_ options: WordPressMultisiteOptions, in appRoot: String) async throws -> CommandResult { unused() }
    func share(in appRoot: String, onOutputLine: (@Sendable (String) -> Void)?) async throws -> CommandResult { unused() }
}

@MainActor
final class DockerDiskViewModelTests: XCTestCase {

    private func makeViewModel(
        docker: FakeDockerSystemService = FakeDockerSystemService(),
        // A fake, never `nil` and never the real `DDEVCommandService` the view model now
        // defaults to — these tests must not spawn `ddev` subprocesses.
        ddevService: DDEVServicing = FakeDDEVService(),
        scheduler: CommandScheduler? = nil
    ) -> DockerDiskViewModel {
        DockerDiskViewModel(
            dockerService: docker,
            ddevService: ddevService,
            scheduler: scheduler,
            warnThreshold: 0.85,
            criticalThreshold: 0.93
        )
    }

    /// Configures `docker` so `refreshFullInventory` + `executeReclaim` produce a plan with all
    /// three usage-derived/volume actions this suite exercises: build cache, unused images, and
    /// one orphaned volume ripe for removal. Mirrors `testExecuteReclaimRunsPlannedActions`'s
    /// setup so the re-entrancy and failure-path tests below drive a realistic, non-trivial plan.
    private func configureReclaimablePlan(on docker: FakeDockerSystemService, volumeName: String = "westlife_project_mutagen") {
        docker.usageResult = .success(DockerUsage(
            images: DockerUsageCategory(totalCount: 5, active: 1, sizeBytes: 10_000, reclaimableBytes: 5_000),
            containers: DockerUsageCategory(totalCount: 0, active: 0, sizeBytes: 0, reclaimableBytes: 0),
            volumes: DockerUsageCategory(totalCount: 0, active: 0, sizeBytes: 0, reclaimableBytes: 0),
            buildCache: DockerUsageCategory(totalCount: 3, active: 0, sizeBytes: 2_000, reclaimableBytes: 2_000)
        ))
        docker.volumesResult = .success([
            DockerVolume(name: volumeName, sizeBytes: 1_000, links: 0)
        ])
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

    // MARK: - Re-entrancy (finding 1)

    func testExecuteReclaimIsNotReentrant() async {
        let docker = FakeDockerSystemService()
        configureReclaimablePlan(on: docker)
        let viewModel = makeViewModel(docker: docker)
        await viewModel.refreshFullInventory(projects: [makeProject(named: "aqua-pura")])

        docker.pruneBuildCacheGate.isArmed = true
        async let first: Void = viewModel.executeReclaim()
        // Wait until the first call is genuinely mid-flight (parked inside `pruneBuildCache`)
        // before issuing the second, so the overlap is real rather than assumed.
        await docker.pruneBuildCacheGate.waitForWaiters(atLeast: 1)

        async let second: Void = viewModel.executeReclaim()
        // Give the second call a bounded window to either bail out at the re-entrancy guard
        // (expected) or, if the guard were missing, to reach the gate itself.
        await docker.pruneBuildCacheGate.waitForWaiters(atLeast: 2, maxAttempts: 50)

        docker.pruneBuildCacheGate.release()
        _ = await (first, second)

        XCTAssertEqual(docker.pruneBuildCacheCallCount, 1, "a concurrent call must not re-run the batch")
        XCTAssertEqual(docker.removeVolumesCallCount, 1, "a concurrent call must not re-issue volume removal")
        XCTAssertEqual(docker.removedVolumes, ["westlife_project_mutagen"])
        XCTAssertFalse(viewModel.isReclaiming)
    }

    func testRemoveVolumeIsNotReentrant() async {
        let docker = FakeDockerSystemService()
        let viewModel = makeViewModel(docker: docker)

        docker.removeVolumesGate.isArmed = true
        async let first: Void = viewModel.removeVolume(named: "orphan_volume")
        await docker.removeVolumesGate.waitForWaiters(atLeast: 1)

        async let second: Void = viewModel.removeVolume(named: "orphan_volume")
        await docker.removeVolumesGate.waitForWaiters(atLeast: 2, maxAttempts: 50)

        docker.removeVolumesGate.release()
        _ = await (first, second)

        XCTAssertEqual(docker.removeVolumesCallCount, 1, "a concurrent call must not re-run the removal")
        XCTAssertEqual(docker.removedVolumes, ["orphan_volume"])
        XCTAssertFalse(viewModel.isReclaiming)
    }

    // MARK: - Failure paths (finding 2)

    func testPruneFailureDoesNotAbortBatch() async {
        struct Boom: Error {}
        let docker = FakeDockerSystemService()
        configureReclaimablePlan(on: docker)
        docker.pruneBuildCacheResult = .failure(Boom())
        let viewModel = makeViewModel(docker: docker)
        await viewModel.refreshFullInventory(projects: [makeProject(named: "aqua-pura")])

        await viewModel.executeReclaim()

        XCTAssertTrue(docker.prunedImages, "a build-cache failure must not stop the rest of the batch")
        XCTAssertEqual(docker.removedVolumes, ["westlife_project_mutagen"], "volumes must still be removed")
        XCTAssertEqual(
            viewModel.lastReclaimSummary, "Reclaimed with 1 failure(s): Build cache.",
            "the one failure must be named, not silently dropped"
        )
    }

    func testVolumeRemovalFailureReflectedInSummary() async {
        let docker = FakeDockerSystemService()
        configureReclaimablePlan(on: docker)
        docker.volumeNamesToFail = ["westlife_project_mutagen"]
        let viewModel = makeViewModel(docker: docker)
        await viewModel.refreshFullInventory(projects: [makeProject(named: "aqua-pura")])

        await viewModel.executeReclaim()

        XCTAssertTrue(docker.prunedBuildCache)
        XCTAssertTrue(docker.prunedImages)
        let summary = try? XCTUnwrap(viewModel.lastReclaimSummary)
        XCTAssertTrue(
            summary?.contains("westlife_project_mutagen") ?? false,
            "the failed volume must be named in the summary"
        )
        XCTAssertFalse(
            summary?.hasPrefix("Reclaimed an estimated") ?? true,
            "a partial failure must not be reported as a clean success"
        )
    }

    func testRemoveVolumeSucceedsAndClearsStaleError() async {
        let docker = FakeDockerSystemService()
        docker.usageResult = .failure(NSError(domain: "test", code: 1))
        let viewModel = makeViewModel(docker: docker)
        // Seed a stale error from an earlier, unrelated failure.
        await viewModel.refreshFullInventory(projects: [])
        XCTAssertNotNil(viewModel.errorMessage, "precondition: an error is already showing")

        docker.volumeNamesToFail = []
        await viewModel.removeVolume(named: "orphan_volume")

        XCTAssertEqual(docker.removedVolumes, ["orphan_volume"])
        XCTAssertNil(viewModel.errorMessage, "a successful removal must clear a stale error from a prior operation")
    }

    func testRemoveVolumeFailureSetsErrorMessage() async {
        let docker = FakeDockerSystemService()
        docker.volumeNamesToFail = ["orphan_volume"]
        let viewModel = makeViewModel(docker: docker)

        await viewModel.removeVolume(named: "orphan_volume")

        XCTAssertEqual(docker.removedVolumes, ["orphan_volume"])
        XCTAssertNotNil(viewModel.errorMessage)
    }

    func testPrefetchImagesSucceeds() async {
        let docker = FakeDockerSystemService()
        let ddevService = FakeDDEVService()
        let viewModel = makeViewModel(docker: docker, ddevService: ddevService)

        await viewModel.prefetchImages()

        XCTAssertEqual(ddevService.downloadImagesCallCount, 1)
        XCTAssertNil(viewModel.errorMessage)
        XCTAssertFalse(viewModel.isReclaiming)
    }

    func testPrefetchImagesFailureSetsErrorMessage() async {
        struct Boom: Error {}
        let docker = FakeDockerSystemService()
        let ddevService = FakeDDEVService()
        ddevService.downloadImagesResult = .failure(Boom())
        let viewModel = makeViewModel(docker: docker, ddevService: ddevService)

        await viewModel.prefetchImages()

        XCTAssertEqual(ddevService.downloadImagesCallCount, 1)
        XCTAssertNotNil(viewModel.errorMessage)
        XCTAssertFalse(viewModel.isReclaiming)
    }

    func testExecuteReclaimUsesSchedulerWhenProvided() async {
        let docker = FakeDockerSystemService()
        configureReclaimablePlan(on: docker)
        let scheduler = CommandScheduler(maxConcurrent: 1)
        let viewModel = makeViewModel(docker: docker, scheduler: scheduler)
        await viewModel.refreshFullInventory(projects: [makeProject(named: "aqua-pura")])
        let expectedBytes = viewModel.plan.totalBytes

        await viewModel.executeReclaim()

        // Exercises the `scheduler.run(operation)` branch inside `record` end-to-end (rather
        // than merely compiling it): the batch must still complete correctly when funnelled
        // through a real `CommandScheduler`.
        XCTAssertTrue(docker.prunedBuildCache)
        XCTAssertTrue(docker.prunedImages)
        XCTAssertEqual(docker.removedVolumes, ["westlife_project_mutagen"])
        XCTAssertEqual(viewModel.lastReclaimSummary, "Reclaimed an estimated \(expectedBytes.formattedBytes).")
    }

    // MARK: - F2: volume removal is scheduled too

    /// `executeReclaim`'s prunes went through `record` (and so through the scheduler), but its
    /// volume removals called `dockerService.removeVolumes` directly, bypassing it entirely — so
    /// the destructive half of reclaim could still interleave with a project start/stop. Prove
    /// the scheduler is now genuinely in the path by holding its only permit: the removal must
    /// not reach Docker until the permit is released.
    func testRemoveVolumeGoesThroughTheSchedulerWhenProvided() async throws {
        let docker = FakeDockerSystemService()
        let scheduler = CommandScheduler(maxConcurrent: 1)
        let viewModel = makeViewModel(docker: docker, scheduler: scheduler)

        try await scheduler.acquire()  // hold the only permit, as a project start would

        let removal = Task { await viewModel.removeVolume(named: "westlife-mariadb") }
        for _ in 0..<200 where docker.removeVolumesCallCount == 0 {
            await Task.yield()
        }
        XCTAssertEqual(
            docker.removeVolumesCallCount, 0,
            "removal must wait for a scheduler permit rather than bypassing it"
        )

        await scheduler.release()
        await removal.value

        XCTAssertEqual(docker.removedVolumes, ["westlife-mariadb"], "and must still run once the permit frees")
        XCTAssertNil(viewModel.errorMessage)
    }

    /// The same for the bulk path's volume removals.
    func testExecuteReclaimVolumeRemovalGoesThroughTheScheduler() async throws {
        let docker = FakeDockerSystemService()
        configureReclaimablePlan(on: docker)
        let scheduler = CommandScheduler(maxConcurrent: 1)
        let viewModel = makeViewModel(docker: docker, scheduler: scheduler)
        await viewModel.refreshFullInventory(projects: [makeProject(named: "aqua-pura")])

        try await scheduler.acquire()

        let reclaim = Task { await viewModel.executeReclaim() }
        for _ in 0..<200 where docker.removeVolumesCallCount == 0 {
            await Task.yield()
        }
        XCTAssertEqual(docker.removeVolumesCallCount, 0, "bulk removal must also wait on the scheduler")
        XCTAssertFalse(docker.prunedBuildCache, "and so must the prunes")

        await scheduler.release()
        await reclaim.value

        XCTAssertEqual(docker.removedVolumes, ["westlife_project_mutagen"])
    }

    /// Without a scheduler the un-scheduled branch must still work — tests rely on it, and it
    /// is the only path that does not require an injected actor.
    func testRemoveVolumeWorksWithoutAScheduler() async {
        let docker = FakeDockerSystemService()
        let viewModel = makeViewModel(docker: docker)

        await viewModel.removeVolume(named: "westlife-mariadb")

        XCTAssertEqual(docker.removedVolumes, ["westlife-mariadb"])
    }

    // MARK: - F3: a failing DDEV service must not report a clean success

    /// Configures a plan containing exactly one `.mutagenReset` item: a registered, *stopped*
    /// project whose sync-cache volume exists.
    private func configureMutagenResetPlan(on docker: FakeDockerSystemService) {
        let zero = DockerUsageCategory(totalCount: 0, active: 0, sizeBytes: 0, reclaimableBytes: 0)
        docker.usageResult = .success(DockerUsage(images: zero, containers: zero, volumes: zero, buildCache: zero))
        docker.volumesResult = .success([
            DockerVolume(name: "aqua-pura_project_mutagen", sizeBytes: 24_000_000_000, links: 0)
        ])
    }

    private func stoppedProject(named name: String) -> DDEVProject {
        DDEVProject(
            name: name, appRoot: "/tmp/\(name)", shortRoot: "~/\(name)",
            status: .stopped, statusDescription: "stopped", projectType: .php, docroot: "",
            primaryURL: nil, httpURL: nil, httpsURL: nil, mailpitURL: nil, mailpitHTTPSURL: nil,
            xhguiURL: nil, xhguiHTTPSURL: nil, mutagenEnabled: true, mutagenStatus: nil
        )
    }

    /// The bug: `ddevService` was optional and the `.mutagenReset` branch did `guard let
    /// ddevService else { return }` — returning *without throwing*, so `record` counted the
    /// untouched reset as a success. `lastReclaimSummary` then claimed every sync-cache byte in
    /// the plan had been reclaimed. On the machine this was found on that was 24 GB reported as
    /// freed while nothing had happened. Whatever the reason the reset does not run, the summary
    /// must not claim a clean success.
    func testFailingDDEVServiceIsCountedAsAFailureNotAReclaim() async {
        struct Boom: Error {}
        let docker = FakeDockerSystemService()
        configureMutagenResetPlan(on: docker)
        let ddevService = FakeDDEVService()
        ddevService.mutagenResult = .failure(Boom())
        let viewModel = makeViewModel(docker: docker, ddevService: ddevService)
        await viewModel.refreshFullInventory(projects: [stoppedProject(named: "aqua-pura")])

        XCTAssertEqual(viewModel.plan.items.count, 1, "expected exactly one mutagen-reset item")
        let claimedBytes = viewModel.plan.totalBytes.formattedBytes

        await viewModel.executeReclaim()

        let summary = viewModel.lastReclaimSummary
        XCTAssertNotEqual(
            viewModel.lastReclaimSummary, "Reclaimed an estimated \(claimedBytes).",
            "a reset that did not happen must never be summarised as a clean reclaim"
        )
        XCTAssertEqual(
            viewModel.lastReclaimSummary,
            "Reclaimed with 1 failure(s): aqua-pura sync cache.",
            "unexpected summary: \(String(describing: summary))"
        )
    }

    /// The complement: when the reset genuinely succeeds, the clean summary is correct.
    func testSucceedingMutagenResetIsSummarisedAsAReclaim() async {
        let docker = FakeDockerSystemService()
        configureMutagenResetPlan(on: docker)
        let ddevService = FakeDDEVService()
        let viewModel = makeViewModel(docker: docker, ddevService: ddevService)
        await viewModel.refreshFullInventory(projects: [stoppedProject(named: "aqua-pura")])
        let expectedBytes = viewModel.plan.totalBytes

        await viewModel.executeReclaim()

        XCTAssertEqual(ddevService.mutagenCallCount, 1, "the reset must actually be attempted")
        XCTAssertEqual(
            viewModel.lastReclaimSummary,
            "Reclaimed an estimated \(expectedBytes.formattedBytes)."
        )
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
        let viewModel = DockerDiskViewModel(dockerService: docker, ddevService: FakeDDEVService(), warnThreshold: -1.0, criticalThreshold: 0.93)

        await viewModel.refreshHeadroom()

        XCTAssertEqual(viewModel.alertLevel, .normal)
    }

    func testThresholdAboveOneIsClamped() async {
        // `usedFraction` never exceeds 1.0, so a threshold above 1.0 would unclamped mean
        // "never warn". Confirm a near-full disk still raises `.critical` once clamped.
        let criticalDocker = FakeDockerSystemService()
        criticalDocker.headroomResult = .success(
            DockerHeadroom(totalBytes: 1000, usedBytes: 990, availableBytes: 10)  // 99%
        )
        let criticalViewModel = DockerDiskViewModel(dockerService: criticalDocker, ddevService: FakeDDEVService(), warnThreshold: 1.4, criticalThreshold: 2.0)

        await criticalViewModel.refreshHeadroom()

        XCTAssertEqual(criticalViewModel.alertLevel, .critical)

        // Both inputs clamp to the same ceiling (`maxThreshold`), so a naive clamp-then-swap
        // would collapse warn == critical and make `.warning` permanently unreachable — the
        // regression this test previously missed (see finding 3). Confirm a slightly lower
        // usage, still above the clamped warn threshold but below critical, reads as `.warning`.
        let warningDocker = FakeDockerSystemService()
        warningDocker.headroomResult = .success(
            DockerHeadroom(totalBytes: 1000, usedBytes: 985, availableBytes: 15)  // 98.5%
        )
        let warningViewModel = DockerDiskViewModel(dockerService: warningDocker, ddevService: FakeDDEVService(), warnThreshold: 1.4, criticalThreshold: 2.0)

        await warningViewModel.refreshHeadroom()

        XCTAssertEqual(
            warningViewModel.alertLevel, .warning,
            "clamping two out-of-range thresholds must still leave a reachable warning band"
        )
    }

    // MARK: - Periodic headroom refresh (Task 12)

    /// A second `startPeriodicHeadroomRefresh()` call must not start a second concurrent loop.
    /// `DockerDiskViewModel` is a single shared instance handed to every `ContentView` — unlike
    /// `@State`, which is scoped per window — so a missing guard here would double the call rate
    /// against the same shared instance whenever a second window is opened (Cmd+N), defeating the
    /// whole point of keeping this path to the cheap `headroom()` call. Mirrors
    /// `ProjectDashboardViewModelTests.testStatusPollingRefreshesWhileActiveAndStopsOnStop`'s
    /// magnitude-based approach: a short interval, a bounded wait, then a call-count check wide
    /// enough to absorb scheduling jitter but tight enough to catch an outright doubling.
    /// Deterministic rather than wall-clock: arm the headroom gate, let the loop tick into it,
    /// and count how many callers are parked. Exactly one loop parks exactly one caller; the
    /// regression this targets — a second `start()` spawning a concurrent second loop — would
    /// park two. `waitForWaiters(atLeast: 2)` is bounded, so the correct case falls through
    /// after its attempts rather than hanging.
    func testStartPeriodicHeadroomRefreshIsNotReentrant() async throws {
        let docker = FakeDockerSystemService()
        docker.headroomGate.isArmed = true
        let viewModel = makeViewModel(docker: docker)

        viewModel.startPeriodicHeadroomRefresh(interval: .zero)
        viewModel.startPeriodicHeadroomRefresh(interval: .zero) // must not start a second loop

        await docker.headroomGate.waitForWaiters(atLeast: 2)

        XCTAssertEqual(
            docker.headroomGate.waiterCount, 1,
            "a second start() call must not run a concurrent second loop"
        )

        viewModel.stopPeriodicHeadroomRefresh()
        docker.headroomGate.release()
    }

    /// F1 — the periodic loop must never be able to drive `headroomViaProbeVolume()`, which
    /// does `docker volume create` + `docker run --rm alpine df` + `docker volume rm`. On an
    /// idle machine the cheap `docker exec` path always fails (no container to exec into), so
    /// an unguarded loop falls through to that probe on *every* tick — launching a container
    /// every interval, forever. Passing `allowingProbeVolume: false` is what stops it, so
    /// assert on the argument rather than on a call count.
    func testPeriodicHeadroomRefreshNeverAllowsTheProbeVolume() async throws {
        let docker = FakeDockerSystemService()
        docker.headroomGate.isArmed = true
        let viewModel = makeViewModel(docker: docker)

        viewModel.startPeriodicHeadroomRefresh(interval: .zero)

        // Park the first tick deterministically, then let several more run through.
        await docker.headroomGate.waitForWaiters(atLeast: 1)
        docker.headroomGate.release()
        for _ in 0..<200 where docker.headroomCallCount < 5 {
            await Task.yield()
        }
        viewModel.stopPeriodicHeadroomRefresh()

        XCTAssertGreaterThan(docker.headroomCallCount, 0, "the loop must actually run")
        XCTAssertFalse(
            docker.headroomProbeAllowed.contains(true),
            "no periodic tick may permit the container-launching probe fallback"
        )
    }

    /// The other half of F1: an explicit, user-initiated refresh still gets a real measurement,
    /// probe fallback included. Restricting the periodic path must not quietly restrict this one.
    func testExplicitRefreshStillAllowsTheProbeVolume() async {
        let docker = FakeDockerSystemService()
        let viewModel = makeViewModel(docker: docker)

        await viewModel.refreshHeadroom()
        XCTAssertEqual(docker.headroomProbeAllowed, [true])

        await viewModel.refreshFullInventory(projects: [])
        XCTAssertEqual(
            docker.headroomProbeAllowed, [true, true],
            "opening the screen is an explicit refresh and must measure properly"
        )
    }

    func testStopPeriodicHeadroomRefreshHaltsPolling() async throws {
        let docker = FakeDockerSystemService()
        let viewModel = makeViewModel(docker: docker)

        viewModel.startPeriodicHeadroomRefresh(interval: .milliseconds(10))
        try await Task.sleep(for: .milliseconds(60))
        viewModel.stopPeriodicHeadroomRefresh()

        // Let any in-flight tick settle, snapshot, then confirm no further ticks land.
        try await Task.sleep(for: .milliseconds(20))
        let settled = docker.headroomCallCount
        try await Task.sleep(for: .milliseconds(80))
        XCTAssertEqual(docker.headroomCallCount, settled, "No further headroom polling after stop")
    }

    func testWarnGreaterThanCriticalIsCorrected() async {
        // warn > critical is incoherent — warning must fire before critical. The view model
        // treats the pair as transposed and swaps them, which preserves a genuine warning
        // band instead of collapsing both thresholds to the same value.
        let docker = FakeDockerSystemService()
        docker.headroomResult = .success(
            DockerHeadroom(totalBytes: 1000, usedBytes: 800, availableBytes: 200)  // 80%
        )
        let viewModel = DockerDiskViewModel(dockerService: docker, ddevService: FakeDDEVService(), warnThreshold: 0.95, criticalThreshold: 0.7)

        await viewModel.refreshHeadroom()

        XCTAssertEqual(
            viewModel.alertLevel, .warning,
            "swapping the transposed thresholds should put 80% usage in the warning band (0.7–0.95)"
        )
    }
}
