import AppKit
import Foundation

public protocol AppAvailabilityChecking: Sendable {
    func installedEditors() -> [EditorChoice]
    func installedDatabaseTools() -> [DDEVDatabaseTool]
}

public final class WorkspaceAppAvailabilityService: AppAvailabilityChecking, @unchecked Sendable {
    public init() {}

    public func installedEditors() -> [EditorChoice] {
        EditorChoice.allCases.filter { editor in
            guard let bundleIdentifier = editor.bundleIdentifier else {
                return false
            }

            return NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) != nil
        }
    }

    public func installedDatabaseTools() -> [DDEVDatabaseTool] {
        DDEVDatabaseTool.allCases.filter { databaseTool in
            NSWorkspace.shared.urlForApplication(withBundleIdentifier: databaseTool.bundleIdentifier) != nil
        }
    }
}

public struct StaticAppAvailabilityService: AppAvailabilityChecking {
    private let installedBundleIdentifiers: Set<String>

    public init(installedBundleIdentifiers: Set<String>) {
        self.installedBundleIdentifiers = installedBundleIdentifiers
    }

    public func installedEditors() -> [EditorChoice] {
        EditorChoice.allCases.filter { editor in
            guard let bundleIdentifier = editor.bundleIdentifier else {
                return false
            }

            return installedBundleIdentifiers.contains(bundleIdentifier)
        }
    }

    public func installedDatabaseTools() -> [DDEVDatabaseTool] {
        DDEVDatabaseTool.allCases.filter { databaseTool in
            installedBundleIdentifiers.contains(databaseTool.bundleIdentifier)
        }
    }
}
