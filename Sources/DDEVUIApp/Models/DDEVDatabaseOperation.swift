import Foundation

public struct DDEVDatabaseImportOptions: Equatable, Sendable {
    public let filePath: String
    public let database: String
    public let extractPath: String?
    public let dropExistingDatabase: Bool

    public init(
        filePath: String,
        database: String = "db",
        extractPath: String? = nil,
        dropExistingDatabase: Bool = true
    ) {
        self.filePath = filePath
        self.database = database.normalizedDDEVDatabaseName
        self.extractPath = extractPath?.nilIfBlank
        self.dropExistingDatabase = dropExistingDatabase
    }
}

public struct DDEVDatabaseExportOptions: Equatable, Sendable {
    public let outputPath: String
    public let database: String
    public let compression: DDEVDatabaseExportCompression

    public init(
        outputPath: String,
        database: String = "db",
        compression: DDEVDatabaseExportCompression = .gzip
    ) {
        self.outputPath = outputPath
        self.database = database.normalizedDDEVDatabaseName
        self.compression = compression
    }
}

public enum DDEVDatabaseExportCompression: String, CaseIterable, Sendable {
    case gzip
    case none
    case bzip2
    case xz

    public var displayName: String {
        switch self {
        case .gzip: "gzip (.gz)"
        case .none: "Plain SQL"
        case .bzip2: "bzip2 (.bz2)"
        case .xz: "xz (.xz)"
        }
    }

    public var ddevArguments: [String] {
        switch self {
        case .gzip: ["--gzip"]
        case .none: ["--gzip=false"]
        case .bzip2: ["--bzip2"]
        case .xz: ["--xz"]
        }
    }
}

private extension String {
    var normalizedDDEVDatabaseName: String {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "db" : trimmed
    }

    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
