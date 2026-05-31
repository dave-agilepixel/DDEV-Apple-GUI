import XCTest
@testable import DDEVUIApp

final class DDEVConfigApplyingTests: XCTestCase {
    private let base = DDEVConfig(
        phpVersion: "8.2",
        nodeJSVersion: "20",
        databaseType: .mariadb,
        databaseVersion: "10.11",
        webserverType: .nginxFPM,
        performanceMode: .global,
        xdebugEnabled: false,
        xhprofMode: .global,
        uploadDirs: ["web/uploads"],
        additionalHostnames: ["www"]
    )

    func testApplyingUpdatesOnlyTheChangedFieldSoSiblingIndicatorsStayAccurate() {
        let updated = base.applying(.phpVersion("8.3"))

        XCTAssertEqual(updated.phpVersion, "8.3", "Applied field advances")
        // Everything else stays at the baseline, so other rows' hasChanges stays accurate.
        XCTAssertEqual(updated.nodeJSVersion, base.nodeJSVersion)
        XCTAssertEqual(updated.databaseType, base.databaseType)
        XCTAssertEqual(updated.uploadDirs, base.uploadDirs)
        XCTAssertEqual(updated.additionalHostnames, base.additionalHostnames)
    }

    func testApplyingDatabaseUpdatesBothTypeAndVersion() {
        let updated = base.applying(.database(type: .postgres, version: "16"))
        XCTAssertEqual(updated.databaseType, .postgres)
        XCTAssertEqual(updated.databaseVersion, "16")
        XCTAssertEqual(updated.phpVersion, base.phpVersion)
    }

    func testApplyingCoversEveryChangeCase() {
        XCTAssertEqual(base.applying(.nodeJSVersion("22")).nodeJSVersion, "22")
        XCTAssertEqual(base.applying(.webserverType(.apacheFPM)).webserverType, .apacheFPM)
        XCTAssertEqual(base.applying(.performanceMode(.mutagen)).performanceMode, .mutagen)
        XCTAssertTrue(base.applying(.xdebugEnabled(true)).xdebugEnabled)
        XCTAssertEqual(base.applying(.uploadDirs(["a", "b"])).uploadDirs, ["a", "b"])
        XCTAssertEqual(base.applying(.additionalHostnames(["x"])).additionalHostnames, ["x"])
    }
}
