import XCTest
@testable import DDEVUIApp

final class AppPreferencesTests: XCTestCase {
    func testEditorFallbackChoosesCursorThenVSCodeThenFinder() {
        XCTAssertEqual(AppDefaults.effectiveEditor(saved: nil, installedEditors: [.cursor, .visualStudioCode]), .cursor)
        XCTAssertEqual(AppDefaults.effectiveEditor(saved: nil, installedEditors: [.visualStudioCode]), .visualStudioCode)
        XCTAssertEqual(AppDefaults.effectiveEditor(saved: nil, installedEditors: []), .finder)
    }

    func testSavedEditorIsIgnoredWhenUnavailable() {
        XCTAssertEqual(AppDefaults.effectiveEditor(saved: .cursor, installedEditors: [.visualStudioCode]), .visualStudioCode)
    }

    func testFinderIsAlwaysAvailable() {
        XCTAssertEqual(AppDefaults.availableEditors(installedEditors: []), [.finder])
        XCTAssertEqual(AppDefaults.availableEditors(installedEditors: [.cursor]), [.cursor, .finder])
    }

    func testDatabaseFallbackOrder() {
        XCTAssertEqual(AppDefaults.effectiveDatabaseTool(saved: nil, installedDatabaseTools: [.querious, .tablePlus]), .tablePlus)
        XCTAssertEqual(AppDefaults.effectiveDatabaseTool(saved: nil, installedDatabaseTools: [.sequelAce, .dbeaver]), .sequelAce)
        XCTAssertEqual(AppDefaults.effectiveDatabaseTool(saved: nil, installedDatabaseTools: [.dbeaver]), .dbeaver)
        XCTAssertNil(AppDefaults.effectiveDatabaseTool(saved: nil, installedDatabaseTools: []))
    }

    func testSavedDatabaseToolIsIgnoredWhenUnavailable() {
        XCTAssertEqual(AppDefaults.effectiveDatabaseTool(saved: .tablePlus, installedDatabaseTools: [.querious]), .querious)
    }

    func testUserDefaultsPreferencesStorePersistsAndClearsValues() {
        let suiteName = "DDEVUI-AppPreferencesTests-\(UUID().uuidString)"
        let userDefaults = UserDefaults(suiteName: suiteName)!
        defer { userDefaults.removePersistentDomain(forName: suiteName) }
        let store = UserDefaultsAppPreferencesStore(userDefaults: userDefaults)

        store.saveDefaultEditor(.cursor)
        store.saveDefaultDatabaseTool(.tablePlus)
        XCTAssertEqual(store.loadPreferences(), AppPreferences(defaultEditor: .cursor, defaultDatabaseTool: .tablePlus))

        store.saveDefaultEditor(nil)
        store.saveDefaultDatabaseTool(nil)
        XCTAssertEqual(store.loadPreferences(), AppPreferences())
    }
}
