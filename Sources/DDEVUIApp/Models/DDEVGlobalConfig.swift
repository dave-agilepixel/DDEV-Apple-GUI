import Foundation

/// The global DDEV configuration parsed from `ddev config global` output (A14). DDEV prints it as
/// `key=value` lines using the same hyphenated keys as the `--flag` writers, so the raw map round-
/// trips cleanly. Typed accessors surface the handful of common settings the GUI exposes as
/// controls; the full `values` map backs everything else, and the long tail stays in
/// `~/.ddev/global_config.yaml` (edit-in-editor, B8-style).
public struct DDEVGlobalConfig: Equatable, Sendable {
    public let values: [String: String]

    public init(values: [String: String]) {
        self.values = values
    }

    public func string(_ key: String) -> String? { values[key] }

    public var instrumentationOptIn: Bool { values["instrumentation-opt-in"] == "true" }
    public var performanceMode: String { values["performance-mode"] ?? "none" }
    public var xhprofMode: String { values["xhprof-mode"] ?? "xhgui" }
    public var routerHTTPPort: String { values["router-http-port"] ?? "" }
    public var routerHTTPSPort: String { values["router-https-port"] ?? "" }
    public var mailpitHTTPPort: String { values["mailpit-http-port"] ?? "" }
    public var mailpitHTTPSPort: String { values["mailpit-https-port"] ?? "" }
    public var projectTLD: String { values["project-tld"] ?? "" }

    /// Parses `ddev config global` output (one `key=value` per line). Comment (`#`) and blank lines
    /// are ignored; everything else is kept verbatim in `values`.
    public static func parse(_ output: String) -> DDEVGlobalConfig {
        var values: [String: String] = [:]
        for rawLine in output.split(separator: "\n", omittingEmptySubsequences: true) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty, !line.hasPrefix("#"), let eq = line.firstIndex(of: "=") else { continue }
            let key = String(line[line.startIndex..<eq]).trimmingCharacters(in: .whitespaces)
            let value = String(line[line.index(after: eq)...]).trimmingCharacters(in: .whitespaces)
            guard !key.isEmpty else { continue }
            values[key] = value
        }
        return DDEVGlobalConfig(values: values)
    }
}

/// A type-safe edit to the global config, applied via `ddev config global --flag=value` (A14).
/// Closed enum so there's no untrusted flag string to validate (mirrors `DDEVConfigChange`).
public enum DDEVGlobalConfigChange: Equatable, Sendable {
    case instrumentationOptIn(Bool)
    case performanceMode(String)
    case xhprofMode(String)
    case routerHTTPPort(String)
    case routerHTTPSPort(String)
    case mailpitHTTPPort(String)
    case mailpitHTTPSPort(String)
    case projectTLD(String)

    public var ddevFlags: [String] {
        switch self {
        case .instrumentationOptIn(let value): ["--instrumentation-opt-in=\(value)"]
        case .performanceMode(let value): ["--performance-mode=\(value)"]
        case .xhprofMode(let value): ["--xhprof-mode=\(value)"]
        case .routerHTTPPort(let value): ["--router-http-port=\(value)"]
        case .routerHTTPSPort(let value): ["--router-https-port=\(value)"]
        case .mailpitHTTPPort(let value): ["--mailpit-http-port=\(value)"]
        case .mailpitHTTPSPort(let value): ["--mailpit-https-port=\(value)"]
        case .projectTLD(let value): ["--project-tld=\(value)"]
        }
    }
}
