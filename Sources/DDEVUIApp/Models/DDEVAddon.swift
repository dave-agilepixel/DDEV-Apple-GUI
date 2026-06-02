import Foundation

public struct DDEVAddon: Equatable, Identifiable, Sendable {
    public enum AddonType: String, Codable, Sendable {
        case official
        case contrib
        case unknown
    }

    public let repository: String
    public let description: String
    public let version: String?
    public let type: AddonType
    public let dependencies: [String]
    public let githubURL: URL?
    /// GitHub star count from the registry (A16), `nil` when unknown (e.g. table-parsed output).
    public let stars: Int?

    public init(
        repository: String,
        description: String,
        version: String? = nil,
        type: AddonType = .unknown,
        dependencies: [String] = [],
        githubURL: URL? = nil,
        stars: Int? = nil
    ) {
        self.repository = repository
        self.description = description
        self.version = version?.nilIfBlank
        self.type = type
        self.dependencies = dependencies
        self.githubURL = githubURL
        self.stars = stars
    }

    public var id: String {
        repository
    }

    /// The identifier accepted by `ddev add-on remove`. Older DDEV versions reject the
    /// slashed `org/repo` form; the trailing path component is the safe-compatible form.
    public var installName: String {
        repository.split(separator: "/").last.map(String.init) ?? repository
    }

    public var isOfficial: Bool {
        type == .official || repository.hasPrefix("ddev/")
    }

    public static let recommendedOfficial: [DDEVAddon] = [
        DDEVAddon(repository: "ddev/ddev-redis", description: "Redis cache and data store service for DDEV", type: .official),
        DDEVAddon(repository: "ddev/ddev-memcached", description: "Memcached service for DDEV", type: .official),
        DDEVAddon(repository: "ddev/ddev-mongodb", description: "MongoDB service for DDEV", type: .official),
        DDEVAddon(repository: "ddev/ddev-adminer", description: "Adminer database browser for DDEV", type: .official),
        DDEVAddon(repository: "ddev/ddev-phpmyadmin", description: "phpMyAdmin database browser for DDEV", type: .official),
        DDEVAddon(repository: "ddev/ddev-redis-insight", description: "Redis Insight Web UI for DDEV Redis", type: .official),
        DDEVAddon(repository: "ddev/ddev-browsersync", description: "Live reload and HTTPS auto-refresh for DDEV", type: .official),
        DDEVAddon(repository: "ddev/ddev-solr", description: "Apache Solr search service for DDEV", type: .official),
        DDEVAddon(repository: "ddev/ddev-elasticsearch", description: "Elasticsearch service for DDEV", type: .official),
        DDEVAddon(repository: "ddev/ddev-opensearch", description: "OpenSearch service for DDEV", type: .official)
    ]

    public static func parseListOutput(_ output: String) throws -> [DDEVAddon] {
        if let addons = try parseJSONPayload(output), !addons.isEmpty {
            return addons
        }

        return parseTableOutput(output)
    }

    private static func parseJSONPayload(_ output: String) throws -> [DDEVAddon]? {
        guard let data = output.data(using: .utf8),
              let payload = try? JSONDecoder().decode(DDEVAddonJSONPayload.self, from: data)
        else {
            return nil
        }

        return payload.raw?.compactMap(DDEVAddon.init(rawAddon:))
    }

    private static func parseTableOutput(_ output: String) -> [DDEVAddon] {
        var addons: [DDEVAddon] = []

        for line in output.split(whereSeparator: \.isNewline).map(String.init) {
            guard line.contains("│") else { continue }

            let cells = line
                .split(separator: "│", omittingEmptySubsequences: false)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }

            // `contains("/")` already excludes the "ADD-ON" header row and box-drawing
            // separators — no additional substring guard needed (it used to incorrectly
            // drop repositories such as `acme/awesome-add-on`).
            guard cells.count >= 2,
                  let repository = cells.first,
                  repository.contains("/")
            else {
                continue
            }

            var description = cells[1]
            let isMarkedOfficial = description.hasSuffix("*")
            if isMarkedOfficial {
                description = String(description.dropLast()).trimmingCharacters(in: .whitespacesAndNewlines)
            }

            addons.append(
                DDEVAddon(
                    repository: repository,
                    description: description,
                    type: isMarkedOfficial || repository.hasPrefix("ddev/") ? .official : .contrib
                )
            )
        }

        return addons
    }

    private init?(rawAddon: DDEVRawAddon) {
        let repository = rawAddon.title?.nilIfBlank
            ?? [rawAddon.user?.nilIfBlank, rawAddon.repo?.nilIfBlank]
                .compactMap { $0 }
                .joined(separator: "/")

        guard !repository.isEmpty else { return nil }

        self.init(
            repository: repository,
            description: rawAddon.description ?? "",
            version: rawAddon.tagName,
            type: AddonType(rawValue: rawAddon.type ?? "") ?? .unknown,
            dependencies: rawAddon.dependencies ?? [],
            githubURL: rawAddon.githubURL.flatMap(URL.init(string:)),
            stars: rawAddon.stars
        )
    }
}

private struct DDEVAddonJSONPayload: Decodable {
    let raw: [DDEVRawAddon]?
}

private struct DDEVRawAddon: Decodable {
    let title: String?
    let githubURL: String?
    let description: String?
    let user: String?
    let repo: String?
    let tagName: String?
    let dependencies: [String]?
    let type: String?
    let stars: Int?

    enum CodingKeys: String, CodingKey {
        case title
        case githubURL = "github_url"
        case description
        case user
        case repo
        case tagName = "tag_name"
        case dependencies
        case type
        case stars
    }
}

