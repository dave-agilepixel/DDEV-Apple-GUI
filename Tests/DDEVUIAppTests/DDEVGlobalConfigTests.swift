import XCTest
@testable import DDEVUIApp

final class DDEVGlobalConfigTests: XCTestCase {
    private let sample = """
    addon-data-url=https://addons.ddev.com/addons.json
    instrumentation-opt-in=true
    mailpit-http-port=8025
    mailpit-https-port=8026
    omit-containers=[]
    performance-mode=mutagen
    project-tld=ddev.site
    router-http-port=80
    router-https-port=443
    xhprof-mode=xhgui
    """

    func testParsesKeyValueLinesIntoTypedHighlights() {
        let config = DDEVGlobalConfig.parse(sample)

        XCTAssertTrue(config.instrumentationOptIn)
        XCTAssertEqual(config.performanceMode, "mutagen")
        XCTAssertEqual(config.xhprofMode, "xhgui")
        XCTAssertEqual(config.routerHTTPPort, "80")
        XCTAssertEqual(config.routerHTTPSPort, "443")
        XCTAssertEqual(config.mailpitHTTPPort, "8025")
        XCTAssertEqual(config.mailpitHTTPSPort, "8026")
        XCTAssertEqual(config.projectTLD, "ddev.site")
    }

    func testParseKeepsFullRawMapAndIgnoresCommentsAndBlanks() {
        let config = DDEVGlobalConfig.parse("# a comment\n\nproject-tld=example.test\n")
        XCTAssertEqual(config.values["project-tld"], "example.test")
        XCTAssertNil(config.values["# a comment"])
        XCTAssertEqual(config.values.count, 1)
    }

    func testInstrumentationOptInIsFalseWhenNotTrue() {
        XCTAssertFalse(DDEVGlobalConfig.parse("instrumentation-opt-in=false").instrumentationOptIn)
    }

    func testChangeFlagsMatchDDEVGlobalFlagNames() {
        XCTAssertEqual(DDEVGlobalConfigChange.instrumentationOptIn(false).ddevFlags, ["--instrumentation-opt-in=false"])
        XCTAssertEqual(DDEVGlobalConfigChange.performanceMode("none").ddevFlags, ["--performance-mode=none"])
        XCTAssertEqual(DDEVGlobalConfigChange.xhprofMode("prepend").ddevFlags, ["--xhprof-mode=prepend"])
        XCTAssertEqual(DDEVGlobalConfigChange.routerHTTPPort("8080").ddevFlags, ["--router-http-port=8080"])
        XCTAssertEqual(DDEVGlobalConfigChange.routerHTTPSPort("8443").ddevFlags, ["--router-https-port=8443"])
        XCTAssertEqual(DDEVGlobalConfigChange.mailpitHTTPPort("8025").ddevFlags, ["--mailpit-http-port=8025"])
        XCTAssertEqual(DDEVGlobalConfigChange.mailpitHTTPSPort("8026").ddevFlags, ["--mailpit-https-port=8026"])
        XCTAssertEqual(DDEVGlobalConfigChange.projectTLD("ddev.site").ddevFlags, ["--project-tld=ddev.site"])
    }
}
