import XCTest
@testable import DDEVUIApp

/// Integration tests for the real `ProcessCommandRunner`. These spawn short-lived child
/// processes via `/usr/bin/env` (`echo`, `sleep`) to verify the cancellation + timeout
/// behaviour added for audit finding H2.
final class ProcessCommandRunnerTests: XCTestCase {
    func testSuccessfulCommandReturnsOutput() async throws {
        let runner = ProcessCommandRunner()
        let result = try await runner.run(CommandSpec(executable: "echo", arguments: ["hello"]))
        XCTAssertEqual(result.exitCode, 0)
        XCTAssertEqual(result.stdout.trimmingCharacters(in: .whitespacesAndNewlines), "hello")
        XCTAssertFalse(result.wasCancelled)
    }

    func testCancellationTerminatesChildProcessPromptly() async throws {
        let runner = ProcessCommandRunner()
        let start = Date()
        let task = Task<CommandResult, Error> {
            try await runner.run(CommandSpec(executable: "sleep", arguments: ["30"]))
        }
        // Give the child a moment to actually start before cancelling.
        try await Task.sleep(for: .milliseconds(300))
        task.cancel()

        do {
            _ = try await task.value
            XCTFail("Expected cancellation to throw")
        } catch is CancellationError {
            // expected
        } catch {
            XCTFail("Expected CancellationError, got \(error)")
        }

        let elapsed = Date().timeIntervalSince(start)
        XCTAssertLessThan(elapsed, 10, "A cancelled child must be terminated, not waited out for 30s")
    }

    func testTimeoutTerminatesChildProcess() async throws {
        let runner = ProcessCommandRunner()
        let start = Date()
        do {
            _ = try await runner.run(
                CommandSpec(executable: "sleep", arguments: ["30"], timeout: .seconds(1))
            )
            XCTFail("Expected timeout to throw")
        } catch let CommandRunnerError.timedOut(result) {
            XCTAssertTrue(result.wasCancelled, "A timed-out result is flagged as cancelled")
        } catch {
            XCTFail("Expected CommandRunnerError.timedOut, got \(error)")
        }

        let elapsed = Date().timeIntervalSince(start)
        XCTAssertLessThan(elapsed, 10, "A wedged child must be killed at the timeout, not run to completion")
    }

    func testTimeoutDoesNotFireForFastCommand() async throws {
        let runner = ProcessCommandRunner()
        let result = try await runner.run(
            CommandSpec(executable: "echo", arguments: ["quick"], timeout: .seconds(30))
        )
        XCTAssertEqual(result.exitCode, 0)
        XCTAssertFalse(result.wasCancelled)
    }
}
