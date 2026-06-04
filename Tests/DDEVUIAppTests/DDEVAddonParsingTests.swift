import XCTest
@testable import DDEVUIApp

final class DDEVAddonParsingTests: XCTestCase {
    func testParseListOutputDecodesStarsFromRegistry() throws {
        let json = #"""
        {"raw":[{"title":"ddev/ddev-redis","description":"Redis","type":"official","stars":42,"github_url":"https://github.com/ddev/ddev-redis"}]}
        """#
        let addons = try DDEVAddon.parseListOutput(json)
        XCTAssertEqual(addons.first?.repository, "ddev/ddev-redis")
        XCTAssertEqual(addons.first?.stars, 42)
        XCTAssertTrue(addons.first?.isOfficial == true)
    }

    func testSortedForBrowsePutsOfficialFirstThenStars() {
        let addons = [
            DDEVAddon(repository: "z/community-a", description: "", type: .contrib, stars: 5),
            DDEVAddon(repository: "ddev/ddev-redis", description: "", type: .official, stars: 80),
            DDEVAddon(repository: "a/community-b", description: "", type: .contrib, stars: 50)
        ]
        let sorted = ProjectDashboardViewModel.sortedForBrowse(addons)
        XCTAssertEqual(sorted.map(\.repository), ["ddev/ddev-redis", "a/community-b", "z/community-a"])
    }

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

    func testParsesInstalledPascalCaseRawSchema() throws {
        // Real output of `ddev add-on list --installed --json-output` (DDEV v1.25.2): the
        // `raw` objects use PascalCase keys (Name/Repository/Version/Dependencies), unlike the
        // registry/search schema. Previously this decoded to zero add-ons and the UI dumped
        // the raw JSON blob.
        let output = #"""
        {"level":"info","msg":"┌────────┬─────────┬───────────────────────────┬───────────────────────────┐\n│ ADD-ON │ VERSION │ REPOSITORY                │ DATE INSTALLED            │\n├────────┼─────────┼───────────────────────────┼───────────────────────────┤\n│ bun    │ 1.1.2   │ OpenForgeProject/ddev-bun │ 2026-05-28T09:52:47+01:00 │\n└────────┴─────────┴───────────────────────────┴───────────────────────────┘\n","raw":[{"Name":"bun","Repository":"OpenForgeProject/ddev-bun","Version":"1.1.2","Dependencies":null,"InstallDate":"2026-05-28T09:52:47+01:00","ProjectFiles":["commands/web/bun","web-build/Dockerfile.bun"],"GlobalFiles":[],"RemovalActions":[]}],"time":"2026-06-04T15:31:56+01:00"}
        """#

        let addons = try DDEVAddon.parseListOutput(output)

        XCTAssertEqual(addons.count, 1)
        XCTAssertEqual(addons.first?.repository, "OpenForgeProject/ddev-bun")
        XCTAssertEqual(addons.first?.version, "1.1.2")
        XCTAssertEqual(addons.first?.dependencies, [])
        // `installName` must be DDEV's canonical name ("bun"), the identifier
        // `ddev add-on remove` expects — not the "ddev-bun" repo path tail.
        XCTAssertEqual(addons.first?.installName, "bun")
    }

    func testParsesInstalledRawSchemaWithDependencies() throws {
        let output = #"""
        {"raw":[{"Name":"keydb","Repository":"kwasib/ddev-keydb","Version":"v0.1.0","Dependencies":["redis"],"InstallDate":"2026-05-28T09:52:47+01:00"}]}
        """#

        let addons = try DDEVAddon.parseListOutput(output)

        XCTAssertEqual(addons.first?.repository, "kwasib/ddev-keydb")
        XCTAssertEqual(addons.first?.version, "v0.1.0")
        XCTAssertEqual(addons.first?.dependencies, ["redis"])
        XCTAssertEqual(addons.first?.installName, "keydb")
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
