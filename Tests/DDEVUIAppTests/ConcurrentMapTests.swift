import XCTest
@testable import DDEVUIApp

final class ConcurrentMapTests: XCTestCase {
    func testRespectsConcurrencyLimitAndPreservesOrder() async {
        let tracker = ConcurrencyPeakTracker()
        let inputs = Array(0..<24)

        let outputs = await concurrentMap(inputs, limit: 4) { value in
            await tracker.enter()
            for _ in 0..<4 { await Task.yield() }
            await tracker.leave()
            return value * 10
        }

        XCTAssertEqual(outputs, inputs.map { $0 * 10 }, "Order preserved and every element mapped")
        let peak = await tracker.peak
        XCTAssertLessThanOrEqual(peak, 4, "Never more than `limit` transforms run at once")
        XCTAssertGreaterThan(peak, 1, "Work actually ran concurrently")
    }

    func testHandlesEmptyAndLimitLargerThanCount() async {
        let empty = await concurrentMap([Int](), limit: 4) { $0 }
        XCTAssertEqual(empty, [])

        let few = await concurrentMap([1, 2], limit: 10) { $0 + 1 }
        XCTAssertEqual(few, [2, 3])
    }
}

private actor ConcurrencyPeakTracker {
    private var current = 0
    private(set) var peak = 0
    func enter() { current += 1; peak = max(peak, current) }
    func leave() { current -= 1 }
}
