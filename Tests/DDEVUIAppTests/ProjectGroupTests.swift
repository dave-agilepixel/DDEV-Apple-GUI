import XCTest
@testable import DDEVUIApp

final class ProjectGroupTests: XCTestCase {
    func testCodableRoundTrip() throws {
        let group = ProjectGroup(id: UUID(), name: "Client Work", colorID: .blue, memberIDs: ["a", "b"])
        let data = try JSONEncoder().encode([group])
        let decoded = try JSONDecoder().decode([ProjectGroup].self, from: data)
        XCTAssertEqual(decoded, [group])
    }

    func testGroupColorHasEightCases() {
        XCTAssertEqual(GroupColor.allCases.count, 8)
    }
}
