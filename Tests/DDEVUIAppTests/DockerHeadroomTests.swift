import XCTest
@testable import DDEVUIApp

final class DockerHeadroomTests: XCTestCase {
    func testParsesRealFixture() throws {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "docker-df-pk", withExtension: "txt"))
        let headroom = try DockerHeadroom.parse(try String(contentsOf: url, encoding: .utf8))

        // 1024-blocks converted to bytes.
        XCTAssertEqual(headroom.totalBytes, 98_759_140 * 1024)
        XCTAssertEqual(headroom.usedBytes, 66_597_752 * 1024)
        XCTAssertEqual(headroom.availableBytes, 27_111_892 * 1024)
        XCTAssertEqual(headroom.percentUsed, 71)
    }

    func testParsesExecProbeShapeWithDifferentFilesystemAndMountPoint() throws {
        // The `docker exec` path reports `overlay` on `/`; the fallback reports `/dev/vda1`
        // on `/probe`. Parsing must depend on column position only.
        let text = """
        Filesystem           1024-blocks    Used Available Capacity Mounted on
        overlay               98759140  66888912  26820732  71% /
        """
        let headroom = try DockerHeadroom.parse(text)
        XCTAssertEqual(headroom.usedBytes, 66_888_912 * 1024)
        XCTAssertEqual(headroom.percentUsed, 71)
    }

    func testUsedFractionIsRelativeToUsedPlusAvailable() throws {
        // df's Capacity column excludes reserved blocks, so total != used + available:
        // here used + available (900) leaves 100 blocks reserved out of a total of 1000.
        // used / (used + available) = 750 / 900 = 0.8333... (83%), whereas the wrong
        // used / total formula would give 750 / 1000 = 0.75 (75%) — the two disagree,
        // so this fixture actually pins the intended formula.
        let text = """
        Filesystem 1024-blocks Used Available Capacity Mounted on
        overlay 1000 750 150 83% /
        """
        let headroom = try DockerHeadroom.parse(text)
        XCTAssertEqual(headroom.usedFraction, 750.0 / 900.0, accuracy: 0.0001)
        XCTAssertEqual(headroom.percentUsed, 83)
    }

    func testThrowsWhenNoDataRow() {
        let headerOnly = "Filesystem 1024-blocks Used Available Capacity Mounted on"
        XCTAssertThrowsError(try DockerHeadroom.parse(headerOnly)) { error in
            guard case DockerSystemError.malformedOutput = error else {
                return XCTFail("expected malformedOutput, got \(error)")
            }
        }
    }

    func testThrowsOnNonNumericColumns() {
        let text = """
        Filesystem 1024-blocks Used Available Capacity Mounted on
        overlay lots some none 71% /
        """
        XCTAssertThrowsError(try DockerHeadroom.parse(text))
    }

    func testThrowsOnEmptyInput() {
        XCTAssertThrowsError(try DockerHeadroom.parse(""))
    }
}
