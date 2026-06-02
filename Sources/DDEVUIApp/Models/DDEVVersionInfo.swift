import Foundation

/// The decoded payload of `ddev version -j` — DDEV's own version plus the component image tags
/// (web/db/router/ssh-agent/xhgui) and the host toolchain (Docker, docker-compose, Mutagen).
/// `ddev version -j` is a log envelope whose machine-readable map lives under `.raw` as a flat
/// `[String: String]`; this mirrors that map verbatim (nothing dropped) and adds typed accessors
/// for the handful of fields worth highlighting. Read-only and not persisted.
public struct DDEVVersionInfo: Equatable, Sendable {
    public struct Item: Equatable, Sendable, Identifiable {
        public let key: String
        public let value: String
        public var id: String { key }

        public init(key: String, value: String) {
            self.key = key
            self.value = value
        }
    }

    /// Every `.raw` entry, case-insensitively sorted by key so the rendered list is stable run-to-run.
    public let items: [Item]

    public init(items: [Item]) {
        self.items = items
    }

    public func value(for key: String) -> String? {
        items.first { $0.key == key }?.value
    }

    // Typed highlights — the fields most worth surfacing prominently in the About panel.
    public var ddevVersion: String? { value(for: "DDEV version") }
    public var architecture: String? { value(for: "architecture") }
    public var os: String? { value(for: "os") }
    public var docker: String? { value(for: "docker") }
    public var dockerCompose: String? { value(for: "docker-compose") }
    public var mutagen: String? { value(for: "mutagen") }
    public var webImage: String? { value(for: "web") }
    public var dbImage: String? { value(for: "db") }
    public var routerImage: String? { value(for: "router") }
    public var sshAgentImage: String? { value(for: "ddev-ssh-agent") }
    public var xhguiImage: String? { value(for: "xhgui-image") }

    public static func decodeVersionPayload(_ data: Data) throws -> DDEVVersionInfo {
        let payload = try JSONDecoder().decode(Payload.self, from: data)
        let items = payload.raw
            .map { Item(key: $0.key, value: $0.value) }
            .sorted { $0.key.localizedCaseInsensitiveCompare($1.key) == .orderedAscending }
        return DDEVVersionInfo(items: items)
    }

    private struct Payload: Decodable {
        let raw: [String: String]
    }
}
