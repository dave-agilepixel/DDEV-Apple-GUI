import XCTest
@testable import DDEVUIApp

final class DDEVSnapshotParsingTests: XCTestCase {
    func testParseEmptySnapshotListOutput() {
        XCTAssertEqual(DDEVSnapshot.parseListOutput("No snapshots found.\n"), [])
        XCTAssertEqual(DDEVSnapshot.parseListOutput(""), [])
    }

    func testParseMultipleSnapshotNamesWithDatabaseSuffixes() {
        let output = """
        Snapshot list for aqua-pura:
        before-upgrade_mariadb_10.11.gz
        release-candidate_mysql_8.0.gz
        plain-name.gz
        """

        XCTAssertEqual(
            DDEVSnapshot.parseListOutput(output),
            [
                DDEVSnapshot(name: "before-upgrade", databaseSuffix: "mariadb 10.11"),
                DDEVSnapshot(name: "release-candidate", databaseSuffix: "mysql 8.0"),
                DDEVSnapshot(name: "plain-name", databaseSuffix: nil)
            ]
        )
    }

    func testDisplayLabelIncludesDatabaseSuffixWhenAvailable() {
        XCTAssertEqual(
            DDEVSnapshot(name: "before-upgrade", databaseSuffix: "mariadb 10.11").displayLabel,
            "before-upgrade (mariadb 10.11)"
        )
        XCTAssertEqual(DDEVSnapshot(name: "plain-name", databaseSuffix: nil).displayLabel, "plain-name")
    }

    func testSuggestedNameUsesSanitizedProjectNameAndTimestamp() throws {
        let date = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-05-27T21:48:12Z"))

        XCTAssertEqual(
            DDEVSnapshot.suggestedName(
                projectName: "Client Site / Woo",
                date: date,
                timeZone: TimeZone(secondsFromGMT: 0)!
            ),
            "client-site-woo-20260527-214812"
        )
    }
}
