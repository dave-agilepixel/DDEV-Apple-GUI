import XCTest
@testable import DDEVUIApp

/// Tests the pure `.command` script generation behind the A11 "Open shell in Terminal" hand-off.
/// The file-write / NSWorkspace open is not unit-tested (it touches the real workspace), but the
/// quoting and command assembly — the part that can go subtly wrong — is.
final class WorkspaceShellHandoffTests: XCTestCase {
    func testWebShellScriptCDsIntoProjectAndRunsDDEVSSH() {
        let script = MacWorkspaceOpener.shellScript(
            appRoot: "/Users/dave/Development/site",
            arguments: DDEVShellTarget.webShell.ddevArguments
        )

        XCTAssertEqual(script, """
        #!/bin/bash
        cd '/Users/dave/Development/site' || exit 1
        ddev ssh
        """)
    }

    func testDBShellTargetUsesServiceFlag() {
        XCTAssertEqual(DDEVShellTarget.dbShell.ddevArguments, ["ssh", "--service", "db"])
        XCTAssertEqual(DDEVShellTarget.mysql.ddevArguments, ["mysql"])
    }

    func testScriptSingleQuotesPathsContainingSpaces() {
        let script = MacWorkspaceOpener.shellScript(
            appRoot: "/Users/dave/Local Sites/my project",
            arguments: ["ssh"]
        )

        XCTAssertTrue(
            script.contains("cd '/Users/dave/Local Sites/my project' || exit 1"),
            "Paths with spaces must stay single-quoted so cd receives one argument"
        )
    }

    func testScriptEscapesSingleQuotesInPath() {
        let script = MacWorkspaceOpener.shellScript(
            appRoot: "/Users/dave/o'brien/site",
            arguments: ["ssh"]
        )

        // A literal single quote in the path must be escaped as '\'' so the surrounding quoting
        // stays balanced and the shell can't reinterpret the remainder of the line.
        XCTAssertTrue(script.contains("cd '/Users/dave/o'\\''brien/site' || exit 1"))
    }
}
