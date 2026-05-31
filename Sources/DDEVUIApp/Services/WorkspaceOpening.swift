import AppKit
import Foundation

public enum EditorChoice: String, CaseIterable, Codable, Identifiable, Sendable {
    case cursor = "cursor"
    case visualStudioCode = "visual-studio-code"
    case finder = "finder"

    public var id: String {
        rawValue
    }

    public var displayName: String {
        switch self {
        case .cursor:
            "Cursor"
        case .visualStudioCode:
            "Visual Studio Code"
        case .finder:
            "Finder"
        }
    }

    public var bundleIdentifier: String? {
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

/// A shell session to hand off to the user's terminal (A11). Interactive shells are a poor fit
/// for an in-app form, so instead of embedding a PTY we open Terminal.app running the relevant
/// `ddev` command in the project directory.
public enum DDEVShellTarget: String, CaseIterable, Identifiable, Sendable {
    case webShell
    case dbShell
    case mysql

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .webShell: "Shell (web)"
        case .dbShell: "Shell (db)"
        case .mysql: "MySQL Client"
        }
    }

    public var systemImage: String {
        switch self {
        case .webShell: "terminal"
        case .dbShell: "terminal"
        case .mysql: "cylinder.split.1x2"
        }
    }

    /// The `ddev` arguments this target runs inside the project directory.
    public var ddevArguments: [String] {
        switch self {
        case .webShell: ["ssh"]
        case .dbShell: ["ssh", "--service", "db"]
        case .mysql: ["mysql"]
        }
    }
}

// NSWorkspace is main-thread-affine, so the opener is MainActor-isolated. This lets the
// compiler verify all call sites are on the main actor instead of suppressing the check with
// `@unchecked Sendable` (audit L13). All callers are SwiftUI views, already on the MainActor.
@MainActor
public protocol WorkspaceOpening: Sendable {
    func openURL(_ url: URL)
    func openFolder(_ path: String, editor: EditorChoice)
    /// Opens a specific file (e.g. `.ddev/config.yaml`) in the chosen editor (B8).
    func openFile(_ path: String, editor: EditorChoice)
    /// Hands a shell session off to Terminal.app, running `ddev <target>` in `appRoot` (A11).
    func openShell(in appRoot: String, target: DDEVShellTarget)
}

@MainActor
public final class MacWorkspaceOpener: WorkspaceOpening {
    public init() {}

    public func openURL(_ url: URL) {
        NSWorkspace.shared.open(url)
    }

    public func openFolder(_ path: String, editor: EditorChoice) {
        openInEditor(URL(fileURLWithPath: path), editor: editor)
    }

    public func openFile(_ path: String, editor: EditorChoice) {
        openInEditor(URL(fileURLWithPath: path), editor: editor)
    }

    private func openInEditor(_ url: URL, editor: EditorChoice) {
        guard let bundleIdentifier = editor.bundleIdentifier,
              let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier)
        else {
            NSWorkspace.shared.activateFileViewerSelecting([url])
            return
        }

        let configuration = NSWorkspace.OpenConfiguration()
        NSWorkspace.shared.open([url], withApplicationAt: appURL, configuration: configuration)
    }

    public func openShell(in appRoot: String, target: DDEVShellTarget) {
        let script = Self.shellScript(appRoot: appRoot, arguments: target.ddevArguments)
        guard let scriptURL = Self.writeShellScript(script, appRoot: appRoot, target: target) else {
            // Fall back to revealing the folder if we couldn't stage the launcher script.
            NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: appRoot)])
            return
        }
        // `.command` files open in Terminal.app (the default handler) — no Automation permission
        // prompt, unlike an AppleScript `do script` hand-off.
        NSWorkspace.shared.open(scriptURL)
    }

    /// Builds the `.command` launcher script that `cd`s into the project and runs `ddev <args>`.
    /// Pure and side-effect-free so the quoting logic is unit-testable. The project path is
    /// single-quoted (paths can contain spaces); the ddev arguments come from the closed
    /// `DDEVShellTarget` enum, so they need no escaping.
    nonisolated static func shellScript(appRoot: String, arguments: [String]) -> String {
        let escapedRoot = appRoot.replacingOccurrences(of: "'", with: "'\\''")
        let command = (["ddev"] + arguments).joined(separator: " ")
        return """
        #!/bin/bash
        cd '\(escapedRoot)' || exit 1
        \(command)
        """
    }

    /// Stages the launcher under a dedicated temp subdirectory with a stable, per-project/target
    /// name (so repeated launches overwrite rather than accumulate), marked executable.
    private static func writeShellScript(_ script: String, appRoot: String, target: DDEVShellTarget) -> URL? {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("ddevui-shell", isDirectory: true)
        let safeRoot = appRoot.replacingOccurrences(of: "/", with: "_")
        let fileURL = directory.appendingPathComponent("ddev-\(target.rawValue)-\(safeRoot).command")
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try script.write(to: fileURL, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: fileURL.path)
            return fileURL
        } catch {
            return nil
        }
    }
}
