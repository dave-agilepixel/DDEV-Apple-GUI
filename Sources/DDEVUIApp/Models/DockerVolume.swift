import Foundation

/// A local Docker volume as reported by `docker system df -v --format json`.
public struct DockerVolume: Equatable, Sendable {
    public let name: String
    public let sizeBytes: Int64
    /// Number of containers currently using this volume. Docker reports it directly, so no
    /// cross-reference against `docker ps` is needed.
    ///
    /// This is the sole signal guarding deletion (`isInUse`), so decoding is fail-safe: an
    /// unparseable or negative value is coerced to a positive count rather than zero, so an
    /// unknown link count always reads as "in use" and never as "safe to delete".
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
            // `links` is the only signal guarding volume deletion (see `isInUse`), so this must
            // fail towards "in use" rather than "not in use". A genuinely parsed non-negative
            // count is trusted as-is (including a real `0`); an unparseable value, or a negative
            // (nonsense) parsed value, is coerced to 1 rather than 0. Unlike the `Size` fallback
            // below, getting this wrong risks deleting a volume that is actually still attached
            // to a container.
            let links: Int
            if let parsedLinks = Int(volume.Links), parsedLinks >= 0 {
                links = parsedLinks
            } else {
                links = 1
            }
            return DockerVolume(
                name: volume.Name,
                sizeBytes: DockerSize.parse(volume.Size) ?? 0,
                links: links
            )
        }
    }
}
