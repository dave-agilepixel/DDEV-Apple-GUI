import Foundation

public protocol ProjectGroupStoring: Sendable {
    func loadGroups() -> [ProjectGroup]
    func saveGroups(_ groups: [ProjectGroup])
}

public final class UserDefaultsProjectGroupStore: ProjectGroupStoring, @unchecked Sendable {
    private static let key = "projectGroups"
    private let userDefaults: UserDefaults

    public init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    public func loadGroups() -> [ProjectGroup] {
        guard let data = userDefaults.data(forKey: Self.key),
              let groups = try? JSONDecoder().decode([ProjectGroup].self, from: data) else {
            return []
        }
        return groups
    }

    public func saveGroups(_ groups: [ProjectGroup]) {
        guard let data = try? JSONEncoder().encode(groups) else { return }
        userDefaults.set(data, forKey: Self.key)
    }
}

public final class InMemoryProjectGroupStore: ProjectGroupStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var groups: [ProjectGroup]

    public init(groups: [ProjectGroup] = []) { self.groups = groups }

    public func loadGroups() -> [ProjectGroup] { lock.withLock { groups } }
    public func saveGroups(_ groups: [ProjectGroup]) { lock.withLock { self.groups = groups } }
}
