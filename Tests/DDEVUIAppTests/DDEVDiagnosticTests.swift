import XCTest
@testable import DDEVUIApp

final class DDEVDiagnosticTests: XCTestCase {
    func testReportCombinesDiagnosticOutputForCopying() {
        let now = Date()
        let report = DDEVDiagnosticReport(
            entries: [
                DDEVDiagnosticEntry(
                    check: .ddevVersion,
                    result: CommandResult(
                        executable: "ddev",
                        arguments: ["version"],
                        workingDirectory: nil,
                        exitCode: 0,
                        stdout: "ddev version v1.24.8\n",
                        stderr: "",
                        startedAt: now,
                        finishedAt: now,
                        wasCancelled: false
                    )
                ),
                DDEVDiagnosticEntry(
                    check: .projectDiagnose,
                    result: CommandResult(
                        executable: "ddev",
                        arguments: ["utility", "diagnose"],
                        workingDirectory: "/Users/dave/site",
                        exitCode: 1,
                        stdout: "",
                        stderr: "Docker is not running\n",
                        startedAt: now,
                        finishedAt: now,
                        wasCancelled: false
                    )
                )
            ]
        )

        XCTAssertEqual(
            report.copyableOutput,
            """
            ## DDEV Version
            Command: ddev version
            Exit Code: 0

            ddev version v1.24.8

            ## Diagnose
            Working Directory: /Users/dave/site
            Command: ddev utility diagnose
            Exit Code: 1

            STDERR:
            Docker is not running
            """
        )
    }

    func testChecksExposeScopesAndResetRisk() {
        XCTAssertEqual(DDEVDiagnosticCheck.globalChecks, [.ddevVersion, .globalDiagnose])
        XCTAssertTrue(DDEVDiagnosticCheck.projectChecks.contains(.customConfig))
        XCTAssertTrue(DDEVDiagnosticCheck.projectChecks.contains(.dbMatch))
        XCTAssertTrue(DDEVDiagnosticCheck.mutagenReset.requiresConfirmation)
        XCTAssertFalse(DDEVDiagnosticCheck.mutagenSync.requiresConfirmation)
    }
}
