import Foundation

public struct DDEVProject: Equatable, Hashable, Identifiable, Sendable {
    public var id: String { name }

    public let name: String
    public let appRoot: String
    public let shortRoot: String
    public let status: DDEVProjectStatus
    public let statusDescription: String
    public let projectType: DDEVProjectType
    public let docroot: String
    public let primaryURL: URL?
    public let httpURL: URL?
    public let httpsURL: URL?
    public let mailpitURL: URL?
    public let mailpitHTTPSURL: URL?
    public let xhguiURL: URL?
    public let xhguiHTTPSURL: URL?
    public let mutagenEnabled: Bool
    public let mutagenStatus: String?

    public init(
        name: String,
        appRoot: String,
        shortRoot: String,
        status: DDEVProjectStatus,
        statusDescription: String,
        projectType: DDEVProjectType,
        docroot: String,
        primaryURL: URL?,
        httpURL: URL?,
        httpsURL: URL?,
        mailpitURL: URL?,
        mailpitHTTPSURL: URL?,
        xhguiURL: URL?,
        xhguiHTTPSURL: URL?,
        mutagenEnabled: Bool,
        mutagenStatus: String?
    ) {
        self.name = name
        self.appRoot = appRoot
        self.shortRoot = shortRoot
        self.status = status
        self.statusDescription = statusDescription
        self.projectType = projectType
        self.docroot = docroot
        self.primaryURL = primaryURL
        self.httpURL = httpURL
        self.httpsURL = httpsURL
        self.mailpitURL = mailpitURL
        self.mailpitHTTPSURL = mailpitHTTPSURL
        self.xhguiURL = xhguiURL
        self.xhguiHTTPSURL = xhguiHTTPSURL
        self.mutagenEnabled = mutagenEnabled
        self.mutagenStatus = mutagenStatus
    }

    public var isWordPress: Bool {
        projectType == .wordpress || projectType == .wpBedrock
    }
}

public enum DDEVProjectStatus: String, Codable, Sendable {
    case running
    case paused
    case stopped
    case unknown
}

public enum DDEVProjectType: String, Codable, CaseIterable, Sendable {
    case wordpress
    case wpBedrock = "wp-bedrock"
    case laravel
    case generic
    case other
}

extension DDEVProject {
    public static func decodeListPayload(_ data: Data) throws -> [DDEVProject] {
        let payload = try JSONDecoder().decode(DDEVListPayload.self, from: data)
        return payload.raw.map(DDEVProject.init(raw:))
    }

    private init(raw: RawDDEVProject) {
        self.init(
            name: raw.name,
            appRoot: raw.approot,
            shortRoot: raw.shortroot,
            status: DDEVProjectStatus(rawValue: raw.status) ?? .unknown,
            statusDescription: raw.statusDesc,
            projectType: DDEVProjectType(rawValue: raw.type) ?? .other,
            docroot: raw.docroot,
            primaryURL: URL(string: raw.primaryURL),
            httpURL: URL(string: raw.httpURL),
            httpsURL: URL(string: raw.httpsURL),
            mailpitURL: URL(string: raw.mailpitURL),
            mailpitHTTPSURL: URL(string: raw.mailpitHTTPSURL),
            xhguiURL: URL(string: raw.xhguiURL),
            xhguiHTTPSURL: URL(string: raw.xhguiHTTPSURL),
            mutagenEnabled: raw.mutagenEnabled,
            mutagenStatus: raw.mutagenStatus
        )
    }
}

private struct DDEVListPayload: Decodable {
    let raw: [RawDDEVProject]
}

private struct RawDDEVProject: Decodable {
    let name: String
    let approot: String
    let shortroot: String
    let status: String
    let statusDesc: String
    let type: String
    let docroot: String
    let primaryURL: String
    let httpURL: String
    let httpsURL: String
    let mailpitURL: String
    let mailpitHTTPSURL: String
    let xhguiURL: String
    let xhguiHTTPSURL: String
    let mutagenEnabled: Bool
    let mutagenStatus: String?

    private enum CodingKeys: String, CodingKey {
        case name
        case approot
        case shortroot
        case status
        case statusDesc = "status_desc"
        case type
        case docroot
        case primaryURL = "primary_url"
        case httpURL = "httpurl"
        case httpsURL = "httpsurl"
        case mailpitURL = "mailpit_url"
        case mailpitHTTPSURL = "mailpit_https_url"
        case xhguiURL = "xhgui_url"
        case xhguiHTTPSURL = "xhgui_https_url"
        case mutagenEnabled = "mutagen_enabled"
        case mutagenStatus = "mutagen_status"
    }
}
