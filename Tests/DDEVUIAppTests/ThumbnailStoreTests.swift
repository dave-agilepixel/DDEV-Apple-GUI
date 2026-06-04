import XCTest
@testable import DDEVUIApp

final class ThumbnailStoreTests: XCTestCase {
    private func tempDir() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("ddevui-thumb-tests-\(UUID().uuidString)", isDirectory: true)
    }

    func testSaveThenLoadAllRoundTrips() async throws {
        let dir = tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = FileThumbnailStore(directory: dir)

        try await store.save(Data([0x1, 0x2, 0x3]), projectID: "aqua-pura")
        try await store.save(Data([0x4, 0x5]), projectID: "agilebugs")

        let all = await store.loadAll()
        XCTAssertEqual(all["aqua-pura"], Data([0x1, 0x2, 0x3]))
        XCTAssertEqual(all["agilebugs"], Data([0x4, 0x5]))
    }

    func testLoadAllOnMissingDirectoryReturnsEmpty() async {
        let all = await FileThumbnailStore(directory: tempDir()).loadAll()
        XCTAssertTrue(all.isEmpty)
    }

    func testPruneDeletesOnlyNonLiveIDs() async throws {
        let dir = tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = FileThumbnailStore(directory: dir)
        try await store.save(Data([0x1]), projectID: "keep")
        try await store.save(Data([0x2]), projectID: "drop")

        await store.prune(keeping: ["keep"])

        let all = await store.loadAll()
        XCTAssertEqual(Set(all.keys), ["keep"])
    }

    func testSavedFileIsOwnerOnly() async throws {
        let dir = tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = FileThumbnailStore(directory: dir)
        try await store.save(Data([0x1]), projectID: "aqua-pura")

        let perms = try FileManager.default.attributesOfItem(
            atPath: dir.appendingPathComponent("aqua-pura.jpg").path
        )[.posixPermissions] as? NSNumber
        XCTAssertEqual(perms?.int16Value, 0o600)
    }

    func testIDWithPathSeparatorIsSanitized() async throws {
        let dir = tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = FileThumbnailStore(directory: dir)

        try await store.save(Data([0x9]), projectID: "a/b")   // must not escape the directory

        let all = await store.loadAll()
        XCTAssertEqual(all["a_b"], Data([0x9]))                // separator replaced with "_"
    }

    func testInMemoryStoreRoundTrips() async throws {
        let store = InMemoryThumbnailStore()
        try await store.save(Data([0x7]), projectID: "x")
        await store.prune(keeping: ["x"])
        let all = await store.loadAll()
        XCTAssertEqual(all["x"], Data([0x7]))
    }
}
