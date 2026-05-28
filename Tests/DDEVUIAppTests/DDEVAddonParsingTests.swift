import XCTest
@testable import DDEVUIApp

final class DDEVAddonParsingTests: XCTestCase {
    func testParsesJSONRawAddOnPayload() throws {
        let output = """
        {
          "level": "info",
          "msg": "2 add-ons found.",
          "raw": [
            {
              "title": "ddev/ddev-redis",
              "github_url": "https://github.com/ddev/ddev-redis",
              "description": "Redis cache and data store service for DDEV",
              "tag_name": "v2.2.0",
              "dependencies": [],
              "type": "official"
            },
            {
              "title": "kwasib/ddev-keydb",
              "github_url": "https://github.com/kwasib/ddev-keydb",
              "description": "KeyDB service for DDEV",
              "tag_name": "v0.1.0",
              "dependencies": ["redis"],
              "type": "contrib"
            }
          ]
        }
        """

        let addons = try DDEVAddon.parseListOutput(output)

        XCTAssertEqual(addons, [
            DDEVAddon(
                repository: "ddev/ddev-redis",
                description: "Redis cache and data store service for DDEV",
                version: "v2.2.0",
                type: .official,
                dependencies: [],
                githubURL: URL(string: "https://github.com/ddev/ddev-redis")
            ),
            DDEVAddon(
                repository: "kwasib/ddev-keydb",
                description: "KeyDB service for DDEV",
                version: "v0.1.0",
                type: .contrib,
                dependencies: ["redis"],
                githubURL: URL(string: "https://github.com/kwasib/ddev-keydb")
            )
        ])
    }

    func testFallsBackToConservativeTableParsing() throws {
        let output = """
        ┌─────────────────────────┬────────────────────────────────────────┐
        │ ADD-ON                  │ DESCRIPTION                            │
        ├─────────────────────────┼────────────────────────────────────────┤
        │ ddev/ddev-adminer       │ Adminer database browser for DDEV*     │
        ├─────────────────────────┼────────────────────────────────────────┤
        │ user/ddev-example       │ Example contributed add-on             │
        └─────────────────────────┴────────────────────────────────────────┘
        """

        let addons = try DDEVAddon.parseListOutput(output)

        XCTAssertEqual(addons.map(\.repository), ["ddev/ddev-adminer", "user/ddev-example"])
        XCTAssertEqual(addons.first?.description, "Adminer database browser for DDEV")
        XCTAssertEqual(addons.first?.type, .official)
        XCTAssertEqual(addons.last?.type, .contrib)
    }

    func testRecommendedOfficialAddOnsIncludeCommonServices() {
        XCTAssertEqual(DDEVAddon.recommendedOfficial.map(\.repository), [
            "ddev/ddev-redis",
            "ddev/ddev-memcached",
            "ddev/ddev-mongodb",
            "ddev/ddev-adminer",
            "ddev/ddev-phpmyadmin",
            "ddev/ddev-redis-insight",
            "ddev/ddev-browsersync",
            "ddev/ddev-solr",
            "ddev/ddev-elasticsearch",
            "ddev/ddev-opensearch"
        ])
    }
}
