import XCTest
@testable import DDEVUIApp

final class DockerSizeTests: XCTestCase {
    func testParsesSIUnits() {
        XCTAssertEqual(DockerSize.parse("42.37GB"), 42_370_000_000)
        XCTAssertEqual(DockerSize.parse("28.67kB"), 28_670)
        XCTAssertEqual(DockerSize.parse("215.7MB"), 215_700_000)
        XCTAssertEqual(DockerSize.parse("1.807TB"), 1_807_000_000_000)
        XCTAssertEqual(DockerSize.parse("0B"), 0)
        XCTAssertEqual(DockerSize.parse("512B"), 512)
    }

    func testStripsPercentageSuffix() {
        // `Reclaimable` carries a percentage on most rows but not on BuildCache.
        XCTAssertEqual(DockerSize.parse("2.4GB (15%)"), 2_400_000_000)
        XCTAssertEqual(DockerSize.parse("1.216GB"), 1_216_000_000)
    }

    func testToleratesWhitespaceAndCasing() {
        XCTAssertEqual(DockerSize.parse("  546MB  "), 546_000_000)
        XCTAssertEqual(DockerSize.parse("546mb"), 546_000_000)
    }

    func testReturnsNilForUnparseableInput() {
        XCTAssertNil(DockerSize.parse(""))
        XCTAssertNil(DockerSize.parse("N/A"))
        XCTAssertNil(DockerSize.parse("GB"))
        XCTAssertNil(DockerSize.parse("12 parsecs"))
    }

    func testFormatsBytesForDisplay() {
        // ByteCountFormatter `.file` is SI/1000-based, matching Docker's own reporting.
        XCTAssertEqual(Int64(0).formattedBytes, "Zero KB")
        XCTAssertTrue(Int64(42_370_000_000).formattedBytes.contains("42"))
        XCTAssertTrue(Int64(42_370_000_000).formattedBytes.hasSuffix("GB"))
    }
}
