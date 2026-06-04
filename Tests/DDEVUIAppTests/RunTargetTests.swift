import XCTest
@testable import DDEVUIApp

final class RunTargetTests: XCTestCase {
    func testWordPressTargetsAreToolsThenExecServices() {
        let targets = RunTarget.available(for: .wordpress)
        XCTAssertEqual(targets, [
            .tool(.composer), .tool(.npm), .tool(.wp),
            .exec(.web), .exec(.db)
        ])
    }

    func testDrupalIncludesDrush() {
        let targets = RunTarget.available(for: .drupal10)
        XCTAssertTrue(targets.contains(.tool(.drush)))
        XCTAssertFalse(targets.contains(.tool(.wp)))
    }

    func testLabelsAreNonEmptyAndDistinguishToolFromService() {
        XCTAssertEqual(RunTarget.tool(.composer).label, "Composer")
        XCTAssertEqual(RunTarget.exec(.web).label, "Web shell")
        XCTAssertFalse(RunTarget.exec(.db).label.isEmpty)
    }

    func testIDsAreUnique() {
        // id feeds ForEach/Picker tag identity — collisions would cause subtle rendering bugs.
        let ids = RunTarget.available(for: .wordpress).map(\.id)
        XCTAssertEqual(ids.count, Set(ids).count)
    }
}
