/// A FIFO async semaphore that bounds how many command operations run at once.
///
/// Has zero DDEV knowledge — it simply hands out a fixed number of permits and releases
/// blocked callers in arrival order. `ProjectDashboardViewModel` uses it to cap concurrent
/// project *mutations* (start/stop/restart/import/…) so a "start everything" burst does not
/// thrash Docker. Reads (logs/config/describe) bypass it entirely.
public actor CommandScheduler {
    private let maxConcurrent: Int
    private var available: Int
    private var waiters: [CheckedContinuation<Void, Never>] = []

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
    /// - Important: This method does not respond to task cancellation while queued. A
    ///   cancelled task stays suspended until a permit becomes available. Every caller that
    ///   acquires a permit must always `release()` it (or use `run(_:)`, which guarantees this).
    public func acquire() async {
        if available > 0 {
            available -= 1
            return
        }
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    /// Returns a permit. If a caller is waiting, the permit is handed directly to the oldest
    /// waiter (the total in-flight count is conserved); otherwise the free count grows.
    public func release() {
        if waiters.isEmpty {
            available = min(available + 1, maxConcurrent)
        } else {
            waiters.removeFirst().resume()
        }
    }

    /// Runs `operation` while holding a permit; releases it even if `operation` throws.
    public func run<T: Sendable>(_ operation: @Sendable () async throws -> T) async rethrows -> T {
        await acquire()
        defer { release() }
        return try await operation()
    }
}
