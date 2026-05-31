import XCTest
@testable import DDEVUIApp

final class DockerExecutableResolverTests: XCTestCase {
    func testPrefersHomebrewDockerWhenShellPathIsMissing() {
        let resolver = DockerExecutableResolver(
            environment: ["PATH": "/usr/bin:/bin"],
            homeDirectory: "/Users/test",
            fileExists: { $0 == "/opt/homebrew/bin/docker" }
        )
        XCTAssertEqual(resolver.resolve(), "/opt/homebrew/bin/docker")
    }

    func testFindsOrbStackDockerUnderHome() {
        let resolver = DockerExecutableResolver(
            environment: ["PATH": "/usr/bin:/bin"],
            homeDirectory: "/Users/test",
            fileExists: { $0 == "/Users/test/.orbstack/bin/docker" }
        )
        XCTAssertEqual(resolver.resolve(), "/Users/test/.orbstack/bin/docker")
    }

    func testPrefersKnownLocationOverHostilePathEntry() {
        // A known-good absolute location wins over a PATH entry, so a hostile PATH can't shadow it.
        let resolver = DockerExecutableResolver(
            environment: ["PATH": "/tmp/evil:/usr/bin"],
            homeDirectory: "/Users/test",
            fileExists: { $0 == "/opt/homebrew/bin/docker" || $0 == "/tmp/evil/docker" }
        )
        XCTAssertEqual(resolver.resolve(), "/opt/homebrew/bin/docker")
    }

    func testUsesPATHWhenNoKnownLocationExists() {
        let resolver = DockerExecutableResolver(
            environment: ["PATH": "/custom/bin:/usr/bin"],
            homeDirectory: "/Users/test",
            fileExists: { $0 == "/custom/bin/docker" }
        )
        XCTAssertEqual(resolver.resolve(), "/custom/bin/docker")
    }

    func testFallsBackToBareNameWhenNothingFound() {
        let resolver = DockerExecutableResolver(
            environment: ["PATH": "/usr/bin:/bin"],
            homeDirectory: "/Users/test",
            fileExists: { _ in false }
        )
        XCTAssertEqual(resolver.resolve(), "docker")
    }
}
