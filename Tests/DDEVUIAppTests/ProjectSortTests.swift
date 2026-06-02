import XCTest
@testable import DDEVUIApp

final class ProjectSortTests: XCTestCase {
    func testNameSortIsCaseInsensitiveAscending() {
        let sorted = ProjectSort.name.sort([.sampleWordPress, .sampleLaravel], recentIDs: [])
        XCTAssertEqual(sorted.map(\.name), ["agilebugs", "aqua-pura"])
    }

    func testStatusSortPutsRunningFirstThenByName() {
        let running = DDEVProject.sampleWordPress                    // aqua-pura, running
        let stopped = DDEVProject.sampleLaravel.withStatus(.stopped) // agilebugs, stopped

        let sorted = ProjectSort.status.sort([stopped, running], recentIDs: [])

        XCTAssertEqual(sorted.map(\.name), ["aqua-pura", "agilebugs"], "Running sorts ahead of stopped")
    }

    func testRecentlyUsedHonorsRecencyThenFallsBackToName() {
        let sorted = ProjectSort.recentlyUsed.sort([.sampleWordPress, .sampleLaravel], recentIDs: ["agilebugs"])
        XCTAssertEqual(sorted.map(\.name), ["agilebugs", "aqua-pura"], "Most-recently-used floats to the top")

        // With no recency recorded, ties fall back to name order.
        let byName = ProjectSort.recentlyUsed.sort([.sampleWordPress, .sampleLaravel], recentIDs: [])
        XCTAssertEqual(byName.map(\.name), ["agilebugs", "aqua-pura"])
    }
}
