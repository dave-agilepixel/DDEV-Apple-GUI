import Foundation

public struct DDEVProject: Codable, Equatable, Hashable, Identifiable, Sendable {
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
    public let phpVersion: String?

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
        mutagenStatus: String?,
        phpVersion: String? = nil
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
        self.phpVersion = phpVersion
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
    case asterios
    case backdrop
    case cakephp
    case codeigniter
    case craftcms
    case drupal
    case drupal6
    case drupal7
    case drupal8
    case drupal9
    case drupal10
    case drupal11
    case drupal12
    case generic
    case joomla
    case laravel
    case magento
    case magento2
    case php
    case shopware6
    case silverstripe
    case symfony
    case typo3
    case wordpress
    case wpBedrock = "wp-bedrock"
    case other

    public static let commonProjectTypes: [DDEVProjectType] = [
        .wordpress,
        .wpBedrock,
        .drupal11,
        .drupal10,
        .craftcms,
        .laravel,
        .php,
        .generic
    ]

    public static let advancedProjectTypes: [DDEVProjectType] = supportedConfigTypes
        .filter { !commonProjectTypes.contains($0) }

    public static let supportedConfigTypes: [DDEVProjectType] = [
        .asterios,
        .backdrop,
        .cakephp,
        .codeigniter,
        .craftcms,
        .drupal,
        .drupal6,
        .drupal7,
        .drupal8,
        .drupal9,
        .drupal10,
        .drupal11,
        .drupal12,
        .generic,
        .joomla,
        .laravel,
        .magento,
        .magento2,
        .php,
        .shopware6,
        .silverstripe,
        .symfony,
        .typo3,
        .wordpress,
        .wpBedrock
    ]

    public var displayName: String {
        switch self {
        case .asterios: "Asterios"
        case .backdrop: "Backdrop"
        case .cakephp: "CakePHP"
        case .codeigniter: "CodeIgniter"
        case .craftcms: "Craft CMS"
        case .drupal: "Drupal"
        case .drupal6: "Drupal 6"
        case .drupal7: "Drupal 7"
        case .drupal8: "Drupal 8"
        case .drupal9: "Drupal 9"
        case .drupal10: "Drupal 10"
        case .drupal11: "Drupal 11"
        case .drupal12: "Drupal 12"
        case .generic: "Generic"
        case .joomla: "Joomla"
        case .laravel: "Laravel"
        case .magento: "Magento"
        case .magento2: "Magento 2"
        case .php: "PHP"
        case .shopware6: "Shopware 6"
        case .silverstripe: "Silverstripe"
        case .symfony: "Symfony"
        case .typo3: "TYPO3"
        case .wordpress: "WordPress"
        case .wpBedrock: "WP Bedrock"
        case .other: "Other"
        }
    }

    public var symbol: String {
        switch self {
        case .wordpress, .wpBedrock: "w.square"
        case .drupal, .drupal6, .drupal7, .drupal8, .drupal9, .drupal10, .drupal11, .drupal12: "drop"
        case .laravel: "l.square"
        case .craftcms: "c.square"
        case .typo3: "t.square"
        case .magento, .magento2, .shopware6: "cart"
        case .php, .symfony, .cakephp, .codeigniter: "chevron.left.forwardslash.chevron.right"
        case .joomla, .backdrop, .silverstripe, .asterios: "globe"
        case .generic: "folder"
        case .other: "questionmark.square.dashed"
        }
    }

    public var family: DDEVProjectFamily {
        switch self {
        case .wordpress, .wpBedrock:
            .wordpress
        case .drupal, .drupal6, .drupal7, .drupal8, .drupal9, .drupal10, .drupal11, .drupal12:
            .drupal
        case .laravel, .symfony, .cakephp, .codeigniter:
            .framework
        case .magento, .magento2, .shopware6:
            .commerce
        case .backdrop, .craftcms, .joomla, .silverstripe, .typo3, .asterios:
            .cms
        case .php, .generic:
            .generic
        case .other:
            .other
        }
    }
}

public enum DDEVProjectFamily: String, Equatable, Sendable {
    case wordpress
    case drupal
    case framework
    case commerce
    case cms
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
            mutagenStatus: raw.mutagenStatus,
            phpVersion: raw.phpVersion
        )
    }

    public func applying(details: DDEVProjectDetails) -> DDEVProject {
        DDEVProject(
            name: name,
            appRoot: appRoot,
            shortRoot: shortRoot,
            status: status,
            statusDescription: statusDescription,
            projectType: projectType,
            docroot: docroot,
            primaryURL: primaryURL,
            httpURL: httpURL,
            httpsURL: httpsURL,
            mailpitURL: mailpitURL,
            mailpitHTTPSURL: mailpitHTTPSURL,
            xhguiURL: xhguiURL,
            xhguiHTTPSURL: xhguiHTTPSURL,
            mutagenEnabled: mutagenEnabled,
            mutagenStatus: mutagenStatus,
            phpVersion: details.phpVersion
        )
    }
}

public struct DDEVProjectDetails: Equatable, Sendable {
    public let phpVersion: String?

    public init(phpVersion: String?) {
        self.phpVersion = phpVersion
    }

    public static func decodeDescribePayload(_ data: Data) throws -> DDEVProjectDetails {
        let payload = try JSONDecoder().decode(DDEVDescribePayload.self, from: data)
        return DDEVProjectDetails(phpVersion: payload.raw.phpVersion)
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
    let phpVersion: String?

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
        case phpVersion = "php_version"
    }
}

private struct DDEVDescribePayload: Decodable {
    let raw: RawDDEVProjectDetails
}

private struct RawDDEVProjectDetails: Decodable {
    let phpVersion: String?

    private enum CodingKeys: String, CodingKey {
        case phpVersion = "php_version"
    }
}
