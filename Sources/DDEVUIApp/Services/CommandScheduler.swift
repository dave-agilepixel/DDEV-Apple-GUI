/// A FIFO async semaphore that bounds how many command operations run at once.
///
/// Has zero DDEV knowledge — it simply hands out a fixed number of permits and releases
/// blocked callers in arrival order. `ProjectDashboardViewModel` uses it to cap concurrent
/// project *mutations* (start/stop/restart/import/…) so a "start everything" burst does not
/// thrash Docker. Reads (logs/config/describe) bypass it entirely.
public actor CommandScheduler {
    private let maxConcurrent: Int
    private var available: Int

    private struct Waiter {
        let id: Int
        let continuation: CheckedContinuation<Void, Error>
    }
    private var waiters: [Waiter] = []
    private var nextWaiterID = 0

    public init(maxConcurrent: Int = 3) {
        precondition(maxConcurrent >= 1, "maxConcurrent must be >= 1")
        self.maxConcurrent = maxConcurrent
        self.available = maxConcurrent
    }

    /// Number of callers currently suspended waiting for a permit. Exposed for tests so
    /// they can enqueue waiters in a deterministic order.
    var waiterCount: Int { waiters.count }

    /// Suspends until a permit is free. Queued callers resume strictly FIFO.
    ///
    /// Responds to task cancellation (audit L4): a cancelled queued caller is removed from the
    /// queue and throws `CancellationError`, so it can't park indefinitely holding a slot. Every
    /// caller that successfully acquires a permit must always `release()` it (or use `run(_:)`).
    public func acquire() async throws {
        if available > 0 {
            available -= 1
            return
        }

        let id = nextWaiterID
        nextWaiterID += 1

        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                if Task.isCancelled {
                    continuation.resume(throwing: CancellationError())
                } else {
                    waiters.append(Waiter(id: id, continuation: continuation))
                }
            }
        } onCancel: {
            Task { await self.cancelWaiter(id) }
        }
    }

    /// Removes a cancelled waiter (if still queued) and resumes it with `CancellationError`.
    /// Actor isolation plus remove-before-resume guarantees a waiter is resumed at most once,
    /// even if a `release()` races the cancellation.
    private func cancelWaiter(_ id: Int) {
        guard let index = waiters.firstIndex(where: { $0.id == id }) else { return }
        waiters.remove(at: index).continuation.resume(throwing: CancellationError())
    }

    /// Returns a permit. If a caller is waiting, the permit is handed directly to the oldest
    /// waiter (the total in-flight count is conserved); otherwise the free count grows.
    public func release() {
        if waiters.isEmpty {
            available = min(available + 1, maxConcurrent)
        } else {
            waiters.removeFirst().continuation.resume(returning: ())
        }
    }

    /// Runs `operation` while holding a permit; releases it even if `operation` throws or the
    /// queued acquire is cancelled.
    public func run<T: Sendable>(_ operation: @Sendable () async throws -> T) async throws -> T {
        try await acquire()
        defer { release() }
        return try await operation()
    }
}
