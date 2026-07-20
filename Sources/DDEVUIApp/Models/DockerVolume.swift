import Foundation

/// A local Docker volume as reported by `docker system df -v --format json`.
public struct DockerVolume: Equatable, Sendable {
    public let name: String
    public let sizeBytes: Int64
    /// Number of containers currently using this volume. Docker reports it directly, so no
    /// cross-reference against `docker ps` is needed.
    public let links: Int

    public init(name: String, sizeBytes: Int64, links: Int) {
        self.name = name
        self.sizeBytes = sizeBytes
        self.links = links
    }

    public var isInUse: Bool { links > 0 }

    /// The `-v` form returns a single object containing arrays — unlike the plain
    /// `docker system df --format json`, which is JSON-lines.
    private struct Payload: Decodable {
        struct Volume: Decodable {
            let Name: String
            let Size: String
            let Links: String
        }
        let Volumes: [Volume]
    }

    public static func decodeList(_ text: String) throws -> [DockerVolume] {
        guard let payload = try? JSONDecoder().decode(Payload.self, from: Data(text.utf8)) else {
            throw DockerSystemError.malformedOutput("unreadable `docker system df -v` payload")
        }
        return payload.Volumes.map { volume in
            DockerVolume(
                name: volume.Name,
                sizeBytes: DockerSize.parse(volume.Size) ?? 0,
                links: Int(volume.Links) ?? 0
            )
        }
    }
}
