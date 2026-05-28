import XCTest
@testable import DDEVUIApp

final class InspectorTabTests: XCTestCase {
    func testCasesInDisplayOrder() {
        XCTAssertEqual(InspectorTab.allCases, [.overview, .manage, .logs])
    }

    func testDisplayNamesMatchDesignSpec() {
        XCTAssertEqual(InspectorTab.overview.displayName, "Overview")
        XCTAssertEqual(InspectorTab.manage.displayName, "Manage")
        XCTAssertEqual(InspectorTab.logs.displayName, "Logs")
    }

    func testSystemImagesArePopulated() {
        for tab in InspectorTab.allCases {
            XCTAssertFalse(tab.systemImage.isEmpty)
        }
    }
}
