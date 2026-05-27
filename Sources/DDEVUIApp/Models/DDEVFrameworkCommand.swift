import Foundation

public struct DDEVFrameworkCommand: Equatable, Identifiable, Sendable {
    public let id: String
    public let title: String
    public let groupTitle: String
    public let systemImage: String
    public let arguments: [String]
    public let risk: DDEVCommandRisk
    public let confirmationMessage: String?

    public init(
        id: String,
        title: String,
        groupTitle: String,
        systemImage: String,
        arguments: [String],
        risk: DDEVCommandRisk = .normal,
        confirmationMessage: String? = nil
    ) {
        self.id = id
        self.title = title
        self.groupTitle = groupTitle
        self.systemImage = systemImage
        self.arguments = arguments
        self.risk = risk
        self.confirmationMessage = confirmationMessage
    }

    public var requiresConfirmation: Bool {
        risk != .normal
    }

    public static func presets(for projectType: DDEVProjectType) -> [DDEVFrameworkCommand] {
        switch projectType {
        case .wordpress, .wpBedrock:
            wordpressCommands
        case .laravel:
            laravelCommands
        case .drupal, .drupal6, .drupal7, .drupal8, .drupal9, .drupal10, .drupal11, .drupal12, .backdrop:
            drushCommands
        case .magento, .magento2:
            magentoCommands
        case .craftcms:
            craftCommands
        case .typo3:
            typo3Commands
        case .symfony:
            composerCommands + symfonyCommands
        case .php, .generic:
            composerCommands
        case .asterios, .cakephp, .codeigniter, .joomla, .shopware6, .silverstripe, .other:
            []
        }
    }
}

public enum DDEVCommandRisk: Equatable, Sendable {
    case normal
    case highImpact
    case destructive
}

private extension DDEVFrameworkCommand {
    static let wordpressCommands = [
        DDEVFrameworkCommand(
            id: "wordpress.update-core",
            title: "Update Core",
            groupTitle: "WordPress",
            systemImage: "shippingbox.and.arrow.backward",
            arguments: ["wp", "core", "update"]
        ),
        DDEVFrameworkCommand(
            id: "wordpress.update-plugins",
            title: "Update Plugins",
            groupTitle: "WordPress",
            systemImage: "puzzlepiece.extension",
            arguments: ["wp", "plugin", "update", "--all"],
            risk: .highImpact,
            confirmationMessage: "Update all WordPress plugins for this project?"
        ),
        DDEVFrameworkCommand(
            id: "wordpress.update-themes",
            title: "Update Themes",
            groupTitle: "WordPress",
            systemImage: "paintpalette",
            arguments: ["wp", "theme", "update", "--all"],
            risk: .highImpact,
            confirmationMessage: "Update all WordPress themes for this project?"
        ),
        DDEVFrameworkCommand(
            id: "wordpress.flush-cache",
            title: "Flush Cache",
            groupTitle: "WordPress",
            systemImage: "trash",
            arguments: ["wp", "cache", "flush"]
        )
    ]

    static let laravelCommands = [
        DDEVFrameworkCommand(
            id: "laravel.migrate",
            title: "Migrate",
            groupTitle: "Laravel",
            systemImage: "arrow.up.arrow.down",
            arguments: ["artisan", "migrate"],
            risk: .highImpact,
            confirmationMessage: "Run Laravel database migrations for this project?"
        ),
        DDEVFrameworkCommand(
            id: "laravel.migrate-fresh-seed",
            title: "Fresh Migrate Seed",
            groupTitle: "Laravel",
            systemImage: "exclamationmark.triangle",
            arguments: ["artisan", "migrate:fresh", "--seed"],
            risk: .destructive,
            confirmationMessage: "This drops and rebuilds the Laravel database before seeding it."
        ),
        DDEVFrameworkCommand(
            id: "laravel.cache-clear",
            title: "Clear Cache",
            groupTitle: "Laravel",
            systemImage: "trash",
            arguments: ["artisan", "cache:clear"]
        ),
        DDEVFrameworkCommand(
            id: "laravel.route-list",
            title: "List Routes",
            groupTitle: "Laravel",
            systemImage: "list.bullet.rectangle",
            arguments: ["artisan", "route:list"]
        )
    ]

    static let drushCommands = [
        DDEVFrameworkCommand(
            id: "drush.cache-rebuild",
            title: "Rebuild Cache",
            groupTitle: "Drush",
            systemImage: "arrow.clockwise",
            arguments: ["drush", "cr"]
        ),
        DDEVFrameworkCommand(
            id: "drush.database-updates",
            title: "Database Updates",
            groupTitle: "Drush",
            systemImage: "cylinder.split.1x2",
            arguments: ["drush", "updb", "-y"],
            risk: .highImpact,
            confirmationMessage: "Run Drupal database updates for this project?"
        ),
        DDEVFrameworkCommand(
            id: "drush.config-import",
            title: "Import Config",
            groupTitle: "Drush",
            systemImage: "square.and.arrow.down",
            arguments: ["drush", "cim", "-y"],
            risk: .highImpact,
            confirmationMessage: "Import Drupal configuration into this project?"
        ),
        DDEVFrameworkCommand(
            id: "drush.config-export",
            title: "Export Config",
            groupTitle: "Drush",
            systemImage: "square.and.arrow.up",
            arguments: ["drush", "cex", "-y"],
            risk: .highImpact,
            confirmationMessage: "Export Drupal configuration from this project?"
        )
    ]

    static let magentoCommands = [
        DDEVFrameworkCommand(
            id: "magento.cache-flush",
            title: "Flush Cache",
            groupTitle: "Magento",
            systemImage: "trash",
            arguments: ["magento", "cache:flush"]
        ),
        DDEVFrameworkCommand(
            id: "magento.setup-upgrade",
            title: "Setup Upgrade",
            groupTitle: "Magento",
            systemImage: "arrow.up.circle",
            arguments: ["magento", "setup:upgrade"],
            risk: .highImpact,
            confirmationMessage: "Run Magento setup upgrade for this project?"
        ),
        DDEVFrameworkCommand(
            id: "magento.indexer-reindex",
            title: "Reindex",
            groupTitle: "Magento",
            systemImage: "arrow.triangle.2.circlepath",
            arguments: ["magento", "indexer:reindex"]
        )
    ]

    static let craftCommands = [
        DDEVFrameworkCommand(
            id: "craft.clear-caches",
            title: "Clear Caches",
            groupTitle: "Craft CMS",
            systemImage: "trash",
            arguments: ["craft", "clear-caches/all"]
        ),
        DDEVFrameworkCommand(
            id: "craft.migrate-all",
            title: "Run Migrations",
            groupTitle: "Craft CMS",
            systemImage: "arrow.up.arrow.down",
            arguments: ["craft", "migrate/all"],
            risk: .highImpact,
            confirmationMessage: "Run Craft CMS migrations for this project?"
        )
    ]

    static let typo3Commands = [
        DDEVFrameworkCommand(
            id: "typo3.cache-flush",
            title: "Flush Cache",
            groupTitle: "TYPO3",
            systemImage: "trash",
            arguments: ["typo3", "cache:flush"]
        ),
        DDEVFrameworkCommand(
            id: "typo3.database-updateschema",
            title: "Update Schema",
            groupTitle: "TYPO3",
            systemImage: "cylinder.split.1x2",
            arguments: ["typo3", "database:updateschema"],
            risk: .highImpact,
            confirmationMessage: "Run TYPO3 database schema updates for this project?"
        )
    ]

    static let composerCommands = [
        DDEVFrameworkCommand(
            id: "composer.install",
            title: "Composer Install",
            groupTitle: "Composer",
            systemImage: "shippingbox",
            arguments: ["composer", "install"]
        ),
        DDEVFrameworkCommand(
            id: "composer.update",
            title: "Composer Update",
            groupTitle: "Composer",
            systemImage: "arrow.up.circle",
            arguments: ["composer", "update"],
            risk: .highImpact,
            confirmationMessage: "Run Composer update for this project?"
        )
    ]

    static let symfonyCommands = [
        DDEVFrameworkCommand(
            id: "symfony.cache-clear",
            title: "Clear Symfony Cache",
            groupTitle: "Symfony",
            systemImage: "trash",
            arguments: ["exec", "bin/console", "cache:clear"]
        )
    ]
}
