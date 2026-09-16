import XCTest
@testable import DDEVUIApp

final class DockerVolumeTests: XCTestCase {
    private func fixture() throws -> String {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "docker-system-df-v", withExtension: "json"))
        return try String(contentsOf: url, encoding: .utf8)
    }

    func testDecodesRealFixture() throws {
        let volumes = try DockerVolume.decodeList(try fixture())
        XCTAssertEqual(volumes.count, 7)

        let mutagen = try XCTUnwrap(volumes.first { $0.name == "aqua-pura_project_mutagen" })
        XCTAssertEqual(mutagen.sizeBytes, 546_000_000)
        XCTAssertEqual(mutagen.links, 0)
        XCTAssertFalse(mutagen.isInUse)
    }

    func testLinksDrivesInUse() throws {
        let text = #"{"Volumes":[{"Name":"busy","Size":"1GB","Links":"2"},{"Name":"idle","Size":"1GB","Links":"0"}]}"#
        let volumes = try DockerVolume.decodeList(text)
        XCTAssertTrue(try XCTUnwrap(volumes.first { $0.name == "busy" }).isInUse)
        XCTAssertFalse(try XCTUnwrap(volumes.first { $0.name == "idle" }).isInUse)
    }

    func testTreatsUnparseableSizeAsZeroRatherThanFailing() throws {
        // Docker prints "N/A" in several columns; one odd size must not lose the whole list.
        let text = #"{"Volumes":[{"Name":"odd","Size":"N/A","Links":"0"}]}"#
        let volumes = try DockerVolume.decodeList(text)
        XCTAssertEqual(volumes.first?.sizeBytes, 0)
    }

    func testTreatsNonNumericLinksAsInUse() throws {
        // `Links` is the sole signal guarding deletion, so an unparseable value must fail
        // towards "in use", never towards "safe to delete".
        let text = #"{"Volumes":[{"Name":"odd","Size":"1GB","Links":"unknown"}]}"#
        let volumes = try DockerVolume.decodeList(text)
        XCTAssertTrue(try XCTUnwrap(volumes.first { $0.name == "odd" }).isInUse)
    }

    func testTreatsMissingLinksAsInUse() throws {
        let text = #"{"Volumes":[{"Name":"odd","Size":"1GB","Links":""}]}"#
        let volumes = try DockerVolume.decodeList(text)
        XCTAssertTrue(try XCTUnwrap(volumes.first { $0.name == "odd" }).isInUse)
    }

    func testTreatsNegativeLinksAsInUse() throws {
        // A negative link count is nonsense input, not a legitimate "0"; it must not be
        // read as "not in use".
        let text = #"{"Volumes":[{"Name":"odd","Size":"1GB","Links":"-1"}]}"#
        let volumes = try DockerVolume.decodeList(text)
        XCTAssertTrue(try XCTUnwrap(volumes.first { $0.name == "odd" }).isInUse)
    }

    func testReturnsEmptyWhenNoVolumes() throws {
        XCTAssertEqual(try DockerVolume.decodeList(#"{"Volumes":[]}"#).count, 0)
    }

    func testThrowsOnGarbageInput() {
        XCTAssertThrowsError(try DockerVolume.decodeList("not json")) { error in
            guard case DockerSystemError.malformedOutput = error else {
                return XCTFail("expected malformedOutput, got \(error)")
            }
        }
    }
}
