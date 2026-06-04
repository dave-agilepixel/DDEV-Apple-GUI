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
    /// DDEV's canonical add-on name from `add-on list --installed` (e.g. "bun"), used verbatim for
    /// removal. `nil` for registry/search results, where it's derived from the repository instead.
    public let installedName: String?

    public init(
        repository: String,
        description: String,
        version: String? = nil,
        type: AddonType = .unknown,
        dependencies: [String] = [],
        githubURL: URL? = nil,
        stars: Int? = nil,
        installedName: String? = nil
    ) {
        self.repository = repository
        self.description = description
        self.version = version?.nilIfBlank
        self.type = type
        self.dependencies = dependencies
        self.githubURL = githubURL
        self.stars = stars
        self.installedName = installedName?.nilIfBlank
    }

    public var id: String {
        repository
    }

    /// The identifier accepted by `ddev add-on remove`. For installed add-ons DDEV reports its own
    /// canonical name (e.g. "bun" for `OpenForgeProject/ddev-bun`) — use it verbatim. Otherwise fall
    /// back to the repository's trailing path component; older DDEV versions reject the slashed form.
    public var installName: String {
        installedName ?? repository.split(separator: "/").last.map(String.init) ?? repository
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
            stars: rawAddon.stars,
            installedName: rawAddon.name
        )
    }
}

private struct DDEVAddonJSONPayload: Decodable {
    let raw: [DDEVRawAddon]?
}

/// Decodes a single `raw` add-on entry from either DDEV schema:
/// - registry / search (`ddev add-on list`, `ddev add-on search`) — lowercase `title`, `user`,
///   `repo`, `tag_name`, `dependencies`, `type`, `stars`, `github_url`.
/// - installed (`ddev add-on list --installed`) — PascalCase `Name`, `Repository`, `Version`,
///   `Dependencies`. Each field falls back to its installed-schema counterpart when the
///   registry key is absent, so one type handles both outputs.
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
    /// DDEV's canonical name from installed output (the `Name` key); `nil` for registry/search.
    let name: String?

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
        case installedName = "Name"
        case installedRepository = "Repository"
        case installedVersion = "Version"
        case installedDependencies = "Dependencies"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        // Installed output carries the org/repo identifier under `Repository`; the registry's
        // equivalent is `title`. Resolving both here lets `repository` parsing stay unchanged.
        title = try container.decodeIfPresent(String.self, forKey: .title)
            ?? container.decodeIfPresent(String.self, forKey: .installedRepository)
        githubURL = try container.decodeIfPresent(String.self, forKey: .githubURL)
        description = try container.decodeIfPresent(String.self, forKey: .description)
        user = try container.decodeIfPresent(String.self, forKey: .user)
        repo = try container.decodeIfPresent(String.self, forKey: .repo)
        tagName = try container.decodeIfPresent(String.self, forKey: .tagName)
            ?? container.decodeIfPresent(String.self, forKey: .installedVersion)
        // `Dependencies` is JSON `null` when there are none — `decodeIfPresent` maps that to `nil`.
        dependencies = try container.decodeIfPresent([String].self, forKey: .dependencies)
            ?? container.decodeIfPresent([String].self, forKey: .installedDependencies)
        type = try container.decodeIfPresent(String.self, forKey: .type)
        stars = try container.decodeIfPresent(Int.self, forKey: .stars)
        name = try container.decodeIfPresent(String.self, forKey: .installedName)
    }
}

