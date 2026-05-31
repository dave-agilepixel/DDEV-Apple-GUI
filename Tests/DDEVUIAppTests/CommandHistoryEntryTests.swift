import XCTest
@testable import DDEVUIApp

final class CommandHistoryEntryTests: XCTestCase {
    func testEachEntryHasItsOwnStableIdentity() {
        let result = CommandResult.success(stdout: "x")
        let first = CommandHistoryEntry(result: result)
        let second = CommandHistoryEntry(result: result)

        XCTAssertNotEqual(first.id, second.id,
                          "Distinct entries get distinct ids even for identical results, so the sliding history window can't reuse a row's identity")

        let copy = first
        XCTAssertEqual(copy.id, first.id, "Identity is stable across value copies")
    }
}
