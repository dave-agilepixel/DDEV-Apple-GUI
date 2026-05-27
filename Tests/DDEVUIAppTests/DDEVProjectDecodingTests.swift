import XCTest
@testable import DDEVUIApp

final class DDEVProjectDecodingTests: XCTestCase {
    func testDecodesProjectsFromDDEVListPayload() throws {
        let data = """
        {
          "raw": [
            {
              "name": "aqua-pura",
              "approot": "/Users/dave/Development/agilepixel/aqua-pura",
              "shortroot": "~/Development/agilepixel/aqua-pura",
              "status": "running",
              "status_desc": "running",
              "type": "wordpress",
              "docroot": "",
              "primary_url": "https://aqua-pura.ddev.site",
              "httpurl": "http://aqua-pura.ddev.site",
              "httpsurl": "https://aqua-pura.ddev.site",
              "mailpit_url": "http://aqua-pura.ddev.site:8025",
              "mailpit_https_url": "https://aqua-pura.ddev.site:8026",
              "xhgui_url": "http://aqua-pura.ddev.site:8143",
              "xhgui_https_url": "https://aqua-pura.ddev.site:8142",
              "mutagen_enabled": true,
              "mutagen_status": "ok"
            }
          ]
        }
        """.data(using: .utf8)!

        let projects = try DDEVProject.decodeListPayload(data)

        XCTAssertEqual(projects.count, 1)
        XCTAssertEqual(projects[0].name, "aqua-pura")
        XCTAssertEqual(projects[0].appRoot, "/Users/dave/Development/agilepixel/aqua-pura")
        XCTAssertEqual(projects[0].status, .running)
        XCTAssertEqual(projects[0].projectType, .wordpress)
        XCTAssertEqual(projects[0].primaryURL?.absoluteString, "https://aqua-pura.ddev.site")
        XCTAssertTrue(projects[0].isWordPress)
    }

    func testNonWordPressProjectIsNotWordPress() {
        let project = DDEVProject(
            name: "agilebugs",
            appRoot: "/tmp/agilebugs",
            shortRoot: "~/agilebugs",
            status: .paused,
            statusDescription: "paused",
            projectType: .laravel,
            docroot: "public",
            primaryURL: nil,
            httpURL: nil,
            httpsURL: nil,
            mailpitURL: nil,
            mailpitHTTPSURL: nil,
            xhguiURL: nil,
            xhguiHTTPSURL: nil,
            mutagenEnabled: true,
            mutagenStatus: "ok"
        )

        XCTAssertFalse(project.isWordPress)
    }
}
