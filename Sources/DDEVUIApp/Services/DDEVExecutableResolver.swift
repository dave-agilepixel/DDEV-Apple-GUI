import Foundation

public struct DDEVExecutableResolver: Sendable {
    private let environment: [String: String]
    private let fileExists: @Sendable (String) -> Bool

    public init(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        fileExists: @escaping @Sendable (String) -> Bool = { FileManager.default.isExecutableFile(atPath: $0) }
    ) {
        self.environment = environment
        self.fileExists = fileExists
    }

    public func resolve() -> String {
        for path in pathCandidates() where fileExists(path) {
            return path
        }

        return "ddev"
    }

    private func pathCandidates() -> [String] {
        let pathEntries = environment["PATH", default: ""]
            .split(separator: ":")
            .map(String.init)
            .filter { !$0.isEmpty }

        let pathExecutables = pathEntries.map { "\($0)/ddev" }
        let knownLocations = [
            "/opt/homebrew/bin/ddev",
            "/usr/local/bin/ddev",
            "/usr/bin/ddev"
        ]

        return pathExecutables + knownLocations
    }
}
