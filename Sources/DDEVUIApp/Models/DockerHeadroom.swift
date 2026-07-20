import Foundation

/// Free space on the Docker VM's filesystem — the figure that actually governs whether a
/// `ddev start` succeeds. Derived from `df -Pk` run inside a container, because the size of
/// `Docker.raw` on the host says nothing about how full the VM believes it is.
public struct DockerHeadroom: Equatable, Sendable {
    public let totalBytes: Int64
    public let usedBytes: Int64
    public let availableBytes: Int64

    public init(totalBytes: Int64, usedBytes: Int64, availableBytes: Int64) {
        self.totalBytes = totalBytes
        self.usedBytes = usedBytes
        self.availableBytes = availableBytes
    }

    /// Used as a proportion of usable space. Mirrors df's own Capacity column, which excludes
    /// reserved blocks — so this is deliberately not `usedBytes / totalBytes`.
    public var usedFraction: Double {
        let usable = usedBytes + availableBytes
        guard usable > 0 else { return 0 }
        return Double(usedBytes) / Double(usable)
    }

    public var percentUsed: Int {
        Int((usedFraction * 100).rounded())
    }

    /// Parses POSIX `df -Pk` output. Only column *position* is trusted: the two probe paths
    /// report different filesystem names (`overlay` vs `/dev/vda1`) and mount points
    /// (`/` vs `/probe`), so neither may be matched on.
    public static func parse(_ text: String) throws -> DockerHeadroom {
        let rows = text
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.hasPrefix("Filesystem") }

        guard let row = rows.last else {
            throw DockerSystemError.malformedOutput("`df` returned no data rows")
        }

        let fields = row.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        guard fields.count >= 6,
              let blocks = Int64(fields[1]),
              let used = Int64(fields[2]),
              let available = Int64(fields[3])
        else {
            throw DockerSystemError.malformedOutput("unreadable `df` row: \(row)")
        }

        return DockerHeadroom(
            totalBytes: blocks * 1024,
            usedBytes: used * 1024,
            availableBytes: available * 1024
        )
    }
}
