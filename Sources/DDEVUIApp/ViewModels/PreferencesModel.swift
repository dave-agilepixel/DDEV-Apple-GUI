import Foundation
import Observation

/// Owns app-preferences and installed-app state, extracted from `ProjectDashboardViewModel` to
/// shrink the god-object and isolate this concern (audit M9). The view model owns one of these
/// and forwards its public API, so views and tests are unaffected.
@MainActor
@Observable
public final class PreferencesModel {
    public private(set) var preferences: AppPreferences
    public private(set) var installedEditors: [EditorChoice]
    public private(set) var installedDatabaseTools: [DDEVDatabaseTool]

    @ObservationIgnored private let preferencesStore: AppPreferencesStoring
    @ObservationIgnored private let appAvailability: AppAvailabilityChecking

    public init(
        preferencesStore: AppPreferencesStoring = UserDefaultsAppPreferencesStore(),
        appAvailability: AppAvailabilityChecking = WorkspaceAppAvailabilityService()
    ) {
        self.preferencesStore = preferencesStore
        self.appAvailability = appAvailability
        self.preferences = preferencesStore.loadPreferences()
        self.installedEditors = appAvailability.installedEditors()
        self.installedDatabaseTools = appAvailability.installedDatabaseTools()
    }

    public var availableEditors: [EditorChoice] {
        AppDefaults.availableEditors(installedEditors: installedEditors)
    }

    public var availableDatabaseTools: [DDEVDatabaseTool] {
        installedDatabaseTools
    }

    public var effectiveDefaultEditor: EditorChoice {
        AppDefaults.effectiveEditor(saved: preferences.defaultEditor, installedEditors: installedEditors)
    }

    public var effectiveDefaultDatabaseTool: DDEVDatabaseTool? {
        AppDefaults.effectiveDatabaseTool(
            saved: preferences.defaultDatabaseTool,
            installedDatabaseTools: installedDatabaseTools
        )
    }

    public func setDefaultEditor(_ editor: EditorChoice?) {
        preferences.defaultEditor = editor
        preferencesStore.saveDefaultEditor(editor)
    }

    public func setDefaultDatabaseTool(_ databaseTool: DDEVDatabaseTool?) {
        preferences.defaultDatabaseTool = databaseTool
        preferencesStore.saveDefaultDatabaseTool(databaseTool)
    }

    public func refreshInstalledApps() {
        installedEditors = appAvailability.installedEditors()
        installedDatabaseTools = appAvailability.installedDatabaseTools()
    }
}
