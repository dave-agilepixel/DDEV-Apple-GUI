import Foundation

public struct DDEVSnapshot: Equatable, Identifiable, Sendable {
    public let name: String
    public let databaseSuffix: String?

    public init(name: String, databaseSuffix: String?) {
        self.name = name
        self.databaseSuffix = databaseSuffix
    }

    public var id: String {
        name
    }

    public var displayLabel: String {
        if let databaseSuffix {
            "\(name) (\(databaseSuffix))"
        } else {
            name
        }
    }

    public static func suggestedName(projectName: String, date: Date = Date(), timeZone: TimeZone = .current) -> String {
        let projectSegment = sanitizedNameSegment(from: projectName)
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyyMMdd-HHmmss"

        return "\(projectSegment)-\(formatter.string(from: date))"
    }

    public static func parseListOutput(_ output: String) -> [DDEVSnapshot] {
        output
            .split(whereSeparator: \.isNewline)
            .compactMap { parseLine(String($0)) }
    }

    private static func parseLine(_ line: String) -> DDEVSnapshot? {
        var trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmed.contains("│") {
            return parseTableRow(trimmed)
        }

        trimmed = trimmed.trimmingCharacters(in: CharacterSet(charactersIn: "-*| "))

        guard !trimmed.isEmpty else { return nil }

        let lowercased = trimmed.lowercased()
        guard !lowercased.contains("no snapshots"),
              !lowercased.contains("snapshot list"),
              !lowercased.contains("snapshots for"),
              lowercased != "name",
              !trimmed.allSatisfy({ $0 == "-" }),
              !trimmed.isBoxDrawingRule
        else {
            return nil
        }

        let token = trimmed
            .components(separatedBy: .whitespacesAndNewlines)
            .first { $0.hasSuffix(".gz") || $0.hasSuffix(".sql.gz") }
            ?? trimmed

        return parseSnapshotToken(token)
    }

    private static func parseTableRow(_ line: String) -> DDEVSnapshot? {
        let cells = line
            .split(separator: "│", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard let snapshotName = cells.first else { return nil }

        let lowercased = snapshotName.lowercased()
        guard lowercased != "snapshot", lowercased != "name" else { return nil }

        return parseSnapshotToken(snapshotName)
    }

    private static func parseSnapshotToken(_ token: String) -> DDEVSnapshot? {
        let filename = URL(fileURLWithPath: token).lastPathComponent
        let baseName = filename.removingGZipSuffix

        guard !baseName.isEmpty, !baseName.contains(" ") else { return nil }

        let databaseTypes = ["mariadb", "mysql", "postgresql", "postgres"]
        for databaseType in databaseTypes {
            let separator = "_\(databaseType)_"
            if let range = baseName.range(of: separator, options: [.caseInsensitive, .backwards]) {
                let snapshotName = String(baseName[..<range.lowerBound])
                let version = String(baseName[range.upperBound...])
                    .replacingOccurrences(of: "_", with: ".")

                guard !snapshotName.isEmpty, !version.isEmpty else { break }
                return DDEVSnapshot(name: snapshotName, databaseSuffix: "\(databaseType) \(version)")
            }
        }

        return DDEVSnapshot(name: baseName, databaseSuffix: nil)
    }

    private static func sanitizedNameSegment(from projectName: String) -> String {
        let allowedCharacters = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let normalized = String(projectName.lowercased().unicodeScalars.map { scalar in
            allowedCharacters.contains(scalar) ? Character(scalar) : "-"
        })
        let collapsed = normalized
            .split(separator: "-", omittingEmptySubsequences: true)
            .joined(separator: "-")

        return collapsed.isEmpty ? "snapshot" : collapsed
    }
}

private extension String {
    var removingGZipSuffix: String {
        if hasSuffix(".gz") {
            String(dropLast(3))
        } else {
            self
        }
    }

    var isBoxDrawingRule: Bool {
        let ruleCharacters = CharacterSet(charactersIn: "┌┬┐├┼┤└┴┘─")
        return unicodeScalars.allSatisfy { ruleCharacters.contains($0) }
    }
}
