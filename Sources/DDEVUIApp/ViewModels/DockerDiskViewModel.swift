import Foundation
import Observation

/// The view model's view of `DockerSystemService`, declared here so tests can substitute a
/// fake. Mirrors how `DDEVServicing` is declared alongside `ProjectDashboardViewModel`.
public protocol DockerSystemServicing: Sendable {
    func usage() async throws -> DockerUsage
    func headroom() async throws -> DockerHeadroom
    func volumes() async throws -> [DockerVolume]
    func pruneBuildCache() async throws -> CommandResult
    func pruneUnusedImages() async throws -> CommandResult
    func removeVolumes(_ names: [String]) async -> [VolumeRemovalResult]
}

extension DockerSystemService: DockerSystemServicing {}

public enum DiskAlertLevel: Equatable, Sendable {
    case normal
    case warning
    case critical
}

@MainActor
@Observable
public final class DockerDiskViewModel {
    /// Disk-usage thresholds are only meaningful somewhere in the 50%–99% band: below 50%
    /// there is nothing worth flagging, and at (or above) 100% the alert could never fire
    /// since `usedFraction` never reaches it.
    private static let minThreshold = 0.5
    private static let maxThreshold = 0.99

    public private(set) var headroom: DockerHeadroom?
    public private(set) var usage: DockerUsage?
    public private(set) var inventory: [ClassifiedVolume] = []
    public private(set) var plan: ReclaimPlan = ReclaimPlan(items: [])
    public private(set) var isLoadingInventory = false
    public private(set) var isReclaiming = false
    public private(set) var errorMessage: String?
    public private(set) var lastReclaimSummary: String?

    @ObservationIgnored private let dockerService: DockerSystemServicing
    @ObservationIgnored private let ddevService: DDEVServicing?
    @ObservationIgnored private let scheduler: CommandScheduler?
    @ObservationIgnored private let warnThreshold: Double
    @ObservationIgnored private let criticalThreshold: Double

    public init(
        dockerService: DockerSystemServicing = DockerSystemService(),
        ddevService: DDEVServicing? = nil,
        scheduler: CommandScheduler? = nil,
        warnThreshold: Double = 0.85,
        criticalThreshold: Double = 0.93
    ) {
        self.dockerService = dockerService
        self.ddevService = ddevService
        self.scheduler = scheduler

        // Preferences impose no range or ordering validation upstream, so a stray 0, a
        // negative number, or something above 1.0 must not reach `alertLevel` unclamped.
        // Once each value is in range, `warn > critical` is still incoherent — warning
        // should always fire before critical — so treat that as the pair being transposed
        // and swap them. Swapping (rather than collapsing both to one value) preserves a
        // genuine warning band instead of making `.warning` unreachable.
        let clampedWarn = Self.clampToRange(warnThreshold)
        let clampedCritical = Self.clampToRange(criticalThreshold)
        if clampedWarn > clampedCritical {
            self.warnThreshold = clampedCritical
            self.criticalThreshold = clampedWarn
        } else {
            self.warnThreshold = clampedWarn
            self.criticalThreshold = clampedCritical
        }
    }

    private static func clampToRange(_ value: Double) -> Double {
        min(max(value, minThreshold), maxThreshold)
    }

    /// `.normal` whenever headroom is unknown. An unmeasurable disk must never raise an
    /// alert — a failed probe is not evidence of a full disk.
    public var alertLevel: DiskAlertLevel {
        guard let headroom else { return .normal }
        if headroom.usedFraction >= criticalThreshold { return .critical }
        if headroom.usedFraction >= warnThreshold { return .warning }
        return .normal
    }

    /// Cheap enough for the background refresh cycle.
    public func refreshHeadroom() async {
        do {
            headroom = try await dockerService.headroom()
        } catch {
            // Deliberately silent: Docker may simply not be running. Clearing the value keeps
            // `alertLevel` at `.normal` rather than reporting a false emergency.
            headroom = nil
        }
    }

    /// Expensive — walks every volume. Call only when the screen is open or on explicit refresh.
    public func refreshFullInventory(projects: [DDEVProject]) async {
        isLoadingInventory = true
        errorMessage = nil
        defer { isLoadingInventory = false }

        do {
            async let usageTask = dockerService.usage()
            async let volumesTask = dockerService.volumes()
            let (loadedUsage, loadedVolumes) = try await (usageTask, volumesTask)

            usage = loadedUsage
            inventory = ReclaimPlanner.classify(volumes: loadedVolumes, projects: projects)
            plan = ReclaimPlanner.plan(volumes: loadedVolumes, projects: projects, usage: loadedUsage)
            await refreshHeadroom()
        } catch {
            errorMessage = error.presentableMessage
        }
    }

    /// Runs every action in the current plan. Individual failures are collected rather than
    /// aborting the batch.
    public func executeReclaim() async {
        guard !plan.isEmpty else { return }
        isReclaiming = true
        errorMessage = nil
        defer { isReclaiming = false }

        var failures: [String] = []
        var volumeNames: [String] = []

        for item in plan.items {
            switch item.action {
            case .buildCache:
                await record(&failures, item.label) { [dockerService] in
                    _ = try await dockerService.pruneBuildCache()
                }
            case .unusedImages:
                await record(&failures, item.label) { [dockerService] in
                    _ = try await dockerService.pruneUnusedImages()
                }
            case let .mutagenReset(_, appRoot):
                await record(&failures, item.label) { [ddevService] in
                    guard let ddevService else { return }
                    _ = try await ddevService.mutagen(.reset, in: appRoot)
                }
            case let .removeVolume(name):
                volumeNames.append(name)
            }
        }

        if !volumeNames.isEmpty {
            let results = await dockerService.removeVolumes(volumeNames)
            failures.append(contentsOf: results.filter { !$0.succeeded }.map(\.name))
        }

        lastReclaimSummary = failures.isEmpty
            ? "Reclaimed \(plan.totalBytes.formattedBytes)."
            : "Reclaimed with \(failures.count) failure(s): \(failures.joined(separator: ", "))."

        await refreshHeadroom()
    }

    /// Explicit per-item removal — the only route by which a registered project's database
    /// can be deleted.
    public func removeVolume(named name: String) async {
        isReclaiming = true
        defer { isReclaiming = false }

        let results = await dockerService.removeVolumes([name])
        if let failure = results.first(where: { !$0.succeeded }) {
            errorMessage = failure.message ?? "Could not remove \(name)."
        }
        await refreshHeadroom()
    }

    /// Maintenance action — this *consumes* disk rather than reclaiming it.
    public func prefetchImages() async {
        guard let ddevService else { return }
        isReclaiming = true
        errorMessage = nil
        defer { isReclaiming = false }
        do {
            _ = try await ddevService.downloadImages()
        } catch {
            errorMessage = error.presentableMessage
        }
    }

    /// Runs one reclaim step, funnelled through the scheduler when one is supplied, and
    /// records the item's label as a failure rather than aborting the whole batch.
    ///
    /// Takes `@escaping @Sendable` rather than the brief's plain closure: a non-escaping,
    /// non-`Sendable` closure cannot be passed into `CommandScheduler.run`, which requires
    /// `@Sendable () async throws -> T` under Swift 6 strict concurrency. Call sites above
    /// capture only `Sendable` values (`dockerService`, `ddevService`, `appRoot`), so marking
    /// the closures `@Sendable` costs nothing.
    private func record(
        _ failures: inout [String],
        _ label: String,
        _ operation: @escaping @Sendable () async throws -> Void
    ) async {
        do {
            if let scheduler {
                try await scheduler.run(operation)
            } else {
                try await operation()
            }
        } catch {
            failures.append(label)
        }
    }
}
