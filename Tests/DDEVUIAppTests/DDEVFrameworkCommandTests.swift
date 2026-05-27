import XCTest
@testable import DDEVUIApp

final class DDEVFrameworkCommandTests: XCTestCase {
    func testWordPressCommandsIncludeSafeUpdatesAndCacheFlush() {
        let commands = DDEVFrameworkCommand.presets(for: .wordpress)

        XCTAssertEqual(commands.map(\.title), [
            "Update Core",
            "Update Plugins",
            "Update Themes",
            "Flush Cache"
        ])
        XCTAssertEqual(commands.map(\.arguments), [
            ["wp", "core", "update"],
            ["wp", "plugin", "update", "--all"],
            ["wp", "theme", "update", "--all"],
            ["wp", "cache", "flush"]
        ])
        XCTAssertEqual(commands.map(\.risk), [.normal, .highImpact, .highImpact, .normal])
    }

    func testLaravelCommandsMapToArtisanPresetsWithFreshMigrationGuarded() {
        let commands = DDEVFrameworkCommand.presets(for: .laravel)

        XCTAssertEqual(commands.map(\.arguments), [
            ["artisan", "migrate"],
            ["artisan", "migrate:fresh", "--seed"],
            ["artisan", "cache:clear"],
            ["artisan", "route:list"]
        ])
        XCTAssertEqual(commands.first { $0.title == "Fresh Migrate Seed" }?.risk, .destructive)
        XCTAssertNotNil(commands.first { $0.title == "Fresh Migrate Seed" }?.confirmationMessage)
    }

    func testDrupalAndBackdropCommandsUseDrushPresets() {
        for type in [DDEVProjectType.drupal11, .backdrop] {
            let commands = DDEVFrameworkCommand.presets(for: type)

            XCTAssertEqual(commands.map(\.arguments), [
                ["drush", "cr"],
                ["drush", "updb", "-y"],
                ["drush", "cim", "-y"],
                ["drush", "cex", "-y"]
            ])
            XCTAssertEqual(commands.first?.risk, .normal)
            XCTAssertTrue(commands.dropFirst().allSatisfy(\.requiresConfirmation))
        }
    }

    func testCommerceCMSAndGenericCommandsAreTypeAware() {
        XCTAssertEqual(DDEVFrameworkCommand.presets(for: .magento2).map(\.arguments), [
            ["magento", "cache:flush"],
            ["magento", "setup:upgrade"],
            ["magento", "indexer:reindex"]
        ])
        XCTAssertEqual(DDEVFrameworkCommand.presets(for: .craftcms).map(\.arguments), [
            ["craft", "clear-caches/all"],
            ["craft", "migrate/all"]
        ])
        XCTAssertEqual(DDEVFrameworkCommand.presets(for: .typo3).map(\.arguments), [
            ["typo3", "cache:flush"],
            ["typo3", "database:updateschema"]
        ])
        XCTAssertEqual(DDEVFrameworkCommand.presets(for: .symfony).map(\.arguments), [
            ["composer", "install"],
            ["composer", "update"],
            ["exec", "bin/console", "cache:clear"]
        ])
        XCTAssertEqual(DDEVFrameworkCommand.presets(for: .php).map(\.arguments), [
            ["composer", "install"],
            ["composer", "update"]
        ])
    }

    func testUnsupportedProjectTypesDoNotOfferGuessyCommands() {
        XCTAssertEqual(DDEVFrameworkCommand.presets(for: .other), [])
        XCTAssertEqual(DDEVFrameworkCommand.presets(for: .asterios), [])
    }
}
