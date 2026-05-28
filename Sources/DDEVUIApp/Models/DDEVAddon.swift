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

    public init(
        repository: String,
        description: String,
        version: String? = nil,
        type: AddonType = .unknown,
        dependencies: [String] = [],
        githubURL: URL? = nil
    ) {
        self.repository = repository
        self.description = description
        self.version = version?.nilIfBlank
        self.type = type
        self.dependencies = dependencies
        self.githubURL = githubURL
    }

    public var id: String {
        repository
    }

    public var installName: String {
        repository
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

            guard cells.count >= 2,
                  let repository = cells.first,
                  repository.contains("/"),
                  !repository.lowercased().contains("add-on")
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
            githubURL: rawAddon.githubURL.flatMap(URL.init(string:))
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

    enum CodingKeys: String, CodingKey {
        case title
        case githubURL = "github_url"
        case description
        case user
        case repo
        case tagName = "tag_name"
        case dependencies
        case type
    }
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
