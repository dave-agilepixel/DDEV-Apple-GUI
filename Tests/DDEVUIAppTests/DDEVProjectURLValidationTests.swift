import XCTest
@testable import DDEVUIApp

final class DDEVProjectURLValidationTests: XCTestCase {
    func testValidatedURLTrimsWhitespaceAndRequiresSchemeAndHost() {
        XCTAssertNil(DDEVProject.validatedURL(""))
        XCTAssertNil(DDEVProject.validatedURL("   "))
        XCTAssertNil(DDEVProject.validatedURL("not a url"), "Garbage with spaces is rejected, not turned into a zombie URL")
        XCTAssertNil(DDEVProject.validatedURL("aqua-pura.ddev.site"), "A schemeless host can't be opened in a browser")

        XCTAssertEqual(
            DDEVProject.validatedURL(" https://aqua-pura.ddev.site ")?.absoluteString,
            "https://aqua-pura.ddev.site",
            "Surrounding whitespace is trimmed before constructing the URL"
        )
        XCTAssertEqual(
            DDEVProject.validatedURL("https://aqua-pura.ddev.site:8443")?.absoluteString,
            "https://aqua-pura.ddev.site:8443"
        )
    }
}
