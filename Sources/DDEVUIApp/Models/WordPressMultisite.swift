import Foundation

public enum WordPressMultisiteMode: String, CaseIterable, Identifiable, Sendable {
    case subdirectories
    case subdomains

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .subdirectories: "Subdirectories"
        case .subdomains: "Subdomains"
        }
    }

    public var usesSubdomains: Bool {
        self == .subdomains
    }
}

public struct WordPressMultisiteOptions: Equatable, Sendable {
    public let mode: WordPressMultisiteMode
    public let primaryURL: String
    public let networkTitle: String?
    public let basePath: String?
    public let additionalHostnames: [String]
    public let additionalFQDNs: [String]

    public init(
        mode: WordPressMultisiteMode,
        primaryURL: String,
        networkTitle: String? = nil,
        basePath: String? = nil,
        additionalHostnames: [String] = [],
        additionalFQDNs: [String] = []
    ) {
        self.mode = mode
        self.primaryURL = primaryURL
        self.networkTitle = networkTitle?.nilIfBlank
        self.basePath = Self.normalizedBasePath(basePath)
        self.additionalHostnames = additionalHostnames.normalizedDDEVList
        self.additionalFQDNs = additionalFQDNs.normalizedDDEVList
    }

    public var needsDDEVURLConfiguration: Bool {
        !additionalHostnames.isEmpty || !additionalFQDNs.isEmpty
    }

    private static func normalizedBasePath(_ value: String?) -> String? {
        guard var path = value?.nilIfBlank else { return nil }
        if !path.hasPrefix("/") {
            path = "/" + path
        }
        if path != "/", path.hasSuffix("/") {
            path.removeLast()
        }
        return path
    }
}

private extension Array where Element == String {
    var normalizedDDEVList: [String] {
        map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}
