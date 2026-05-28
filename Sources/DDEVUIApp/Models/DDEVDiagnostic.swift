import Foundation

public enum DDEVDiagnosticCheck: String, CaseIterable, Identifiable, Sendable {
    case ddevVersion
    case globalDiagnose
    case projectDiagnose
    case customConfig
    case dbMatch
    case mutagenStatus
    case mutagenSync
    case mutagenReset
    case mutagenLogs

    public var id: String { rawValue }

    public static let globalChecks: [DDEVDiagnosticCheck] = [.ddevVersion, .globalDiagnose]
    public static let projectChecks: [DDEVDiagnosticCheck] = [.projectDiagnose, .customConfig, .dbMatch]
    public static let mutagenChecks: [DDEVDiagnosticCheck] = [.mutagenStatus, .mutagenSync, .mutagenReset, .mutagenLogs]

    public var title: String {
        switch self {
        case .ddevVersion:
            "DDEV Version"
        case .globalDiagnose, .projectDiagnose:
            "Diagnose"
        case .customConfig:
            "Custom Config"
        case .dbMatch:
            "Database Match"
        case .mutagenStatus:
            "Mutagen Status"
        case .mutagenSync:
            "Mutagen Sync"
        case .mutagenReset:
            "Mutagen Reset"
        case .mutagenLogs:
            "Mutagen Logs"
        }
    }

    public var summary: String {
        switch self {
        case .ddevVersion:
            "Show DDEV and component versions."
        case .globalDiagnose:
            "Check Docker, networking, HTTPS, and DDEV availability."
        case .projectDiagnose:
            "Run DDEV health checks in the selected project."
        case .customConfig:
            "Find custom configuration that may warn on startup."
        case .dbMatch:
            "Verify the running database matches project configuration."
        case .mutagenStatus:
            "Show Mutagen sync health for this project."
        case .mutagenSync:
            "Ask Mutagen to sync this project now."
        case .mutagenReset:
            "Stop the project and remove its Mutagen Docker volume."
        case .mutagenLogs:
            "Show Mutagen logs for debugging sync problems."
        }
    }

    public var systemImage: String {
        switch self {
        case .ddevVersion:
            "number.circle"
        case .globalDiagnose, .projectDiagnose:
            "stethoscope"
        case .customConfig:
            "doc.badge.gearshape"
        case .dbMatch:
            "cylinder.split.1x2"
        case .mutagenStatus:
            "arrow.triangle.2.circlepath"
        case .mutagenSync:
            "arrow.clockwise.icloud"
        case .mutagenReset:
            "exclamationmark.arrow.triangle.2.circlepath"
        case .mutagenLogs:
            "text.page"
        }
    }

    public var requiresConfirmation: Bool {
        self == .mutagenReset
    }

    public init(mutagenCommand: DDEVMutagenCommand) {
        switch mutagenCommand {
        case .status:
            self = .mutagenStatus
        case .sync:
            self = .mutagenSync
        case .reset:
            self = .mutagenReset
        case .logs:
            self = .mutagenLogs
        }
    }
}

public struct DDEVDiagnosticEntry: Equatable, Identifiable, Sendable {
    public var id: String { check.id }
    public let check: DDEVDiagnosticCheck
    public let result: CommandResult

    public init(check: DDEVDiagnosticCheck, result: CommandResult) {
        self.check = check
        self.result = result
    }

    public var succeeded: Bool {
        result.exitCode == 0
    }

    public var output: String {
        [result.stdout.nilIfBlank, result.stderr.nilIfBlank]
            .compactMap { $0 }
            .joined(separator: "\n")
    }
}

public struct DDEVDiagnosticReport: Equatable, Sendable {
    public let entries: [DDEVDiagnosticEntry]

    public init(entries: [DDEVDiagnosticEntry] = []) {
        self.entries = entries
    }

    public var copyableOutput: String {
        entries.map(\.copyableOutput).joined(separator: "\n\n")
    }
}

private extension DDEVDiagnosticEntry {
    var copyableOutput: String {
        var lines = [
            "## \(check.title)"
        ]

        if let workingDirectory = result.workingDirectory {
            lines.append("Working Directory: \(workingDirectory)")
        }

        lines.append("Command: \(result.executable) \(result.arguments.joined(separator: " "))")
        lines.append("Exit Code: \(result.exitCode)")

        if let stdout = result.stdout.nilIfBlank {
            lines.append("")
            lines.append(stdout)
        }

        if let stderr = result.stderr.nilIfBlank {
            lines.append("")
            lines.append("STDERR:")
            lines.append(stderr)
        }

        return lines.joined(separator: "\n")
    }
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
