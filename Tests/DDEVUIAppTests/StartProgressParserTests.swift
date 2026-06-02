import XCTest
@testable import DDEVUIApp

final class StartProgressParserTests: XCTestCase {
    func testRecognizedLinesAdvanceMonotonicallyBelowOne() {
        var parser = StartProgressParser()
        let lines = ["Starting myproject...", "Container ddev-myproject-db  Started",
                     "Container ddev-myproject-web  Started", "Waiting for the web server to be ready"]
        var emitted: [Double] = []
        for line in lines { if let f = parser.consume(line) { emitted.append(f) } }

        XCTAssertFalse(emitted.isEmpty, "known DDEV lines should produce progress")
        XCTAssertEqual(emitted, emitted.sorted(), "progress is non-decreasing")
        XCTAssertTrue(emitted.allSatisfy { $0 < 1.0 }, "never reports 100% before completion")
    }

    func testUnrecognizedOutputStaysIndeterminate() {
        var parser = StartProgressParser()
        XCTAssertNil(parser.consume("some unrelated diagnostic chatter"))
        XCTAssertNil(parser.fraction, "no recognized stage -> indeterminate (nil)")
    }

    func testProgressNeverDecreasesEvenIfStagesArriveOutOfOrder() {
        var parser = StartProgressParser()
        _ = parser.consume("Waiting for the web server to be ready") // late-stage first
        let afterEarly = parser.consume("Starting myproject...")     // early-stage second
        XCTAssertNotNil(parser.fraction)
        if let afterEarly { XCTAssertGreaterThanOrEqual(afterEarly, 0.0) }
        XCTAssertGreaterThanOrEqual(parser.fraction ?? 0, 0.7)
    }

    func testCapturedRealOutputProducesMonotonicRamp() throws {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "ddev-start-output", withExtension: "txt"))
        let text = try String(contentsOf: url, encoding: .utf8)
        var parser = StartProgressParser()
        var emitted: [Double] = []
        for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
            if let f = parser.consume(String(line)) { emitted.append(f) }
        }
        XCTAssertGreaterThanOrEqual(emitted.count, 2, "real output advances through at least two stages")
        XCTAssertEqual(emitted, emitted.sorted())
        XCTAssertTrue(emitted.allSatisfy { $0 < 1.0 })
    }
}
