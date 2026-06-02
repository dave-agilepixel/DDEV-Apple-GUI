import XCTest
@testable import DDEVUIApp

final class DDEVDatabaseMigrationTests: XCTestCase {
    func testOnlyMySQLAndMariaDBSupportMigration() {
        XCTAssertTrue(DDEVDatabaseType.mysql.supportsMigration)
        XCTAssertTrue(DDEVDatabaseType.mariadb.supportsMigration)
        XCTAssertFalse(DDEVDatabaseType.postgres.supportsMigration, "migrate-database is MySQL/MariaDB only")
    }
}
