import XCTest
@testable import DDEVUIApp

/// Decoding tests for the rich `ddev describe -j` payload that backs the inspector's live
/// panels (Xdebug toggle, DB-credentials, per-service health). The fixtures mirror the real
/// envelope captured from `ddev describe <project> -j` on DDEV v1.25.2.
final class DDEVProjectDetailsDecodingTests: XCTestCase {
    func testDecodesRichDescribePayload() throws {
        let details = try DDEVProjectDetails.decodeDescribePayload(Self.fullPayload)

        XCTAssertEqual(details.phpVersion, "8.3")
        XCTAssertEqual(details.xhguiStatus, .disabled)
        XCTAssertEqual(details.xdebugEnabled, false)
        XCTAssertEqual(details.nodeJSVersion, "24")
        XCTAssertEqual(details.routerStatus, "healthy")
        XCTAssertEqual(details.sshAgentStatus, "healthy")
    }

    func testDecodesDatabaseInfo() throws {
        let details = try DDEVProjectDetails.decodeDescribePayload(Self.fullPayload)
        let db = try XCTUnwrap(details.databaseInfo)

        XCTAssertEqual(db.type, "mariadb")
        XCTAssertEqual(db.version, "11.8")
        XCTAssertEqual(db.host, "db")
        XCTAssertEqual(db.port, "3306")
        XCTAssertEqual(db.name, "db")
        XCTAssertEqual(db.username, "db")
        XCTAssertEqual(db.password, "db")
        XCTAssertEqual(db.publishedPort, 55043)
    }

    func testDerivesDatabaseHostPortFromPublishedPort() throws {
        let details = try DDEVProjectDetails.decodeDescribePayload(Self.fullPayload)

        // published_port wins when present (> 0).
        XCTAssertEqual(details.databaseHostPort, "55043")
    }

    func testDerivesDatabaseHostPortFromServiceMappingWhenNotPublished() throws {
        let details = try DDEVProjectDetails.decodeDescribePayload(Self.unpublishedDBPayload)

        // published_port is 0, so fall back to the db service's host-port mapping for 3306.
        XCTAssertEqual(details.databaseHostPort, "55099")
    }

    func testDecodesServicesSortedWebDBThenAlpha() throws {
        let details = try DDEVProjectDetails.decodeDescribePayload(Self.fullPayload)

        XCTAssertEqual(details.services.map(\.shortName), ["web", "db", "adminer", "xhgui"])

        let web = try XCTUnwrap(details.services.first { $0.shortName == "web" })
        XCTAssertEqual(web.image, "ddev/ddev-webserver:v1.25.2")
        XCTAssertEqual(web.status, "running")
        XCTAssertEqual(web.hostHTTPURL?.absoluteString, "http://127.0.0.1:55017")
        XCTAssertEqual(web.hostPorts.count, 3)
        XCTAssertEqual(web.hostPorts.first?.exposedPort, "80")
        XCTAssertEqual(web.hostPorts.first?.hostPort, "55017")
    }

    func testAddonServiceLinksExcludeCoreServicesAndRequireURL() throws {
        let details = try DDEVProjectDetails.decodeDescribePayload(Self.fullPayload)

        // web/db are core; xhgui has no usable url in this fixture; adminer is a real add-on UI.
        XCTAssertEqual(details.addonServiceLinks.map(\.name), ["adminer"])
        XCTAssertEqual(details.addonServiceLinks.first?.url.absoluteString, "https://adminer.aucoot.ddev.site")
    }

    func testThinPayloadStillDecodesWithDefaults() throws {
        let data = #"{"raw":{"php_version":"8.4","xhgui_status":"enabled"}}"#.data(using: .utf8)!

        let details = try DDEVProjectDetails.decodeDescribePayload(data)

        XCTAssertEqual(details.phpVersion, "8.4")
        XCTAssertEqual(details.xhguiStatus, .enabled)
        XCTAssertNil(details.xdebugEnabled)
        XCTAssertNil(details.databaseInfo)
        XCTAssertTrue(details.services.isEmpty)
        XCTAssertTrue(details.addonServiceLinks.isEmpty)
        XCTAssertNil(details.databaseHostPort)
    }

    // MARK: - Fixtures

    private static let fullPayload = """
    {
      "raw": {
        "name": "aucoot",
        "php_version": "8.3",
        "nodejs_version": "24",
        "xhgui_status": "disabled",
        "xdebug_enabled": false,
        "router_status": "healthy",
        "ssh_agent_status": "healthy",
        "dbinfo": {
          "database_type": "mariadb",
          "database_version": "11.8",
          "dbPort": "3306",
          "dbname": "db",
          "host": "db",
          "password": "db",
          "published_port": 55043,
          "username": "db"
        },
        "services": {
          "web": {
            "short_name": "web",
            "image": "ddev/ddev-webserver:v1.25.2",
            "status": "running",
            "host_http_url": "http://127.0.0.1:55017",
            "host_https_url": "https://127.0.0.1:55018",
            "http_url": "http://aucoot.ddev.site",
            "https_url": "https://aucoot.ddev.site",
            "host_ports_mapping": [
              { "exposed_port": "80", "host_port": "55017" },
              { "exposed_port": "443", "host_port": "55018" },
              { "exposed_port": "8025", "host_port": "52027" }
            ]
          },
          "db": {
            "short_name": "db",
            "image": "ddev/ddev-dbserver-mariadb-11.8:v1.25.2",
            "status": "running",
            "host_ports_mapping": [
              { "exposed_port": "3306", "host_port": "55043" }
            ]
          },
          "adminer": {
            "short_name": "adminer",
            "image": "ddev/ddev-utilities:latest",
            "status": "running",
            "http_url": "http://adminer.aucoot.ddev.site",
            "https_url": "https://adminer.aucoot.ddev.site",
            "host_ports_mapping": []
          },
          "xhgui": {
            "short_name": "xhgui",
            "image": "ddev/ddev-xhgui:latest",
            "status": "created",
            "host_ports_mapping": []
          }
        }
      }
    }
    """.data(using: .utf8)!

    private static let unpublishedDBPayload = """
    {
      "raw": {
        "name": "aucoot",
        "php_version": "8.3",
        "dbinfo": {
          "database_type": "mariadb",
          "database_version": "11.8",
          "dbPort": "3306",
          "dbname": "db",
          "host": "db",
          "password": "db",
          "published_port": 0,
          "username": "db"
        },
        "services": {
          "db": {
            "short_name": "db",
            "image": "ddev/ddev-dbserver-mariadb-11.8:v1.25.2",
            "status": "running",
            "host_ports_mapping": [
              { "exposed_port": "3306", "host_port": "55099" }
            ]
          }
        }
      }
    }
    """.data(using: .utf8)!
}
