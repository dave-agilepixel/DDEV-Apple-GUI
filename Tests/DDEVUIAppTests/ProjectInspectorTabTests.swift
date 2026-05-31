import XCTest
@testable import DDEVUIApp

final class InspectorTabTests: XCTestCase {
    func testCasesInDisplayOrder() {
        XCTAssertEqual(InspectorTab.allCases, [.overview, .manage, .logs])
    }

    func testDisplayNamesMatchDesignSpec() {
        XCTAssertEqual(InspectorTab.overview.displayName, "Overview")
        XCTAssertEqual(InspectorTab.manage.displayName, "Manage")
        XCTAssertEqual(InspectorTab.logs.displayName, "Logs")
    }

    func testSystemImagesArePopulated() {
        for tab in InspectorTab.allCases {
            XCTAssertFalse(tab.systemImage.isEmpty)
        }
    }
}

/// Covers the A1 Open/Launch-hub link assembly: the project's own URLs plus add-on service UIs
/// from the live describe detail, sharing one source of truth between the toolbar and the chips.
final class ProjectLaunchLinksTests: XCTestCase {
    func testCombinesProjectURLsWithAddonServiceLinks() throws {
        let project = DDEVProject.sampleRunningWithURLs
        let details = DDEVProjectDetails(
            phpVersion: "8.3",
            services: [
                DDEVServiceInfo(
                    shortName: "adminer", image: "img", status: "running",
                    hostHTTPURL: nil, hostHTTPSURL: nil,
                    httpURL: nil, httpsURL: URL(string: "https://adminer.demo.ddev.site"),
                    hostPorts: []
                )
            ]
        )

        let links = projectLaunchLinks(project, details)

        XCTAssertEqual(links.map(\.name), ["Primary", "Mailpit", "Adminer"])
        XCTAssertEqual(links.last?.url.absoluteString, "https://adminer.demo.ddev.site")
    }

    func testNilDetailsYieldsProjectLinksOnly() {
        let links = projectLaunchLinks(.sampleRunningWithURLs, nil)

        XCTAssertEqual(links.map(\.name), ["Primary", "Mailpit"])
    }
}

private extension DDEVProject {
    static var sampleRunningWithURLs: DDEVProject {
        DDEVProject(
            name: "demo",
            appRoot: "/tmp/demo",
            shortRoot: "~/demo",
            status: .running,
            statusDescription: "running",
            projectType: .wordpress,
            docroot: "",
            primaryURL: URL(string: "https://demo.ddev.site"),
            httpURL: nil,
            httpsURL: nil,
            mailpitURL: URL(string: "http://demo.ddev.site:8025"),
            mailpitHTTPSURL: nil,
            xhguiURL: nil,
            xhguiHTTPSURL: nil,
            mutagenEnabled: false,
            mutagenStatus: nil,
            phpVersion: "8.3"
        )
    }
}
