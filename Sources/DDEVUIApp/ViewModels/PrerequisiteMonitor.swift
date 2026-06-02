import Foundation
import Observation

@MainActor
@Observable
public final class PrerequisiteMonitor {
    public private(set) var state: PrerequisiteState = .initial
    public private(set) var isLaunching = false
    public private(set) var launchErrorMessage: String?

    /// Output of the last `ddev utility dockercheck` run (B7), shown when the user troubleshoots a
    /// Docker that's installed but won't come ready. `nil` until run for the first time.
    public private(set) var dockerCheckReport: DockerCheckReport?
    public private(set) var isRunningDockerCheck = false

    public let pollInterval: Duration
    private let service: PrerequisiteChecking
    @ObservationIgnored private var pollTask: Task<Void, Never>?

    public init(
        service: PrerequisiteChecking = WorkspacePrerequisiteService(),
        pollInterval: Duration = .seconds(5)
    ) {
        self.service = service
        self.pollInterval = pollInterval
    }

    public func start() {
        guard pollTask == nil else { return }
        pollTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                await self.refresh()
                guard !Task.isCancelled else { return }
                // Stop polling once everything is healthy — no point spawning docker/ddev
                // subprocesses forever after the gate is cleared. Clearing pollTask lets
                // start() re-arm on demand (e.g. when the scene returns to the foreground).
                if self.state.allSatisfied {
                    self.pollTask = nil
                    return
                }
                try? await Task.sleep(for: self.pollInterval)
            }
        }
    }

    public func stop() {
        pollTask?.cancel()
        pollTask = nil
    }

    public func refresh() async {
        let newState = await service.check()
        guard !Task.isCancelled else { return }
        state = newState
    }

    public func launch(_ runtime: DockerRuntime) async {
        isLaunching = true
        launchErrorMessage = nil
        do {
            try await service.launch(runtime)
        } catch {
            launchErrorMessage = "Couldn't start \(runtime.displayName): \(error.presentableMessage)"
        }
        await refresh()
        isLaunching = false
    }

    /// Runs `ddev utility dockercheck` and stores the report so the sheet can show why Docker
    /// isn't healthy (B7). Best-effort: the service never throws here — failures come back as a
    /// report flagged `succeeded: false` with the diagnostic text.
    public func runDockerCheck() async {
        isRunningDockerCheck = true
        dockerCheckReport = await service.dockerCheck()
        isRunningDockerCheck = false
    }

    public var shouldBlockUI: Bool {
        !state.isStillChecking && !state.allSatisfied
    }

    deinit {
        pollTask?.cancel()
    }
}
