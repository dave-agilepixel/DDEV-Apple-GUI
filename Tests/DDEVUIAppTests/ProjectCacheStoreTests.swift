import XCTest
@testable import DDEVUIApp

final class ProjectCacheStoreTests: XCTestCase {
    func testFileProjectCacheStoreReturnsEmptyWhenCacheIsMissing() async throws {
        let directory = try temporaryDirectory()
        let store = FileProjectCacheStore(cacheDirectory: directory)

        let projects = try await store.loadProjects()

        XCTAssertEqual(projects, [])
    }

    func testFileProjectCacheStoreSavesAndLoadsProjects() async throws {
        let directory = try temporaryDirectory()
        let store = FileProjectCacheStore(cacheDirectory: directory)

        try await store.saveProjects([.sampleWordPress, .sampleLaravel])

        let loaded = try await store.loadProjects()
        XCTAssertEqual(loaded, [.sampleWordPress, .sampleLaravel])
    }

    func testFileProjectCacheStoreCreatesCacheDirectory() async throws {
        let directory = try temporaryDirectory().appendingPathComponent("Nested")
        let store = FileProjectCacheStore(cacheDirectory: directory)

        try await store.saveProjects([.sampleWordPress])

        XCTAssertTrue(FileManager.default.fileExists(atPath: directory.path))
        let loaded = try await store.loadProjects()
        XCTAssertEqual(loaded, [.sampleWordPress])
    }

    func testInMemoryProjectCacheStoreExposesMutableProjects() async throws {
        let store = InMemoryProjectCacheStore(projects: [.sampleWordPress])

        XCTAssertEqual(store.projects, [.sampleWordPress])

        store.projects = [.sampleLaravel]

        let loaded = try await store.loadProjects()
        XCTAssertEqual(loaded, [.sampleLaravel])
    }

    func testInMemoryProjectCacheStoreExposesMutableErrors() async throws {
        let store = InMemoryProjectCacheStore(projects: [.sampleWordPress])

        store.loadError = ProjectCacheStoreTestError.load
        store.saveError = ProjectCacheStoreTestError.save

        do {
            _ = try await store.loadProjects()
            XCTFail("Expected load to throw")
        } catch {
            XCTAssertEqual(error as? ProjectCacheStoreTestError, .load)
        }
        do {
            try await store.saveProjects([.sampleLaravel])
            XCTFail("Expected save to throw")
        } catch {
            XCTAssertEqual(error as? ProjectCacheStoreTestError, .save)
        }
        XCTAssertEqual(store.projects, [.sampleWordPress])
    }

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("DDEVUI-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}

private enum ProjectCacheStoreTestError: Error {
    case load
    case save
}
