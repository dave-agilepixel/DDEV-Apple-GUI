import Foundation

/// Parsing and formatting for the human-readable sizes Docker reports (`"42.37GB"`,
/// `"28.67kB"`, `"2.4GB (15%)"`). Docker uses SI multipliers — 1000-based, not 1024 — so
/// display formatting uses `ByteCountFormatter.CountStyle.file` to stay consistent with
/// what `docker system df` prints.
public enum DockerSize {
    private static let multipliers: [(suffix: String, factor: Double)] = [
        // Longest suffixes first so "kB" is never matched as "B".
        ("TB", 1_000_000_000_000),
        ("GB", 1_000_000_000),
        ("MB", 1_000_000),
        ("KB", 1_000),
        ("B", 1)
    ]

    /// Converts a Docker size string to bytes, or `nil` when it isn't a size at all
    /// (Docker prints `"N/A"` for several columns).
    public static func parse(_ text: String) -> Int64? {
        // Drop any trailing percentage, e.g. "2.4GB (15%)" -> "2.4GB".
        var cleaned = text
        if let parenthesis = cleaned.firstIndex(of: "(") {
            cleaned = String(cleaned[cleaned.startIndex..<parenthesis])
        }
        cleaned = cleaned.trimmingCharacters(in: .whitespaces).uppercased()
        guard !cleaned.isEmpty else { return nil }

        for (suffix, factor) in multipliers where cleaned.hasSuffix(suffix) {
            let numberPart = String(cleaned.dropLast(suffix.count)).trimmingCharacters(in: .whitespaces)
            guard !numberPart.isEmpty, let value = Double(numberPart) else { return nil }
            return Int64((value * factor).rounded())
        }
        return nil
    }
}

public extension Int64 {
    /// Display form for a byte count, SI-based to match Docker's own numbers.
    var formattedBytes: String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.allowedUnits = [.useKB, .useMB, .useGB, .useTB]
        return formatter.string(fromByteCount: self)
    }
}
