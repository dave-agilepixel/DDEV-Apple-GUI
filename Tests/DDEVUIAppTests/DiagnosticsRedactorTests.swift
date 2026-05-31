import XCTest
@testable import DDEVUIApp

final class DiagnosticsRedactorTests: XCTestCase {
    func testMasksSecretAssignmentsAndKeepsBenignLines() {
        let input = """
        ## Diagnose
        Command: ddev utility diagnose
        Exit Code: 0
        DB_PASSWORD=hunter2
        MYSQL_ROOT_PASSWORD: s3cr3t
        AWS_SECRET_ACCESS_KEY=AKIA/abc+def
        API_TOKEN = ghp_xxx
        PROJECT=aqua-pura
        DATABASE_URL=mysql://user:pass@db:3306
        plain diagnostic line
        """

        let redacted = DiagnosticsRedactor.redact(input)

        XCTAssertFalse(redacted.contains("hunter2"))
        XCTAssertFalse(redacted.contains("s3cr3t"))
        XCTAssertFalse(redacted.contains("AKIA/abc+def"))
        XCTAssertFalse(redacted.contains("ghp_xxx"))
        XCTAssertTrue(redacted.contains("[REDACTED]"))

        // Benign metadata and non-secret values are preserved.
        XCTAssertTrue(redacted.contains("Command: ddev utility diagnose"))
        XCTAssertTrue(redacted.contains("Exit Code: 0"))
        XCTAssertTrue(redacted.contains("PROJECT=aqua-pura"))
        XCTAssertTrue(redacted.contains("plain diagnostic line"))
    }
}
