import XCTest
@testable import DDEVUIApp

final class DDEVExecutableResolverTests: XCTestCase {
    func testPrefersHomebrewDDEVWhenShellPathIsMissing() {
        let resolver = DDEVExecutableResolver(
            environment: ["PATH": "/usr/bin:/bin"],
            fileExists: { $0 == "/opt/homebrew/bin/ddev" }
        )

        XCTAssertEqual(resolver.resolve(), "/opt/homebrew/bin/ddev")
    }

    func testUsesPATHExecutableWhenAvailable() {
        let resolver = DDEVExecutableResolver(
            environment: ["PATH": "/custom/bin:/usr/bin"],
            fileExists: { $0 == "/custom/bin/ddev" }
        )

        XCTAssertEqual(resolver.resolve(), "/custom/bin/ddev")
    }

    func testFallsBackToDDEVNameWhenNoCandidateExists() {
        let resolver = DDEVExecutableResolver(
            environment: ["PATH": "/usr/bin:/bin"],
            fileExists: { _ in false }
        )

        XCTAssertEqual(resolver.resolve(), "ddev")
    }
}
