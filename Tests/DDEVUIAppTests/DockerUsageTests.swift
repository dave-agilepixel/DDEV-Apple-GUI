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

    /// A Docker build that emits IEC suffixes (`GiB`/`MiB`) rather than SI ones is the real
    /// trigger for this: `DockerSize.parse` returns nil for them, and the previous `?? 0`
    /// default turned that into every category silently reading zero — a breakdown showing an
    /// empty Docker and a `plan` offering no build-cache or unused-images items at all, on a
    /// disk that is actually full. Fail visibly instead.
    func testThrowsOnUnparseableSizeRatherThanReportingZero() {
        let iecRows = """
        {"Active":"13","Reclaimable":"2.4GiB (15%)","Size":"15.39GiB","TotalCount":"32","Type":"Images"}
        {"Active":"0","Reclaimable":"0B (0%)","Size":"0B","TotalCount":"0","Type":"Containers"}
        {"Active":"0","Reclaimable":"0B (0%)","Size":"0B","TotalCount":"0","Type":"Local Volumes"}
        {"Active":"0","Reclaimable":"1.2GiB","Size":"1.8GiB","TotalCount":"49","Type":"Build Cache"}
        """

        XCTAssertThrowsError(try DockerUsage.decode(iecRows)) { error in
            guard case let DockerSystemError.malformedOutput(message) = error else {
                return XCTFail("expected malformedOutput, got \(error)")
            }
            XCTAssertTrue(
                message.contains("15.39GiB"),
                "the error should name the value it could not read, got: \(message)"
            )
        }
    }

    func testThrowsOnUnparseableReclaimableSize() {
        let rows = """
        {"Active":"13","Reclaimable":"lots","Size":"15.39GB","TotalCount":"32","Type":"Images"}
        {"Active":"0","Reclaimable":"0B (0%)","Size":"0B","TotalCount":"0","Type":"Containers"}
        {"Active":"0","Reclaimable":"0B (0%)","Size":"0B","TotalCount":"0","Type":"Local Volumes"}
        {"Active":"0","Reclaimable":"0B","Size":"0B","TotalCount":"0","Type":"Build Cache"}
        """

        XCTAssertThrowsError(try DockerUsage.decode(rows)) { error in
            guard case DockerSystemError.malformedOutput = error else {
                return XCTFail("expected malformedOutput, got \(error)")
            }
        }
    }
}
