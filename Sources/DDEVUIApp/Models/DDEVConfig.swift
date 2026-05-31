import Foundation

public struct DDEVConfig: Equatable, Sendable, CustomStringConvertible {
    public let phpVersion: String
    public let nodeJSVersion: String
    public let databaseType: DDEVDatabaseType
    public let databaseVersion: String
    public let webserverType: DDEVWebserverType
    public let performanceMode: DDEVPerformanceMode
    public let xdebugEnabled: Bool
    public let xhprofMode: DDEVXHProfMode
    public let uploadDirs: [String]
    public let additionalHostnames: [String]

    public init(
        phpVersion: String,
        nodeJSVersion: String,
        databaseType: DDEVDatabaseType,
        databaseVersion: String,
        webserverType: DDEVWebserverType,
        performanceMode: DDEVPerformanceMode,
        xdebugEnabled: Bool,
        xhprofMode: DDEVXHProfMode,
        uploadDirs: [String],
        additionalHostnames: [String]
    ) {
        self.phpVersion = phpVersion
        self.nodeJSVersion = nodeJSVersion
        self.databaseType = databaseType
        self.databaseVersion = databaseVersion
        self.webserverType = webserverType
        self.performanceMode = performanceMode
        self.xdebugEnabled = xdebugEnabled
        self.xhprofMode = xhprofMode
        self.uploadDirs = uploadDirs
        self.additionalHostnames = additionalHostnames
    }

    /// Returns a copy with only the field(s) addressed by `change` updated. The config editor
    /// uses this to advance just the applied row's baseline after a successful apply, so other
    /// rows' unsaved-change indicators stay accurate (audit M7).
    public func applying(_ change: DDEVConfigChange) -> DDEVConfig {
        var php = phpVersion, node = nodeJSVersion
        var dbType = databaseType, dbVersion = databaseVersion
        var web = webserverType, perf = performanceMode
        var xdebug = xdebugEnabled, xhprof = xhprofMode
        var uploads = uploadDirs, hostnames = additionalHostnames

        switch change {
        case .phpVersion(let value): php = value
        case .nodeJSVersion(let value): node = value
        case .database(let type, let version): dbType = type; dbVersion = version
        case .webserverType(let value): web = value
        case .performanceMode(let value): perf = value
        case .xdebugEnabled(let value): xdebug = value
        case .xhprofMode(let value): xhprof = value
        case .uploadDirs(let value): uploads = value
        case .additionalHostnames(let value): hostnames = value
        }

        return DDEVConfig(
            phpVersion: php,
            nodeJSVersion: node,
            databaseType: dbType,
            databaseVersion: dbVersion,
            webserverType: web,
            performanceMode: perf,
            xdebugEnabled: xdebug,
            xhprofMode: xhprof,
            uploadDirs: uploads,
            additionalHostnames: hostnames
        )
    }

    public static func parseYAML(_ yaml: String) throws -> DDEVConfig {
        let parser = DDEVConfigYAMLParser(yaml: yaml)
        let document = parser.parse()

        let phpVersion = try document.requiredScalar("php_version")
        let nodeJSVersion = try document.requiredScalar("nodejs_version")
        let databaseType = try DDEVDatabaseType(requiredRawValue: document.requiredNestedScalar("database", "type"))
        let databaseVersion = try document.requiredNestedScalar("database", "version")
        let webserverType = try DDEVWebserverType(requiredRawValue: document.requiredScalar("webserver_type"))
        let performanceMode = try DDEVPerformanceMode(
            requiredRawValue: document.scalar("performance_mode", default: DDEVPerformanceMode.global.rawValue)
        )
        let xdebugEnabled = try document.bool("xdebug_enabled", default: false)
        let xhprofMode = try DDEVXHProfMode(requiredRawValue: document.scalar("xhprof_mode", default: DDEVXHProfMode.xhgui.rawValue))

        return DDEVConfig(
            phpVersion: phpVersion,
            nodeJSVersion: nodeJSVersion,
            databaseType: databaseType,
            databaseVersion: databaseVersion,
            webserverType: webserverType,
            performanceMode: performanceMode,
            xdebugEnabled: xdebugEnabled,
            xhprofMode: xhprofMode,
            uploadDirs: document.list("upload_dirs"),
            additionalHostnames: document.list("additional_hostnames")
        )
    }

    public var description: String {
        [
            "phpVersion=\(phpVersion)",
            "nodeJSVersion=\(nodeJSVersion)",
            "database=\(databaseType.rawValue):\(databaseVersion)",
            "webserverType=\(webserverType.rawValue)",
            "performanceMode=\(performanceMode.rawValue)",
            "xdebugEnabled=\(xdebugEnabled)",
            "xhprofMode=\(xhprofMode.rawValue)",
            "uploadDirs=\(uploadDirs.joined(separator: ","))",
            "additionalHostnames=\(additionalHostnames.joined(separator: ","))"
        ].joined(separator: "; ")
    }
}

public enum DDEVConfigParseError: LocalizedError, Equatable, Sendable {
    case missingRequiredField(String)
    case invalidValue(field: String, value: String)

    public var errorDescription: String? {
        switch self {
        case .missingRequiredField(let field):
            "DDEV config is missing \(field)."
        case .invalidValue(let field, let value):
            "DDEV config has unsupported \(field) value '\(value)'."
        }
    }
}

public enum DDEVDatabaseType: String, CaseIterable, Identifiable, Sendable {
    case mariadb
    case mysql
    case postgres

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .mariadb: "MariaDB"
        case .mysql: "MySQL"
        case .postgres: "PostgreSQL"
        }
    }
}

public enum DDEVWebserverType: String, CaseIterable, Identifiable, Sendable {
    case nginxFPM = "nginx-fpm"
    case apacheFPM = "apache-fpm"
    case generic

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .nginxFPM: "nginx-fpm"
        case .apacheFPM: "apache-fpm"
        case .generic: "generic"
        }
    }
}

public enum DDEVPerformanceMode: String, CaseIterable, Identifiable, Sendable {
    case global
    case none
    case mutagen

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .global: "global"
        case .none: "none"
        case .mutagen: "mutagen"
        }
    }
}

public enum DDEVXHProfMode: String, CaseIterable, Identifiable, Sendable {
    case global
    case prepend
    case xhgui

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .global: "global"
        case .prepend: "prepend"
        case .xhgui: "xhgui"
        }
    }
}

public enum DDEVConfigChange: Equatable, Sendable {
    case phpVersion(String)
    case nodeJSVersion(String)
    case database(type: DDEVDatabaseType, version: String)
    case webserverType(DDEVWebserverType)
    case performanceMode(DDEVPerformanceMode)
    case xdebugEnabled(Bool)
    case xhprofMode(DDEVXHProfMode)
    case uploadDirs([String])
    case additionalHostnames([String])

    public var ddevFlags: [String] {
        switch self {
        case .phpVersion(let version):
            ["--php-version=\(version.trimmedForDDEVFlag)"]
        case .nodeJSVersion(let version):
            ["--nodejs-version=\(version.trimmedForDDEVFlag)"]
        case .database(let type, let version):
            ["--database=\(type.rawValue):\(version.trimmedForDDEVFlag)"]
        case .webserverType(let type):
            ["--webserver-type=\(type.rawValue)"]
        case .performanceMode(let mode):
            ["--performance-mode=\(mode.rawValue)"]
        case .xdebugEnabled(let enabled):
            ["--xdebug-enabled=\(enabled)"]
        case .xhprofMode(let mode):
            ["--xhprof-mode=\(mode.rawValue)"]
        case .uploadDirs(let dirs):
            ["--upload-dirs=\(dirs.ddevCommaList)"]
        case .additionalHostnames(let hostnames):
            ["--additional-hostnames=\(hostnames.ddevCommaList)"]
        }
    }
}

private extension DDEVDatabaseType {
    init(requiredRawValue rawValue: String) throws {
        guard let type = Self(rawValue: rawValue) else {
            throw DDEVConfigParseError.invalidValue(field: "database.type", value: rawValue)
        }
        self = type
    }
}

private extension DDEVWebserverType {
    init(requiredRawValue rawValue: String) throws {
        guard let type = Self(rawValue: rawValue) else {
            throw DDEVConfigParseError.invalidValue(field: "webserver_type", value: rawValue)
        }
        self = type
    }
}

private extension DDEVPerformanceMode {
    init(requiredRawValue rawValue: String) throws {
        guard let mode = Self(rawValue: rawValue) else {
            throw DDEVConfigParseError.invalidValue(field: "performance_mode", value: rawValue)
        }
        self = mode
    }
}

private extension DDEVXHProfMode {
    init(requiredRawValue rawValue: String) throws {
        guard let mode = Self(rawValue: rawValue) else {
            throw DDEVConfigParseError.invalidValue(field: "xhprof_mode", value: rawValue)
        }
        self = mode
    }
}

private struct DDEVConfigDocument {
    var scalars: [String: String] = [:]
    var lists: [String: [String]] = [:]
    var nestedScalars: [String: [String: String]] = [:]

    func requiredScalar(_ key: String) throws -> String {
        guard let value = scalars[key], !value.isEmpty else {
            throw DDEVConfigParseError.missingRequiredField(key)
        }
        return value
    }

    func scalar(_ key: String, default defaultValue: String) -> String {
        guard let value = scalars[key], !value.isEmpty else {
            return defaultValue
        }
        return value
    }

    func requiredNestedScalar(_ parent: String, _ key: String) throws -> String {
        guard let value = nestedScalars[parent]?[key], !value.isEmpty else {
            throw DDEVConfigParseError.missingRequiredField("\(parent).\(key)")
        }
        return value
    }

    func bool(_ key: String, default defaultValue: Bool) throws -> Bool {
        guard let value = scalars[key], !value.isEmpty else {
            return defaultValue
        }
        return try boolValue(field: key, value: value)
    }

    private func boolValue(field: String, value: String) throws -> Bool {
        switch value.lowercased() {
        case "true":
            return true
        case "false":
            return false
        default:
            throw DDEVConfigParseError.invalidValue(field: field, value: value)
        }
    }

    func list(_ key: String) -> [String] {
        lists[key] ?? []
    }
}

private struct DDEVConfigYAMLParser {
    let yaml: String

    func parse() -> DDEVConfigDocument {
        var document = DDEVConfigDocument()
        var activeListKey: String?
        var activeMapKey: String?

        for rawLine in yaml.components(separatedBy: .newlines) {
            let lineWithoutComment = rawLine.droppingYAMLComment
            guard !lineWithoutComment.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                continue
            }

            let indent = lineWithoutComment.prefix { $0 == " " }.count
            let trimmed = lineWithoutComment.trimmingCharacters(in: .whitespaces)

            if let activeListKey, indent > 0, trimmed.hasPrefix("- ") {
                document.lists[activeListKey, default: []].append(String(trimmed.dropFirst(2)).cleanedYAMLScalar)
                continue
            }

            if let activeMapKey, indent > 0, let child = keyValue(from: trimmed) {
                document.nestedScalars[activeMapKey, default: [:]][child.key] = child.value.cleanedYAMLScalar
                continue
            }

            activeListKey = nil
            activeMapKey = nil

            guard let item = keyValue(from: trimmed) else { continue }

            if item.value.isEmpty {
                if item.key == "database" {
                    activeMapKey = item.key
                } else {
                    activeListKey = item.key
                    document.lists[item.key] = []
                }
            } else if item.value.trimmingCharacters(in: .whitespaces).hasPrefix("[") {
                document.lists[item.key] = parseInlineList(item.value)
            } else {
                document.scalars[item.key] = item.value.cleanedYAMLScalar
            }
        }

        return document
    }

    private func keyValue(from line: String) -> (key: String, value: String)? {
        guard let separator = line.firstIndex(of: ":") else { return nil }

        let key = String(line[..<separator]).trimmingCharacters(in: .whitespaces)
        let valueStart = line.index(after: separator)
        let value = String(line[valueStart...]).trimmingCharacters(in: .whitespaces)
        return (key, value)
    }

    private func parseInlineList(_ value: String) -> [String] {
        let trimmed = value.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("["), trimmed.hasSuffix("]") else { return [] }

        let inner = String(trimmed.dropFirst().dropLast())
        guard !inner.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return [] }

        return inner
            .split(separator: ",", omittingEmptySubsequences: false)
            .map { String($0).cleanedYAMLScalar }
            .filter { !$0.isEmpty }
    }
}

private extension String {
    var cleanedYAMLScalar: String {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmed.count >= 2,
           let first = trimmed.first,
           let last = trimmed.last,
           (first == "\"" && last == "\"") || (first == "'" && last == "'") {
            return String(trimmed.dropFirst().dropLast())
        }

        return trimmed
    }

    var droppingYAMLComment: String {
        var inSingleQuote = false
        var inDoubleQuote = false
        for index in indices {
            let character = self[index]
            switch character {
            case "'" where !inDoubleQuote:
                inSingleQuote.toggle()
            case "\"" where !inSingleQuote:
                inDoubleQuote.toggle()
            case "#" where !inSingleQuote && !inDoubleQuote:
                return String(self[..<index])
            default:
                continue
            }
        }
        return self
    }

    var trimmedForDDEVFlag: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private extension Array where Element == String {
    var ddevCommaList: String {
        map(\.trimmedForDDEVFlag)
            .filter { !$0.isEmpty }
            .joined(separator: ",")
    }
}
