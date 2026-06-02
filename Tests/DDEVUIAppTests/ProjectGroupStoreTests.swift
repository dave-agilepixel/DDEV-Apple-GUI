import XCTest
@testable import DDEVUIApp

final class ProjectGroupStoreTests: XCTestCase {
    func testUserDefaultsRoundTrip() {
        let defaults = UserDefaults(suiteName: "ProjectGroupStoreTests.\(UUID().uuidString)")!
        let store = UserDefaultsProjectGroupStore(userDefaults: defaults)
        let groups = [
            ProjectGroup(name: "A", colorID: .blue, memberIDs: ["x"]),
            ProjectGroup(name: "B", colorID: .red, memberIDs: [])
        ]
        store.saveGroups(groups)
        XCTAssertEqual(store.loadGroups(), groups)
    }

    func testLoadDefaultsToEmptyWhenAbsent() {
        let defaults = UserDefaults(suiteName: "ProjectGroupStoreTests.\(UUID().uuidString)")!
        XCTAssertEqual(UserDefaultsProjectGroupStore(userDefaults: defaults).loadGroups(), [])
    }

    func testInMemoryDouble() {
        let store = InMemoryProjectGroupStore()
        XCTAssertEqual(store.loadGroups(), [])
        let groups = [ProjectGroup(name: "A", colorID: .teal)]
        store.saveGroups(groups)
        XCTAssertEqual(store.loadGroups(), groups)
    }
}
