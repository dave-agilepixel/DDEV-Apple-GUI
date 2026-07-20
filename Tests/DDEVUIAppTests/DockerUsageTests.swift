import XCTest
@testable import DDEVUIApp

final class DockerUsageTests: XCTestCase {
    private func fixture() throws -> String {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "docker-system-df", withExtension: "json"))
        return try String(contentsOf: url, encoding: .utf8)
    }

    func testDecodesRealFixture() throws {
        let usage = try DockerUsage.decode(try fixture())

        XCTAssertEqual(usage.images.totalCount, 32)
        XCTAssertEqual(usage.images.active, 13)
        XCTAssertEqual(usage.images.sizeBytes, 15_390_000_000)
        XCTAssertEqual(usage.images.reclaimableBytes, 2_400_000_000)

        XCTAssertEqual(usage.volumes.totalCount, 96)
        XCTAssertEqual(usage.volumes.reclaimableBytes, 42_210_000_000)

        // BuildCache reports Reclaimable without a percentage suffix.
        XCTAssertEqual(usage.buildCache.reclaimableBytes, 1_216_000_000)
        XCTAssertEqual(usage.buildCache.sizeBytes, 1_807_000_000)
    }

    func testTotalReclaimableSumsCategories() throws {
        let usage = try DockerUsage.decode(try fixture())
        XCTAssertEqual(
            usage.totalReclaimableBytes,
            usage.images.reclaimableBytes
                + usage.containers.reclaimableBytes
                + usage.volumes.reclaimableBytes
                + usage.buildCache.reclaimableBytes
        )
    }

    func testIgnoresBlankLines() throws {
        let text = try fixture() + "\n\n   \n"
        XCTAssertNoThrow(try DockerUsage.decode(text))
    }

    func testThrowsWhenACategoryIsMissing() {
        let onlyImages = #"{"Active":"1","Reclaimable":"0B (0%)","Size":"1GB","TotalCount":"1","Type":"Images"}"#
        XCTAssertThrowsError(try DockerUsage.decode(onlyImages)) { error in
            guard case DockerSystemError.malformedOutput = error else {
                return XCTFail("expected malformedOutput, got \(error)")
            }
        }
    }

    func testThrowsOnGarbageInput() {
        XCTAssertThrowsError(try DockerUsage.decode("not json at all"))
    }
}
