import XCTest
@testable import DDEVUIApp

final class DDEVProjectRegistryTests: XCTestCase {

    // MARK: - Parsing

    func testParsesDDEVProjectListFormat() {
        let yaml = """
        anthropy:
            approot: /Users/dave/Development/agilepixel/anthropy
        baker-calculator:
            approot: /Users/dave/Development/humble/baker-calculator

        """
        let parsed = DDEVProjectRegistry.parse(yaml)
        XCTAssertEqual(parsed.map(\.name), ["anthropy", "baker-calculator"])
        XCTAssertEqual(parsed.map(\.appRoot), [
            "/Users/dave/Development/agilepixel/anthropy",
            "/Users/dave/Development/humble/baker-calculator"
        ])
    }

    func testParseStripsQuotesAndIgnoresUnknownKeysAndComments() {
        let yaml = """
        # written by ddev
        "odd name":
            approot: "/Volumes/Work/odd name"
            something_else: 42
        plain:
            approot: '/tmp/plain'
        """
        let parsed = DDEVProjectRegistry.parse(yaml)
        XCTAssertEqual(parsed.map(\.name), ["odd name", "plain"])
        XCTAssertEqual(parsed.map(\.appRoot), ["/Volumes/Work/odd name", "/tmp/plain"])
    }

    func testParseSkipsEntriesWithoutAnApproot() {
        let yaml = """
        broken:
        fine:
            approot: /tmp/fine
        """
        XCTAssertEqual(DDEVProjectRegistry.parse(yaml).map(\.name), ["fine"])
    }

    // MARK: - Folder availability

    func testUnavailableEntriesAreThoseWhoseFolderIsMissing() throws {
        let directory = try makeTemporaryDirectory()
        let present = directory.appendingPathComponent("present", isDirectory: true)
        try FileManager.default.createDirectory(at: present, withIntermediateDirectories: true)
        let registryFile = directory.appendingPathComponent("project_list.yaml")
        try """
        present:
            approot: \(present.path)
        gone:
            approot: \(directory.path)/gone
        """.write(to: registryFile, atomically: true, encoding: .utf8)

        let registry = FileDDEVProjectRegistry(path: registryFile.path)

        XCTAssertEqual(registry.entries().map(\.name), ["present", "gone"])
        XCTAssertEqual(registry.unavailableEntries().map(\.name), ["gone"])
    }

    func testMissingRegistryFileYieldsNothing() {
        let registry = FileDDEVProjectRegistry(path: "/nonexistent/\(UUID().uuidString)/project_list.yaml")
        XCTAssertTrue(registry.entries().isEmpty)
        XCTAssertTrue(registry.unavailableEntries().isEmpty)
    }

    func testInMemoryRegistryReportsUnavailableByFlag() {
        let registry = InMemoryDDEVProjectRegistry(entries: [
            DDEVProjectRegistryEntry(name: "a", appRoot: "/a", folderExists: true),
            DDEVProjectRegistryEntry(name: "b", appRoot: "/Volumes/Work/b", folderExists: false)
        ])
        XCTAssertEqual(registry.unavailableEntries().map(\.name), ["b"])
    }

    private func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("ddevui-registry-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }
}
