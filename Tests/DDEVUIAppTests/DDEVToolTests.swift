import XCTest
@testable import DDEVUIApp

final class DDEVToolTests: XCTestCase {
    func testToolsForTypeAlwaysIncludeComposerAndNPM() {
        XCTAssertEqual(DDEVTool.tools(for: .laravel), [.composer, .npm])
        XCTAssertEqual(DDEVTool.tools(for: .php), [.composer, .npm])
    }

    func testWordPressTypesAddWPCLI() {
        XCTAssertEqual(DDEVTool.tools(for: .wordpress), [.composer, .npm, .wp])
        XCTAssertEqual(DDEVTool.tools(for: .wpBedrock), [.composer, .npm, .wp])
        XCTAssertFalse(DDEVTool.tools(for: .wordpress).contains(.drush))
    }

    func testDrupalTypesAddDrush() {
        XCTAssertEqual(DDEVTool.tools(for: .drupal10), [.composer, .npm, .drush])
        XCTAssertEqual(DDEVTool.tools(for: .drupal7), [.composer, .npm, .drush])
        XCTAssertFalse(DDEVTool.tools(for: .drupal10).contains(.wp))
    }

    func testTokenizeSplitsOnWhitespace() {
        XCTAssertEqual(DDEVTool.tokenizeArguments("require monolog/monolog"), ["require", "monolog/monolog"])
        XCTAssertEqual(DDEVTool.tokenizeArguments("  cr  "), ["cr"])
        XCTAssertEqual(DDEVTool.tokenizeArguments(""), [])
    }

    func testTokenizeRespectsDoubleAndSingleQuotes() {
        XCTAssertEqual(DDEVTool.tokenizeArguments(#"require "foo/bar:^1.0""#), ["require", "foo/bar:^1.0"])
        XCTAssertEqual(DDEVTool.tokenizeArguments(#"config set name "a b c""#), ["config", "set", "name", "a b c"])
        XCTAssertEqual(DDEVTool.tokenizeArguments("run 'a b'"), ["run", "a b"])
    }
}
