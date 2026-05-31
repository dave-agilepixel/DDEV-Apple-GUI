import XCTest
@testable import DDEVUIApp

final class CommandSchedulerTests: XCTestCase {
    func testRunsAtMostMaxConcurrentAtOnce() async {
        let scheduler = CommandScheduler(maxConcurrent: 2)
        let tracker = ConcurrencyTracker()

        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<6 {
                group.addTask {
                    try? await scheduler.acquire()
                    await tracker.enter()
                    // Yield a few times so overlapping work would be observed if the cap leaked.
                    for _ in 0..<5 { await Task.yield() }
                    await tracker.leave()
                    await scheduler.release()
                }
            }
        }

        let peak = await tracker.peak
        XCTAssertEqual(peak, 2, "Never more than maxConcurrent permits held at once")
    }

    func testReleaseHandsPermitToWaiterFIFO() async {
        let scheduler = CommandScheduler(maxConcurrent: 1)
        let order = OrderRecorder()

        try? await scheduler.acquire()         // take the only permit

        // Enqueue three waiters in a *deterministic* order. Unstructured `Task {}` start
        // order is not guaranteed, so we only launch waiter N+1 once waiter N has actually
        // been appended to the scheduler's queue (observed via `waiterCount`).
        var waiters: [Task<Void, Never>] = []
        for index in 0..<3 {
            waiters.append(Task {
                try? await scheduler.acquire()
                await order.record(index)
                await scheduler.release()
            })
            while await scheduler.waiterCount < index + 1 { await Task.yield() }
        }

        // One release hands the permit to waiter 0, which cascades FIFO through 1 then 2.
        await scheduler.release()
        for waiter in waiters { _ = await waiter.value }

        let recorded = await order.values
        XCTAssertEqual(recorded, [0, 1, 2], "Waiters resume strictly FIFO")
    }

    func testRunReleasesPermitEvenWhenOperationThrows() async {
        let scheduler = CommandScheduler(maxConcurrent: 1)
        struct Boom: Error {}

        do {
            _ = try await scheduler.run { throw Boom() }
            XCTFail("Expected throw")
        } catch {
            // expected
        }

        // If the permit leaked, this acquire would hang forever; wrap in a timeout guard.
        let acquired = await withTimeout(seconds: 1) { (try? await scheduler.acquire()) != nil } ?? false
        XCTAssertTrue(acquired, "Permit was released despite the thrown operation")
    }

    func testCancelledQueuedAcquireThrowsAndFreesQueue() async {
        let scheduler = CommandScheduler(maxConcurrent: 1)
        try? await scheduler.acquire() // take the only permit

        let waiter = Task { () -> Bool in
            do { try await scheduler.acquire(); return false }
            catch is CancellationError { return true }
            catch { return false }
        }
        while await scheduler.waiterCount < 1 { await Task.yield() }

        waiter.cancel()
        let threwCancellation = await waiter.value
        XCTAssertTrue(threwCancellation, "A cancelled queued acquire throws CancellationError")

        // The cancelled waiter left the queue, so the scheduler still hands out permits.
        await scheduler.release()
        let reacquired = await withTimeout(seconds: 1) { (try? await scheduler.acquire()) != nil } ?? false
        XCTAssertTrue(reacquired, "Scheduler is not deadlocked by a cancelled waiter")
    }
}

// MARK: - Test helpers

private actor ConcurrencyTracker {
    private var current = 0
    private(set) var peak = 0
    func enter() { current += 1; peak = max(peak, current) }
    func leave() { current -= 1 }
}

private actor OrderRecorder {
    private(set) var values: [Int] = []
    func record(_ value: Int) { values.append(value) }
}

/// Runs `operation`, returning nil if it does not finish within `seconds`.
private func withTimeout<T: Sendable>(seconds: Double, _ operation: @escaping @Sendable () async -> T) async -> T? {
    await withTaskGroup(of: T?.self) { group in
        group.addTask { await operation() }
        group.addTask {
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            return nil
        }
        let result = await group.next() ?? nil
        group.cancelAll()
        return result
    }
}
