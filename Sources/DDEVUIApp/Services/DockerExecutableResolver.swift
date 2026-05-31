import Foundation

/// Resolves the `docker` CLI to an absolute path, mirroring `DDEVExecutableResolver` (audit M6).
/// A GUI app launched by LaunchServices inherits a minimal PATH, so probing well-known install
/// locations (Homebrew, Docker.app, OrbStack, `~/.docker/bin`) avoids a false "Docker missing".
/// Known-good absolute locations are probed *before* PATH so a hostile PATH can't shadow them
/// with an attacker-controlled binary (the ordering audit S3 also calls for).
public struct DockerExecutableResolver: Sendable {
    private let environment: [String: String]
    private let homeDirectory: String
    private let fileExists: @Sendable (String) -> Bool

    public init(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        homeDirectory: String = NSHomeDirectory(),
        fileExists: @escaping @Sendable (String) -> Bool = { FileManager.default.isExecutableFile(atPath: $0) }
    ) {
        self.environment = environment
        self.homeDirectory = homeDirectory
        self.fileExists = fileExists
    }

    public func resolve() -> String {
        for path in candidates() where fileExists(path) {
            return path
        }
        return "docker"
    }

    private func candidates() -> [String] {
        let knownLocations = [
            "/opt/homebrew/bin/docker",
            "/usr/local/bin/docker",
            "/Applications/Docker.app/Contents/Resources/bin/docker",
            "\(homeDirectory)/.docker/bin/docker",
            "\(homeDirectory)/.orbstack/bin/docker",
            "/usr/bin/docker"
        ]

        let pathExecutables = environment["PATH", default: ""]
            .split(separator: ":")
            .map(String.init)
            .filter { !$0.isEmpty }
            .map { "\($0)/docker" }

        return knownLocations + pathExecutables
    }
}
