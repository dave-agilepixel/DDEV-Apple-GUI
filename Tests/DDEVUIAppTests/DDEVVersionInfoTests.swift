import XCTest
@testable import DDEVUIApp

final class DDEVVersionInfoTests: XCTestCase {
    // A trimmed but representative `ddev version -j` envelope (the machine payload lives under `.raw`).
    private let envelope = Data(#"""
    {"level":"info","msg":" rendered table ","raw":{"DDEV version":"v1.25.2","architecture":"arm64","cgo_enabled":"0","db":"ddev/ddev-dbserver-mariadb-11.8:v1.25.2","ddev-ssh-agent":"ddev/ddev-ssh-agent:v1.25.2","docker":"29.5.2","docker-compose":"v5.1.3","go-version":"go1.26.2","mutagen":"0.18.1","os":"darwin","router":"ddev/ddev-traefik-router:v1.25.2","web":"ddev/ddev-webserver:v1.25.2","xhgui-image":"ddev/ddev-xhgui:v1.25.2"},"time":"2026-06-02T15:45:04+01:00"}
    """#.utf8)

    func testDecodesTypedHighlightsFromRawEnvelope() throws {
        let info = try DDEVVersionInfo.decodeVersionPayload(envelope)

        XCTAssertEqual(info.ddevVersion, "v1.25.2")
        XCTAssertEqual(info.docker, "29.5.2")
        XCTAssertEqual(info.dockerCompose, "v5.1.3")
        XCTAssertEqual(info.mutagen, "0.18.1")
        XCTAssertEqual(info.architecture, "arm64")
    }

    func testDecodesComponentImagesFromRawEnvelope() throws {
        let info = try DDEVVersionInfo.decodeVersionPayload(envelope)

        XCTAssertEqual(info.webImage, "ddev/ddev-webserver:v1.25.2")
        XCTAssertEqual(info.dbImage, "ddev/ddev-dbserver-mariadb-11.8:v1.25.2")
        XCTAssertEqual(info.routerImage, "ddev/ddev-traefik-router:v1.25.2")
        XCTAssertEqual(info.sshAgentImage, "ddev/ddev-ssh-agent:v1.25.2")
    }

    func testItemsExposeFullSortedMapForDisplay() throws {
        let info = try DDEVVersionInfo.decodeVersionPayload(envelope)

        // Every raw key is surfaced (nothing silently dropped) so the panel is a faithful mirror.
        XCTAssertEqual(info.value(for: "go-version"), "go1.26.2")
        XCTAssertEqual(info.value(for: "os"), "darwin")

        // Items are stably ordered (case-insensitive ascending) so the list doesn't shuffle per run.
        let keys = info.items.map(\.key)
        XCTAssertEqual(keys, keys.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending })
    }

    func testEmptyRawDecodesToEmptyInfo() throws {
        let info = try DDEVVersionInfo.decodeVersionPayload(Data(#"{"raw":{}}"#.utf8))
        XCTAssertTrue(info.items.isEmpty)
        XCTAssertNil(info.ddevVersion)
    }
}
