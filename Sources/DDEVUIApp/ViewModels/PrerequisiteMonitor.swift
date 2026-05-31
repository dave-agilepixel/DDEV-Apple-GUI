import Foundation
import Observation

@MainActor
@Observable
public final class PrerequisiteMonitor {
    public private(set) var state: PrerequisiteState = .initial
    public private(set) var isLaunching = false
    public private(set) var launchErrorMessage: String?

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

    public var shouldBlockUI: Bool {
        !state.isStillChecking && !state.allSatisfied
    }

    deinit {
        pollTask?.cancel()
    }
}
