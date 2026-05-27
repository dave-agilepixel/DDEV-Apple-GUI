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

    func testDecodesCurrentDDEVSupportedProjectTypes() throws {
        let supportedTypes: [(String, DDEVProjectType)] = [
            ("asterios", .asterios),
            ("backdrop", .backdrop),
            ("cakephp", .cakephp),
            ("codeigniter", .codeigniter),
            ("craftcms", .craftcms),
            ("drupal", .drupal),
            ("drupal6", .drupal6),
            ("drupal7", .drupal7),
            ("drupal8", .drupal8),
            ("drupal9", .drupal9),
            ("drupal10", .drupal10),
            ("drupal11", .drupal11),
            ("drupal12", .drupal12),
            ("generic", .generic),
            ("joomla", .joomla),
            ("laravel", .laravel),
            ("magento", .magento),
            ("magento2", .magento2),
            ("php", .php),
            ("shopware6", .shopware6),
            ("silverstripe", .silverstripe),
            ("symfony", .symfony),
            ("typo3", .typo3),
            ("wordpress", .wordpress),
            ("wp-bedrock", .wpBedrock)
        ]

        for (rawType, expectedType) in supportedTypes {
            let project = try XCTUnwrap(try DDEVProject.decodeListPayload(projectListPayload(type: rawType)).first)
            XCTAssertEqual(project.projectType, expectedType, "Expected \(rawType) to decode as \(expectedType)")
        }
    }

    func testUnknownFutureProjectTypeFallsBackToOther() throws {
        let project = try XCTUnwrap(try DDEVProject.decodeListPayload(projectListPayload(type: "futurecms")).first)

        XCTAssertEqual(project.projectType, .other)
    }

    func testProjectTypesExposeDisplayMetadataAndFamilies() {
        XCTAssertEqual(DDEVProjectType.drupal11.displayName, "Drupal 11")
        XCTAssertEqual(DDEVProjectType.craftcms.displayName, "Craft CMS")
        XCTAssertEqual(DDEVProjectType.php.displayName, "PHP")
        XCTAssertEqual(DDEVProjectType.typo3.symbol, "t.square")
        XCTAssertEqual(DDEVProjectType.magento2.family, .commerce)
        XCTAssertEqual(DDEVProjectType.symfony.family, .framework)
        XCTAssertEqual(DDEVProjectType.joomla.family, .cms)
        XCTAssertTrue(DDEVProjectType.commonProjectTypes.contains(.drupal11))
        XCTAssertTrue(DDEVProjectType.advancedProjectTypes.contains(.asterios))
        XCTAssertFalse(DDEVProjectType.supportedConfigTypes.contains(.other))
    }

    private func projectListPayload(type: String) -> Data {
        """
        {
          "raw": [
            {
              "name": "\(type)-site",
              "approot": "/tmp/\(type)-site",
              "shortroot": "~/\(type)-site",
              "status": "running",
              "status_desc": "running",
              "type": "\(type)",
              "docroot": "",
              "primary_url": "https://\(type)-site.ddev.site",
              "httpurl": "http://\(type)-site.ddev.site",
              "httpsurl": "https://\(type)-site.ddev.site",
              "mailpit_url": "http://\(type)-site.ddev.site:8025",
              "mailpit_https_url": "https://\(type)-site.ddev.site:8026",
              "xhgui_url": "http://\(type)-site.ddev.site:8143",
              "xhgui_https_url": "https://\(type)-site.ddev.site:8142",
              "mutagen_enabled": true,
              "mutagen_status": "ok"
            }
          ]
        }
        """.data(using: .utf8)!
    }
}
