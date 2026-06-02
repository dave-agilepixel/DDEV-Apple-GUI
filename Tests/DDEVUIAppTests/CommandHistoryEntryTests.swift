import XCTest
@testable import DDEVUIApp

final class CommandHistoryEntryTests: XCTestCase {
    func testEachEntryHasItsOwnStableIdentity() {
        let result = CommandResult.success(stdout: "x")
        let first = CommandHistoryEntry(result: result)
        let second = CommandHistoryEntry(result: result)

        XCTAssertNotEqual(first.id, second.id,
                          "Distinct entries get distinct ids even for identical results, so the sliding history window can't reuse a row's identity")

        let copy = first
        XCTAssertEqual(copy.id, first.id, "Identity is stable across value copies")
    }

    func testCommandLineJoinsExecutableAndArguments() {
        XCTAssertEqual(result(args: ["exec", "-s", "web", "bash", "-c", "php -v"]).commandLine,
                       "ddev exec -s web bash -c php -v")
    }

    func testSafelyRerunnableAllowsNonDestructiveCommands() {
        XCTAssertTrue(result(args: ["composer", "install"]).isSafelyRerunnable)
        XCTAssertTrue(result(args: ["exec", "bash", "-c", "ls"]).isSafelyRerunnable)
        XCTAssertTrue(result(args: ["wp", "plugin", "list"]).isSafelyRerunnable)
        XCTAssertTrue(result(args: ["restart"]).isSafelyRerunnable)
    }

    func testSafelyRerunnableBlocksDestructiveOrGuardedCommands() {
        XCTAssertFalse(result(args: ["delete", "aqua-pura"]).isSafelyRerunnable)
        XCTAssertFalse(result(args: ["import-db", "--file=x.sql"]).isSafelyRerunnable)
        XCTAssertFalse(result(args: ["snapshot", "restore", "--latest"]).isSafelyRerunnable)
        XCTAssertFalse(result(args: ["stop", "--unlist", "aqua-pura"]).isSafelyRerunnable)
        XCTAssertFalse(result(args: ["poweroff"]).isSafelyRerunnable)
        XCTAssertFalse(result(args: []).isSafelyRerunnable)
    }

    private func result(args: [String]) -> CommandResult {
        let now = Date()
        return CommandResult(
            executable: "ddev", arguments: args, workingDirectory: nil,
            exitCode: 0, stdout: "", stderr: "", startedAt: now, finishedAt: now, wasCancelled: false
        )
    }
}
