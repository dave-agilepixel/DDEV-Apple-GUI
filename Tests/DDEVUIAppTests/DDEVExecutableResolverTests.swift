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

    func testPrefersKnownLocationOverHostilePathEntry() {
        // A known-good absolute location must win over a PATH entry so a hostile PATH cannot
        // point ddev at an attacker-controlled binary (audit S3).
        let resolver = DDEVExecutableResolver(
            environment: ["PATH": "/tmp/evil:/usr/bin"],
            fileExists: { $0 == "/opt/homebrew/bin/ddev" || $0 == "/tmp/evil/ddev" }
        )

        XCTAssertEqual(resolver.resolve(), "/opt/homebrew/bin/ddev")
    }

    func testFallsBackToDDEVNameWhenNoCandidateExists() {
        let resolver = DDEVExecutableResolver(
            environment: ["PATH": "/usr/bin:/bin"],
            fileExists: { _ in false }
        )

        XCTAssertEqual(resolver.resolve(), "ddev")
    }
}
