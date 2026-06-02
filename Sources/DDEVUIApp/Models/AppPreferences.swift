import Foundation

public struct AppPreferences: Codable, Equatable, Sendable {
    public var defaultEditor: EditorChoice?
    public var defaultDatabaseTool: DDEVDatabaseTool?
    public var projectSort: ProjectSort

    public init(
        defaultEditor: EditorChoice? = nil,
        defaultDatabaseTool: DDEVDatabaseTool? = nil,
        projectSort: ProjectSort = .name
    ) {
        self.defaultEditor = defaultEditor
        self.defaultDatabaseTool = defaultDatabaseTool
        self.projectSort = projectSort
    }
}

public enum AppDefaults {
    private static let editorFallbackOrder: [EditorChoice] = [.cursor, .visualStudioCode, .finder]
    private static let databaseToolFallbackOrder: [DDEVDatabaseTool] = [.tablePlus, .sequelAce, .querious, .dbeaver]

    public static func availableEditors(installedEditors: [EditorChoice]) -> [EditorChoice] {
        guard !installedEditors.contains(.finder) else {
            return installedEditors
        }

        return installedEditors + [.finder]
    }

    public static func effectiveEditor(saved: EditorChoice?, installedEditors: [EditorChoice]) -> EditorChoice {
        let available = availableEditors(installedEditors: installedEditors)

        if let saved, available.contains(saved) {
            return saved
        }

        return editorFallbackOrder.first { available.contains($0) } ?? .finder
    }

    public static func effectiveDatabaseTool(
        saved: DDEVDatabaseTool?,
        installedDatabaseTools: [DDEVDatabaseTool]
    ) -> DDEVDatabaseTool? {
        if let saved, installedDatabaseTools.contains(saved) {
            return saved
        }

        return databaseToolFallbackOrder.first { installedDatabaseTools.contains($0) }
    }
}

public protocol AppPreferencesStoring: Sendable {
    func loadPreferences() -> AppPreferences
    func saveDefaultEditor(_ editor: EditorChoice?)
    func saveDefaultDatabaseTool(_ databaseTool: DDEVDatabaseTool?)
    func saveProjectSort(_ sort: ProjectSort)
}

public final class UserDefaultsAppPreferencesStore: AppPreferencesStoring, @unchecked Sendable {
    private enum Key {
        static let defaultEditor = "defaultEditor"
        static let defaultDatabaseTool = "defaultDatabaseTool"
        static let projectSort = "projectSort"
    }

    private let userDefaults: UserDefaults

    public init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    public func loadPreferences() -> AppPreferences {
        AppPreferences(
            defaultEditor: userDefaults.string(forKey: Key.defaultEditor).flatMap(EditorChoice.init(rawValue:)),
            defaultDatabaseTool: userDefaults.string(forKey: Key.defaultDatabaseTool).flatMap(DDEVDatabaseTool.init(rawValue:)),
            projectSort: userDefaults.string(forKey: Key.projectSort).flatMap(ProjectSort.init(rawValue:)) ?? .name
        )
    }

    public func saveDefaultEditor(_ editor: EditorChoice?) {
        save(editor?.rawValue, forKey: Key.defaultEditor)
    }

    public func saveDefaultDatabaseTool(_ databaseTool: DDEVDatabaseTool?) {
        save(databaseTool?.rawValue, forKey: Key.defaultDatabaseTool)
    }

    public func saveProjectSort(_ sort: ProjectSort) {
        save(sort.rawValue, forKey: Key.projectSort)
    }

    private func save(_ value: String?, forKey key: String) {
        guard let value else {
            userDefaults.removeObject(forKey: key)
            return
        }

        userDefaults.set(value, forKey: key)
    }
}
