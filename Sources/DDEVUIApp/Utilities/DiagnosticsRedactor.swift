import Foundation

/// Masks secret-looking values before `ddev utility diagnose` output is copied to the
/// pasteboard, so passwords / tokens / keys can't be pasted into a public issue or chat
/// (audit S2). Only the value side of a `KEY=value` / `KEY: value` line whose key contains a
/// sensitive token is masked; benign lines and metadata are left intact.
enum DiagnosticsRedactor {
    private static let sensitiveTokens = ["PASSWORD", "PASSWD", "SECRET", "TOKEN", "KEY", "DB_", "AWS_"]

    static func redact(_ text: String) -> String {
        text
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { redactLine(String($0)) }
            .joined(separator: "\n")
    }

    private static func redactLine(_ line: String) -> String {
        // Use whichever delimiter appears first so a value containing ':' (e.g. a URL after '=')
        // doesn't get mistaken for the key/value boundary.
        let delimiter = [line.range(of: "="), line.range(of: ":")]
            .compactMap { $0 }
            .min { $0.lowerBound < $1.lowerBound }
        guard let delimiter else { return line }

        let key = String(line[line.startIndex..<delimiter.lowerBound])
        guard isSensitive(key: key) else { return line }

        return key + String(line[delimiter]) + " [REDACTED]"
    }

    private static func isSensitive(key: String) -> Bool {
        let upper = key.uppercased()
        return sensitiveTokens.contains { upper.contains($0) }
    }
}
