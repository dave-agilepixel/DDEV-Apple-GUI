import XCTest
@testable import DDEVUIApp

final class DDEVLogRequestTests: XCTestCase {
    func testDefaultLogRequestUsesWebServiceAndUsefulTailCount() {
        let request = DDEVLogRequest()

        XCTAssertEqual(request.service, .web)
        XCTAssertEqual(request.tailCount, 100)
        XCTAssertFalse(request.includeTimestamps)
    }
}
