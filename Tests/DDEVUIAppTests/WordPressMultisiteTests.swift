import XCTest
@testable import DDEVUIApp

final class WordPressMultisiteTests: XCTestCase {
    func testOptionsNormalizeBasePathAndAliasLists() {
        let options = WordPressMultisiteOptions(
            mode: .subdirectories,
            primaryURL: "https://aqua-pura.ddev.site",
            networkTitle: "  Aqua Network  ",
            basePath: "network/",
            additionalHostnames: [" www ", "", "*.aqua-pura"],
            additionalFQDNs: [" shop.test ", ""]
        )

        XCTAssertEqual(options.networkTitle, "Aqua Network")
        XCTAssertEqual(options.basePath, "/network")
        XCTAssertEqual(options.additionalHostnames, ["www", "*.aqua-pura"])
        XCTAssertEqual(options.additionalFQDNs, ["shop.test"])
    }

    func testRootBasePathIsPreserved() {
        let options = WordPressMultisiteOptions(
            mode: .subdirectories,
            primaryURL: "https://aqua-pura.ddev.site",
            basePath: "/"
        )

        XCTAssertEqual(options.basePath, "/")
    }
}
