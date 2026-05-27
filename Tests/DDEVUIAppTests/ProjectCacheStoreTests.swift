import XCTest
@testable import DDEVUIApp

final class ProjectCacheStoreTests: XCTestCase {
    func testFileProjectCacheStoreReturnsEmptyWhenCacheIsMissing() throws {
        let directory = try temporaryDirectory()
        let store = FileProjectCacheStore(cacheDirectory: directory)

        let projects = try store.loadProjects()

        XCTAssertEqual(projects, [])
    }

    func testFileProjectCacheStoreSavesAndLoadsProjects() throws {
        let directory = try temporaryDirectory()
        let store = FileProjectCacheStore(cacheDirectory: directory)

        try store.saveProjects([.sampleWordPress, .sampleLaravel])

        XCTAssertEqual(try store.loadProjects(), [.sampleWordPress, .sampleLaravel])
    }

    func testFileProjectCacheStoreCreatesCacheDirectory() throws {
        let directory = try temporaryDirectory().appendingPathComponent("Nested")
        let store = FileProjectCacheStore(cacheDirectory: directory)

        try store.saveProjects([.sampleWordPress])

        XCTAssertTrue(FileManager.default.fileExists(atPath: directory.path))
        XCTAssertEqual(try store.loadProjects(), [.sampleWordPress])
    }

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("DDEVUI-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
