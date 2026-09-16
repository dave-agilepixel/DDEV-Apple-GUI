import Foundation

public struct AppPreferences: Codable, Equatable, Sendable {
    public var defaultEditor: EditorChoice?
    public var defaultDatabaseTool: DDEVDatabaseTool?
    public var projectSort: ProjectSort

    /// Fraction of Docker VM disk usage at which the menu bar starts warning. Default 0.85 —
    /// on a ~99 GB VM that leaves roughly 15 GB, about two project starts of headroom.
    public var diskWarnThreshold: Double

    /// Fraction at which the warning escalates to critical. Default 0.93.
    public var diskCriticalThreshold: Double

    public init(
        defaultEditor: EditorChoice? = nil,
        defaultDatabaseTool: DDEVDatabaseTool? = nil,
        projectSort: ProjectSort = .name,
        diskWarnThreshold: Double = 0.85,
        diskCriticalThreshold: Double = 0.93
    ) {
        self.defaultEditor = defaultEditor
        self.defaultDatabaseTool = defaultDatabaseTool
        self.projectSort = projectSort
        self.diskWarnThreshold = diskWarnThreshold
        self.diskCriticalThreshold = diskCriticalThreshold
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
    func saveDiskWarnThreshold(_ value: Double)
    func saveDiskCriticalThreshold(_ value: Double)
}

public final class UserDefaultsAppPreferencesStore: AppPreferencesStoring, @unchecked Sendable {
    private enum Key {
        static let defaultEditor = "defaultEditor"
        static let defaultDatabaseTool = "defaultDatabaseTool"
        static let projectSort = "projectSort"
        static let diskWarnThreshold = "diskWarnThreshold"
        static let diskCriticalThreshold = "diskCriticalThreshold"
    }

    private let userDefaults: UserDefaults

    public init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    public func loadPreferences() -> AppPreferences {
        AppPreferences(
            defaultEditor: userDefaults.string(forKey: Key.defaultEditor).flatMap(EditorChoice.init(rawValue:)),
            defaultDatabaseTool: userDefaults.string(forKey: Key.defaultDatabaseTool).flatMap(DDEVDatabaseTool.init(rawValue:)),
            projectSort: userDefaults.string(forKey: Key.projectSort).flatMap(ProjectSort.init(rawValue:)) ?? .name,
            diskWarnThreshold: threshold(forKey: Key.diskWarnThreshold, default: 0.85),
            diskCriticalThreshold: threshold(forKey: Key.diskCriticalThreshold, default: 0.93)
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

    public func saveDiskWarnThreshold(_ value: Double) {
        userDefaults.set(value, forKey: Key.diskWarnThreshold)
    }

    public func saveDiskCriticalThreshold(_ value: Double) {
        userDefaults.set(value, forKey: Key.diskCriticalThreshold)
    }

    private func save(_ value: String?, forKey key: String) {
        guard let value else {
            userDefaults.removeObject(forKey: key)
            return
        }

        userDefaults.set(value, forKey: key)
    }

    /// Reads a `Double` preference, falling back to `default` when the key is absent. A plain
    /// `userDefaults.double(forKey:)` returns `0.0` for an absent key, which is indistinguishable
    /// from a genuinely-stored `0.0` — checking `object(forKey:)` first avoids that ambiguity.
    private func threshold(forKey key: String, default defaultValue: Double) -> Double {
        guard userDefaults.object(forKey: key) != nil else {
            return defaultValue
        }

        return userDefaults.double(forKey: key)
    }
}
