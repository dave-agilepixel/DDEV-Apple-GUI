import Foundation

/// Errors raised when Docker's CLI output cannot be understood. Surfacing schema drift as a
/// typed error is deliberate: silently wrong disk numbers would be worse than a visible failure.
public enum DockerSystemError: Error, Equatable {
    case malformedOutput(String)
}

/// One row of `docker system df` — Images, Containers, Local Volumes, or Build Cache.
public struct DockerUsageCategory: Equatable, Sendable {
    public let totalCount: Int
    public let active: Int
    public let sizeBytes: Int64
    public let reclaimableBytes: Int64

    public init(totalCount: Int, active: Int, sizeBytes: Int64, reclaimableBytes: Int64) {
        self.totalCount = totalCount
        self.active = active
        self.sizeBytes = sizeBytes
        self.reclaimableBytes = reclaimableBytes
    }
}

public struct DockerUsage: Equatable, Sendable {
    public let images: DockerUsageCategory
    public let containers: DockerUsageCategory
    public let volumes: DockerUsageCategory
    public let buildCache: DockerUsageCategory

    public init(
        images: DockerUsageCategory,
        containers: DockerUsageCategory,
        volumes: DockerUsageCategory,
        buildCache: DockerUsageCategory
    ) {
        self.images = images
        self.containers = containers
        self.volumes = volumes
        self.buildCache = buildCache
    }

    public var totalSizeBytes: Int64 {
        images.sizeBytes + containers.sizeBytes + volumes.sizeBytes + buildCache.sizeBytes
    }

    public var totalReclaimableBytes: Int64 {
        images.reclaimableBytes + containers.reclaimableBytes
            + volumes.reclaimableBytes + buildCache.reclaimableBytes
    }

    /// One JSON object per line, keyed by a `Type` field. Note this differs from the `-v`
    /// form, which returns a single object containing arrays.
    private struct Row: Decodable {
        let Active: String
        let Reclaimable: String
        let Size: String
        let TotalCount: String
        let `Type`: String
    }

    public static func decode(_ text: String) throws -> DockerUsage {
        var byType: [String: DockerUsageCategory] = [:]
        let decoder = JSONDecoder()

        for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }

            guard let row = try? decoder.decode(Row.self, from: Data(trimmed.utf8)) else {
                throw DockerSystemError.malformedOutput("unreadable `docker system df` row: \(trimmed)")
            }
            byType[row.Type] = DockerUsageCategory(
                totalCount: Int(row.TotalCount) ?? 0,
                active: Int(row.Active) ?? 0,
                sizeBytes: DockerSize.parse(row.Size) ?? 0,
                reclaimableBytes: DockerSize.parse(row.Reclaimable) ?? 0
            )
        }

        func require(_ type: String) throws -> DockerUsageCategory {
            guard let category = byType[type] else {
                throw DockerSystemError.malformedOutput("`docker system df` did not report \(type)")
            }
            return category
        }

        return DockerUsage(
            images: try require("Images"),
            containers: try require("Containers"),
            volumes: try require("Local Volumes"),
            buildCache: try require("Build Cache")
        )
    }
}
