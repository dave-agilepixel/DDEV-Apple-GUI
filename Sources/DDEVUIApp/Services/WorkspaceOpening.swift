import AppKit
import Foundation

public enum EditorChoice: String, CaseIterable, Sendable {
    case cursor = "Cursor"
    case visualStudioCode = "Visual Studio Code"
    case finder = "Finder"

    var bundleIdentifier: String? {
        switch self {
        case .cursor:
            "com.todesktop.230313mzl4w4u92"
        case .visualStudioCode:
            "com.microsoft.VSCode"
        case .finder:
            nil
        }
    }
}

public protocol WorkspaceOpening: Sendable {
    func openURL(_ url: URL)
    func openFolder(_ path: String, editor: EditorChoice)
}

public final class MacWorkspaceOpener: WorkspaceOpening, @unchecked Sendable {
    public init() {}

    public func openURL(_ url: URL) {
        NSWorkspace.shared.open(url)
    }

    public func openFolder(_ path: String, editor: EditorChoice) {
        let url = URL(fileURLWithPath: path)

        guard let bundleIdentifier = editor.bundleIdentifier,
              let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier)
        else {
            NSWorkspace.shared.activateFileViewerSelecting([url])
            return
        }

        let configuration = NSWorkspace.OpenConfiguration()
        NSWorkspace.shared.open([url], withApplicationAt: appURL, configuration: configuration)
    }
}
