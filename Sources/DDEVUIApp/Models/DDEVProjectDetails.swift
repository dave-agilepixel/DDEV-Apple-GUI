import Foundation

/// The rich, *live* slice of `ddev describe -j` consumed by the inspector's per-project panels
/// (Xdebug toggle, DB-credentials, per-service health). Deliberately kept separate from
/// `DDEVProject`: this is fetched on demand per selection and is **never persisted**, because it
/// carries ephemeral container ports and the database password — neither belongs in the on-disk
/// project cache. Only the stable `phpVersion`/`xhguiStatus` are merged back into the cached
/// project via `DDEVProject.applying(details:)`.
public struct DDEVProjectDetails: Equatable, Sendable {
    public let phpVersion: String?
    public let xhguiStatus: DDEVXHGuiStatus?
    public let xdebugEnabled: Bool?
    public let nodeJSVersion: String?
    public let routerStatus: String?
    public let sshAgentStatus: String?
    public let databaseInfo: DDEVDatabaseInfo?
    public let services: [DDEVServiceInfo]

    public init(
        phpVersion: String?,
        xhguiStatus: DDEVXHGuiStatus? = nil,
        xdebugEnabled: Bool? = nil,
        nodeJSVersion: String? = nil,
        routerStatus: String? = nil,
        sshAgentStatus: String? = nil,
        databaseInfo: DDEVDatabaseInfo? = nil,
        services: [DDEVServiceInfo] = []
    ) {
        self.phpVersion = phpVersion
        self.xhguiStatus = xhguiStatus
        self.xdebugEnabled = xdebugEnabled
        self.nodeJSVersion = nodeJSVersion
        self.routerStatus = routerStatus
        self.sshAgentStatus = sshAgentStatus
        self.databaseInfo = databaseInfo
        self.services = services
    }

    /// Services that are add-on/utility UIs worth surfacing in the Open/Launch hub (A1): anything
    /// other than the core web/db containers (whose URLs are already exposed elsewhere) and xhgui
    /// (which has its own dedicated launch), provided it actually exposes a browser URL.
    public var addonServiceLinks: [DDEVServiceLink] {
        services.compactMap { service in
            guard !["web", "db", "xhgui"].contains(service.shortName),
                  let url = service.httpsURL ?? service.httpURL else { return nil }
            return DDEVServiceLink(name: service.shortName, url: url)
        }
    }

    /// The `127.0.0.1:PORT` host port to connect an external DB client to. Prefers the explicit
    /// `dbinfo.published_port`; falls back to the db service's host-port mapping for the in-container
    /// DB port. `nil` when the database port is not published to the host.
    public var databaseHostPort: String? {
        if let published = databaseInfo?.publishedPort, published > 0 {
            return String(published)
        }
        guard let databaseInfo,
              let dbService = services.first(where: { $0.shortName == "db" }),
              let mapping = dbService.hostPorts.first(where: { $0.exposedPort == databaseInfo.port }) else {
            return nil
        }
        return mapping.hostPort
    }

    public static func decodeDescribePayload(_ data: Data) throws -> DDEVProjectDetails {
        let payload = try JSONDecoder().decode(DDEVDescribePayload.self, from: data)
        return payload.raw.toDetails()
    }
}

/// A connectable database credential set from `dbinfo`.
public struct DDEVDatabaseInfo: Equatable, Sendable {
    public let type: String
    public let version: String
    public let host: String
    public let port: String
    public let name: String
    public let username: String
    public let password: String
    /// Host-published port (`0` when the DB port is not exposed to the host).
    public let publishedPort: Int

    public init(
        type: String,
        version: String,
        host: String,
        port: String,
        name: String,
        username: String,
        password: String,
        publishedPort: Int
    ) {
        self.type = type
        self.version = version
        self.host = host
        self.port = port
        self.name = name
        self.username = username
        self.password = password
        self.publishedPort = publishedPort
    }
}

/// One container in the project's service map, with the ephemeral host-port mappings Docker assigned.
public struct DDEVServiceInfo: Equatable, Identifiable, Sendable {
    public var id: String { shortName }
    public let shortName: String
    public let image: String
    public let status: String
    public let hostHTTPURL: URL?
    public let hostHTTPSURL: URL?
    public let httpURL: URL?
    public let httpsURL: URL?
    public let hostPorts: [DDEVHostPortMapping]

    public init(
        shortName: String,
        image: String,
        status: String,
        hostHTTPURL: URL?,
        hostHTTPSURL: URL?,
        httpURL: URL?,
        httpsURL: URL?,
        hostPorts: [DDEVHostPortMapping]
    ) {
        self.shortName = shortName
        self.image = image
        self.status = status
        self.hostHTTPURL = hostHTTPURL
        self.hostHTTPSURL = hostHTTPSURL
        self.httpURL = httpURL
        self.httpsURL = httpsURL
        self.hostPorts = hostPorts
    }

    /// `true` when the container reports a running state (anything else — created/exited/paused — is
    /// surfaced as unhealthy in the services table).
    public var isRunning: Bool { status == "running" }
}

public struct DDEVHostPortMapping: Equatable, Sendable {
    public let exposedPort: String
    public let hostPort: String

    public init(exposedPort: String, hostPort: String) {
        self.exposedPort = exposedPort
        self.hostPort = hostPort
    }
}

/// A named, openable service URL for the Open/Launch hub.
public struct DDEVServiceLink: Equatable, Identifiable, Sendable {
    public var id: String { name }
    public let name: String
    public let url: URL

    public init(name: String, url: URL) {
        self.name = name
        self.url = url
    }
}

// MARK: - Raw decode

private struct DDEVDescribePayload: Decodable {
    let raw: RawDDEVProjectDetails
}

private struct RawDDEVProjectDetails: Decodable {
    let phpVersion: String?
    let nodeJSVersion: String?
    let xhguiStatus: String?
    let xdebugEnabled: Bool?
    let routerStatus: String?
    let sshAgentStatus: String?
    let dbinfo: RawDBInfo?
    let services: [String: RawService]?

    private enum CodingKeys: String, CodingKey {
        case phpVersion = "php_version"
        case nodeJSVersion = "nodejs_version"
        case xhguiStatus = "xhgui_status"
        case xdebugEnabled = "xdebug_enabled"
        case routerStatus = "router_status"
        case sshAgentStatus = "ssh_agent_status"
        case dbinfo
        case services
    }

    func toDetails() -> DDEVProjectDetails {
        DDEVProjectDetails(
            phpVersion: phpVersion,
            xhguiStatus: xhguiStatus.map { DDEVXHGuiStatus(rawValue: $0) ?? .unknown },
            xdebugEnabled: xdebugEnabled,
            nodeJSVersion: nodeJSVersion,
            routerStatus: routerStatus,
            sshAgentStatus: sshAgentStatus,
            databaseInfo: dbinfo?.toDatabaseInfo(),
            services: decodeServices()
        )
    }

    /// Services arrive as an unordered JSON object. Present them web → db → alphabetical so the
    /// table has a stable, sensible order across describes.
    private func decodeServices() -> [DDEVServiceInfo] {
        guard let services else { return [] }
        return services.values
            .map { $0.toServiceInfo() }
            .sorted { lhs, rhs in
                let order = Self.serviceSortRank(lhs.shortName)
                let otherOrder = Self.serviceSortRank(rhs.shortName)
                if order != otherOrder { return order < otherOrder }
                return lhs.shortName < rhs.shortName
            }
    }

    private static func serviceSortRank(_ shortName: String) -> Int {
        switch shortName {
        case "web": 0
        case "db": 1
        default: 2
        }
    }
}

private struct RawDBInfo: Decodable {
    let databaseType: String?
    let databaseVersion: String?
    let host: String?
    let dbPort: String?
    let dbname: String?
    let username: String?
    let password: String?
    let publishedPort: Int?

    private enum CodingKeys: String, CodingKey {
        case databaseType = "database_type"
        case databaseVersion = "database_version"
        case host
        case dbPort
        case dbname
        case username
        case password
        case publishedPort = "published_port"
    }

    func toDatabaseInfo() -> DDEVDatabaseInfo {
        DDEVDatabaseInfo(
            type: databaseType ?? "",
            version: databaseVersion ?? "",
            host: host ?? "",
            port: dbPort ?? "",
            name: dbname ?? "",
            username: username ?? "",
            password: password ?? "",
            publishedPort: publishedPort ?? 0
        )
    }
}

private struct RawService: Decodable {
    let shortName: String?
    let image: String?
    let status: String?
    let hostHTTPURL: String?
    let hostHTTPSURL: String?
    let httpURL: String?
    let httpsURL: String?
    let hostPortsMapping: [RawPortMapping]?

    private enum CodingKeys: String, CodingKey {
        case shortName = "short_name"
        case image
        case status
        case hostHTTPURL = "host_http_url"
        case hostHTTPSURL = "host_https_url"
        case httpURL = "http_url"
        case httpsURL = "https_url"
        case hostPortsMapping = "host_ports_mapping"
    }

    func toServiceInfo() -> DDEVServiceInfo {
        DDEVServiceInfo(
            shortName: shortName ?? "",
            image: image ?? "",
            status: status ?? "",
            hostHTTPURL: DDEVProject.validatedURL(hostHTTPURL ?? ""),
            hostHTTPSURL: DDEVProject.validatedURL(hostHTTPSURL ?? ""),
            httpURL: DDEVProject.validatedURL(httpURL ?? ""),
            httpsURL: DDEVProject.validatedURL(httpsURL ?? ""),
            hostPorts: (hostPortsMapping ?? []).map {
                DDEVHostPortMapping(exposedPort: $0.exposedPort ?? "", hostPort: $0.hostPort ?? "")
            }
        )
    }
}

private struct RawPortMapping: Decodable {
    let exposedPort: String?
    let hostPort: String?

    private enum CodingKeys: String, CodingKey {
        case exposedPort = "exposed_port"
        case hostPort = "host_port"
    }
}
