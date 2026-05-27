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
        XCTAssertNil(projects[0].phpVersion)
        XCTAssertTrue(projects[0].isWordPress)
    }

    func testDecodesPHPVersionFromDDEVDescribePayload() throws {
        let data = """
        {
          "raw": {
            "name": "aqua-pura",
            "php_version": "8.4"
          }
        }
        """.data(using: .utf8)!

        let details = try DDEVProjectDetails.decodeDescribePayload(data)

        XCTAssertEqual(details.phpVersion, "8.4")
    }

    func testProjectRoundTripsThroughJSONForCache() throws {
        let encoded = try JSONEncoder().encode(DDEVProject.sampleWordPress)
        let decoded = try JSONDecoder().decode(DDEVProject.self, from: encoded)

        XCTAssertEqual(decoded, .sampleWordPress)
        XCTAssertEqual(decoded.phpVersion, DDEVProject.sampleWordPress.phpVersion)
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
            mutagenStatus: "ok",
            phpVersion: nil
        )

        XCTAssertFalse(project.isWordPress)
    }
}
