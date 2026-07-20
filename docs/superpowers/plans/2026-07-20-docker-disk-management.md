# Docker Disk Management Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Warn the user in the menu bar before the Docker VM disk fills, and give them a Docker Disk screen that reclaims space safely without ever bulk-deleting a project database.

**Architecture:** A new `DockerSystemService` (mirroring `DDEVCommandService`: injected `CommandRunning`, returns decoded models) reads `docker system df` and probes VM headroom via `df` inside a container. A pure, I/O-free `ReclaimPlanner` classifies every volume and decides what is safe to remove. A `DockerDiskViewModel` joins them and feeds both the menu-bar badge and a new sidebar screen.

**Tech Stack:** Swift 6.2, SwiftUI, `@Observable`, XCTest, SwiftPM. macOS 26+.

**Spec:** `docs/superpowers/specs/2026-07-20-docker-disk-management-design.md`

## Global Constraints

- **Swift tools 6.2**, platform `.macOS(.v26)`. Target `DDEVUIApp`, tests `DDEVUIAppTests`.
- **No new third-party dependencies.** `Package.swift` has zero and must keep zero.
- **All new types are `Sendable`.** Value types `Equatable, Sendable`; services `Sendable`; view models `@MainActor @Observable`.
- **UK English** in all comments, doc comments, and user-facing copy (e.g. "behaviour", "colour", "unauthorised").
- **Tests are XCTest**, not swift-testing. Run with `swift test`.
- **Never `any`-type or force-unwrap** parsed CLI output. Malformed input throws a typed error.
- **`docker` is resolved via `DockerExecutableResolver().resolve()`**, never hardcoded and never bare `"docker"` in production paths.
- **Commit style:** Conventional Commits, `type: Subject`, imperative, ≤50 chars, capitalised, no trailing full stop.
- **The safety rule** (from the spec) is implemented in exactly one place, `ReclaimPlanner`:
  > A volume is bulk-eligible if and only if it is `.mutagen` and not `.running`, **or** it belongs to an `.orphaned` project. A `.database` volume for a registered project is never in a bulk plan.

## File Structure

**Create:**
| File | Responsibility |
| --- | --- |
| `Sources/DDEVUIApp/Utilities/DockerSize.swift` | Parse Docker's human size strings; format bytes for display |
| `Sources/DDEVUIApp/Models/DockerUsage.swift` | `DockerUsage` + `DockerUsageCategory` + JSON-lines decoding |
| `Sources/DDEVUIApp/Models/DockerHeadroom.swift` | `DockerHeadroom` + `df -Pk` parsing |
| `Sources/DDEVUIApp/Models/DockerVolume.swift` | `DockerVolume` + `-v --format json` decoding |
| `Sources/DDEVUIApp/Models/ReclaimPlan.swift` | `VolumeKind`, `ProjectState`, `ClassifiedVolume`, `ReclaimAction`, `ReclaimItem`, `ReclaimPlan` |
| `Sources/DDEVUIApp/Services/DockerSystemService.swift` | All `docker` CLI calls + `DockerSystemError` |
| `Sources/DDEVUIApp/Services/ReclaimPlanner.swift` | Pure classification + planning. The safety rule lives here |
| `Sources/DDEVUIApp/ViewModels/DockerDiskViewModel.swift` | `DockerSystemServicing` protocol, poll state, reclaim execution |
| `Sources/DDEVUIApp/Views/DockerDiskView.swift` | The sidebar screen |
| `Tests/DDEVUIAppTests/DockerSizeTests.swift` | |
| `Tests/DDEVUIAppTests/DockerUsageTests.swift` | |
| `Tests/DDEVUIAppTests/DockerHeadroomTests.swift` | |
| `Tests/DDEVUIAppTests/DockerVolumeTests.swift` | |
| `Tests/DDEVUIAppTests/DockerSystemServiceTests.swift` | |
| `Tests/DDEVUIAppTests/ReclaimPlannerTests.swift` | **The safety-critical suite** |
| `Tests/DDEVUIAppTests/DockerDiskViewModelTests.swift` | |

**Already captured (do not regenerate — these are real output from the 2026-07-20 incident):**
- `Tests/DDEVUIAppTests/Fixtures/docker-system-df.json`
- `Tests/DDEVUIAppTests/Fixtures/docker-system-df-v.json`
- `Tests/DDEVUIAppTests/Fixtures/docker-df-pk.txt`

**Modify:**
| File | Change |
| --- | --- |
| `Package.swift` | Add the three fixtures to `resources:` |
| `Sources/DDEVUIApp/Models/AppPreferences.swift` | Two threshold properties + store methods |
| `Sources/DDEVUIApp/ViewModels/PreferencesModel.swift` | Forward the two thresholds |
| `Sources/DDEVUIApp/ViewModels/ProjectDashboardViewModel.swift` | Add `.dockerDisk` to `ProjectSidebarItem` |
| `Sources/DDEVUIApp/Views/ContentView.swift` | Route `.library(.dockerDisk)`; remove two Maintenance buttons + one dialog |
| `Sources/DDEVUIApp/Views/MenuBarContentView.swift` | Headroom row |
| `Sources/DDEVUIApp/DDEVUIApp.swift` | Menu-bar icon + tint driven by headroom |

**No existing service code changes.** `ddev mutagen reset`, `deleteImages()`, and `downloadImages()` already exist on `DDEVServicing`.

---

### Task 1: Docker size parsing and formatting

Foundational — every later task consumes this. Docker emits sizes as human strings with SI (1000-based) units.

**Files:**
- Create: `Sources/DDEVUIApp/Utilities/DockerSize.swift`
- Test: `Tests/DDEVUIAppTests/DockerSizeTests.swift`

**Interfaces:**
- Consumes: nothing.
- Produces: `DockerSize.parse(_ text: String) -> Int64?` and `Int64.formattedBytes -> String`.

- [ ] **Step 1: Write the failing tests**

Create `Tests/DDEVUIAppTests/DockerSizeTests.swift`:

```swift
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
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift test --filter DockerSizeTests`
Expected: FAIL — `cannot find 'DockerSize' in scope`.

- [ ] **Step 3: Write the implementation**

Create `Sources/DDEVUIApp/Utilities/DockerSize.swift`:

```swift
import Foundation

/// Parsing and formatting for the human-readable sizes Docker reports (`"42.37GB"`,
/// `"28.67kB"`, `"2.4GB (15%)"`). Docker uses SI multipliers — 1000-based, not 1024 — so
/// display formatting uses `ByteCountFormatter.CountStyle.file` to stay consistent with
/// what `docker system df` prints.
public enum DockerSize {
    private static let multipliers: [(suffix: String, factor: Double)] = [
        // Longest suffixes first so "kB" is never matched as "B".
        ("TB", 1_000_000_000_000),
        ("GB", 1_000_000_000),
        ("MB", 1_000_000),
        ("KB", 1_000),
        ("B", 1)
    ]

    /// Converts a Docker size string to bytes, or `nil` when it isn't a size at all
    /// (Docker prints `"N/A"` for several columns).
    public static func parse(_ text: String) -> Int64? {
        // Drop any trailing percentage, e.g. "2.4GB (15%)" -> "2.4GB".
        var cleaned = text
        if let parenthesis = cleaned.firstIndex(of: "(") {
            cleaned = String(cleaned[cleaned.startIndex..<parenthesis])
        }
        cleaned = cleaned.trimmingCharacters(in: .whitespaces).uppercased()
        guard !cleaned.isEmpty else { return nil }

        for (suffix, factor) in multipliers where cleaned.hasSuffix(suffix) {
            let numberPart = String(cleaned.dropLast(suffix.count)).trimmingCharacters(in: .whitespaces)
            guard !numberPart.isEmpty, let value = Double(numberPart) else { return nil }
            return Int64((value * factor).rounded())
        }
        return nil
    }
}

public extension Int64 {
    /// Display form for a byte count, SI-based to match Docker's own numbers.
    var formattedBytes: String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.allowedUnits = [.useKB, .useMB, .useGB, .useTB]
        return formatter.string(fromByteCount: self)
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `swift test --filter DockerSizeTests`
Expected: PASS, 5 tests.

If `testFormatsBytesForDisplay` fails on the `"Zero KB"` string, print the actual value and update the assertion to match this macOS version's `ByteCountFormatter` output — the exact zero-string is platform-defined, the other two assertions are the meaningful ones.

- [ ] **Step 5: Commit**

```bash
git add Sources/DDEVUIApp/Utilities/DockerSize.swift Tests/DDEVUIAppTests/DockerSizeTests.swift
git commit -m "feat: Add Docker size parsing and formatting"
```

---

### Task 2: Register test fixtures

The three fixtures already exist on disk but SwiftPM will not copy them into the test bundle until they are declared.

**Files:**
- Modify: `Package.swift:20`

**Interfaces:**
- Consumes: nothing.
- Produces: `Bundle.module` access to `docker-system-df.json`, `docker-system-df-v.json`, `docker-df-pk.txt` in all later test tasks.

- [ ] **Step 1: Confirm the fixtures exist**

Run: `ls -1 Tests/DDEVUIAppTests/Fixtures/`
Expected output includes:
```
ddev-start-output.txt
docker-df-pk.txt
docker-system-df-v.json
docker-system-df.json
```

If any are missing, stop — do not fabricate them. They are real captured CLI output; regenerate with the commands recorded in the spec.

- [ ] **Step 2: Declare them as resources**

In `Package.swift`, replace:

```swift
            resources: [.copy("Fixtures/ddev-start-output.txt")]
```

with:

```swift
            resources: [
                .copy("Fixtures/ddev-start-output.txt"),
                .copy("Fixtures/docker-system-df.json"),
                .copy("Fixtures/docker-system-df-v.json"),
                .copy("Fixtures/docker-df-pk.txt")
            ]
```

- [ ] **Step 3: Verify the package still resolves and builds**

Run: `swift build 2>&1 | tail -5`
Expected: `Build complete!` with no manifest errors.

- [ ] **Step 4: Commit**

```bash
git add Package.swift Tests/DDEVUIAppTests/Fixtures/
git commit -m "test: Add Docker CLI output fixtures"
```

---

### Task 3: DockerUsage model and JSON-lines decoding

`docker system df --format json` emits **one JSON object per line** — it is not a JSON array. Decoding must split on newlines.

**Files:**
- Create: `Sources/DDEVUIApp/Models/DockerUsage.swift`
- Test: `Tests/DDEVUIAppTests/DockerUsageTests.swift`

**Interfaces:**
- Consumes: `DockerSize.parse` (Task 1).
- Produces:
  - `DockerUsageCategory` with `totalCount: Int`, `active: Int`, `sizeBytes: Int64`, `reclaimableBytes: Int64`
  - `DockerUsage` with `images`, `containers`, `volumes`, `buildCache` (all `DockerUsageCategory`)
  - `DockerUsage.decode(_ text: String) throws -> DockerUsage`
  - `DockerSystemError.malformedOutput(String)`

- [ ] **Step 1: Write the failing tests**

Create `Tests/DDEVUIAppTests/DockerUsageTests.swift`:

```swift
import XCTest
@testable import DDEVUIApp

final class DockerUsageTests: XCTestCase {
    private func fixture() throws -> String {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "docker-system-df", withExtension: "json"))
        return try String(contentsOf: url, encoding: .utf8)
    }

    func testDecodesRealFixture() throws {
        let usage = try DockerUsage.decode(try fixture())

        XCTAssertEqual(usage.images.totalCount, 32)
        XCTAssertEqual(usage.images.active, 13)
        XCTAssertEqual(usage.images.sizeBytes, 15_390_000_000)
        XCTAssertEqual(usage.images.reclaimableBytes, 2_400_000_000)

        XCTAssertEqual(usage.volumes.totalCount, 96)
        XCTAssertEqual(usage.volumes.reclaimableBytes, 42_210_000_000)

        // BuildCache reports Reclaimable without a percentage suffix.
        XCTAssertEqual(usage.buildCache.reclaimableBytes, 1_216_000_000)
        XCTAssertEqual(usage.buildCache.sizeBytes, 1_807_000_000)
    }

    func testTotalReclaimableSumsCategories() throws {
        let usage = try DockerUsage.decode(try fixture())
        XCTAssertEqual(
            usage.totalReclaimableBytes,
            usage.images.reclaimableBytes
                + usage.containers.reclaimableBytes
                + usage.volumes.reclaimableBytes
                + usage.buildCache.reclaimableBytes
        )
    }

    func testIgnoresBlankLines() throws {
        let text = try fixture() + "\n\n   \n"
        XCTAssertNoThrow(try DockerUsage.decode(text))
    }

    func testThrowsWhenACategoryIsMissing() {
        let onlyImages = #"{"Active":"1","Reclaimable":"0B (0%)","Size":"1GB","TotalCount":"1","Type":"Images"}"#
        XCTAssertThrowsError(try DockerUsage.decode(onlyImages)) { error in
            guard case DockerSystemError.malformedOutput = error else {
                return XCTFail("expected malformedOutput, got \(error)")
            }
        }
    }

    func testThrowsOnGarbageInput() {
        XCTAssertThrowsError(try DockerUsage.decode("not json at all"))
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift test --filter DockerUsageTests`
Expected: FAIL — `cannot find 'DockerUsage' in scope`.

- [ ] **Step 3: Write the implementation**

Create `Sources/DDEVUIApp/Models/DockerUsage.swift`:

```swift
import Foundation

/// Errors raised when Docker's CLI output cannot be understood. Surfacing schema drift as a
/// typed error is deliberate: silently wrong disk numbers would be worse than a visible failure.
public enum DockerSystemError: Error, Equatable {
    case malformedOutput(String)
}

/// One row of `docker system df` — Images, Containers, Local Volumes, or Build Cache.
public struct DockerUsageCategory: Equatable, Sendable {
    public let totalCount: Int
    public let active: Int
    public let sizeBytes: Int64
    public let reclaimableBytes: Int64

    public init(totalCount: Int, active: Int, sizeBytes: Int64, reclaimableBytes: Int64) {
        self.totalCount = totalCount
        self.active = active
        self.sizeBytes = sizeBytes
        self.reclaimableBytes = reclaimableBytes
    }
}

public struct DockerUsage: Equatable, Sendable {
    public let images: DockerUsageCategory
    public let containers: DockerUsageCategory
    public let volumes: DockerUsageCategory
    public let buildCache: DockerUsageCategory

    public init(
        images: DockerUsageCategory,
        containers: DockerUsageCategory,
        volumes: DockerUsageCategory,
        buildCache: DockerUsageCategory
    ) {
        self.images = images
        self.containers = containers
        self.volumes = volumes
        self.buildCache = buildCache
    }

    public var totalSizeBytes: Int64 {
        images.sizeBytes + containers.sizeBytes + volumes.sizeBytes + buildCache.sizeBytes
    }

    public var totalReclaimableBytes: Int64 {
        images.reclaimableBytes + containers.reclaimableBytes
            + volumes.reclaimableBytes + buildCache.reclaimableBytes
    }

    /// One JSON object per line, keyed by a `Type` field. Note this differs from the `-v`
    /// form, which returns a single object containing arrays.
    private struct Row: Decodable {
        let Active: String
        let Reclaimable: String
        let Size: String
        let TotalCount: String
        let Type: String
    }

    public static func decode(_ text: String) throws -> DockerUsage {
        var byType: [String: DockerUsageCategory] = [:]
        let decoder = JSONDecoder()

        for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }

            guard let row = try? decoder.decode(Row.self, from: Data(trimmed.utf8)) else {
                throw DockerSystemError.malformedOutput("unreadable `docker system df` row: \(trimmed)")
            }
            byType[row.Type] = DockerUsageCategory(
                totalCount: Int(row.TotalCount) ?? 0,
                active: Int(row.Active) ?? 0,
                sizeBytes: DockerSize.parse(row.Size) ?? 0,
                reclaimableBytes: DockerSize.parse(row.Reclaimable) ?? 0
            )
        }

        func require(_ type: String) throws -> DockerUsageCategory {
            guard let category = byType[type] else {
                throw DockerSystemError.malformedOutput("`docker system df` did not report \(type)")
            }
            return category
        }

        return DockerUsage(
            images: try require("Images"),
            containers: try require("Containers"),
            volumes: try require("Local Volumes"),
            buildCache: try require("Build Cache")
        )
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `swift test --filter DockerUsageTests`
Expected: PASS, 5 tests.

- [ ] **Step 5: Commit**

```bash
git add Sources/DDEVUIApp/Models/DockerUsage.swift Tests/DDEVUIAppTests/DockerUsageTests.swift
git commit -m "feat: Decode docker system df usage output"
```

---

### Task 4: DockerHeadroom model and `df -Pk` parsing

The number that actually governs failure. The two probe paths produce different filesystem names and mount points, so the parser must key on **column position**, never on names.

**Files:**
- Create: `Sources/DDEVUIApp/Models/DockerHeadroom.swift`
- Test: `Tests/DDEVUIAppTests/DockerHeadroomTests.swift`

**Interfaces:**
- Consumes: `DockerSystemError` (Task 3).
- Produces: `DockerHeadroom` with `totalBytes`, `usedBytes`, `availableBytes`, `usedFraction: Double`, `percentUsed: Int`; and `DockerHeadroom.parse(_ text: String) throws -> DockerHeadroom`.

- [ ] **Step 1: Write the failing tests**

Create `Tests/DDEVUIAppTests/DockerHeadroomTests.swift`:

```swift
import XCTest
@testable import DDEVUIApp

final class DockerHeadroomTests: XCTestCase {
    func testParsesRealFixture() throws {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "docker-df-pk", withExtension: "txt"))
        let headroom = try DockerHeadroom.parse(try String(contentsOf: url, encoding: .utf8))

        // 1024-blocks converted to bytes.
        XCTAssertEqual(headroom.totalBytes, 98_759_140 * 1024)
        XCTAssertEqual(headroom.usedBytes, 66_597_752 * 1024)
        XCTAssertEqual(headroom.availableBytes, 27_111_892 * 1024)
        XCTAssertEqual(headroom.percentUsed, 71)
    }

    func testParsesExecProbeShapeWithDifferentFilesystemAndMountPoint() throws {
        // The `docker exec` path reports `overlay` on `/`; the fallback reports `/dev/vda1`
        // on `/probe`. Parsing must depend on column position only.
        let text = """
        Filesystem           1024-blocks    Used Available Capacity Mounted on
        overlay               98759140  66888912  26820732  71% /
        """
        let headroom = try DockerHeadroom.parse(text)
        XCTAssertEqual(headroom.usedBytes, 66_888_912 * 1024)
        XCTAssertEqual(headroom.percentUsed, 71)
    }

    func testUsedFractionIsRelativeToUsedPlusAvailable() throws {
        // df's Capacity column excludes reserved blocks, so total != used + available.
        let text = """
        Filesystem 1024-blocks Used Available Capacity Mounted on
        overlay 1000 750 250 75% /
        """
        let headroom = try DockerHeadroom.parse(text)
        XCTAssertEqual(headroom.usedFraction, 0.75, accuracy: 0.0001)
        XCTAssertEqual(headroom.percentUsed, 75)
    }

    func testThrowsWhenNoDataRow() {
        let headerOnly = "Filesystem 1024-blocks Used Available Capacity Mounted on"
        XCTAssertThrowsError(try DockerHeadroom.parse(headerOnly)) { error in
            guard case DockerSystemError.malformedOutput = error else {
                return XCTFail("expected malformedOutput, got \(error)")
            }
        }
    }

    func testThrowsOnNonNumericColumns() {
        let text = """
        Filesystem 1024-blocks Used Available Capacity Mounted on
        overlay lots some none 71% /
        """
        XCTAssertThrowsError(try DockerHeadroom.parse(text))
    }

    func testThrowsOnEmptyInput() {
        XCTAssertThrowsError(try DockerHeadroom.parse(""))
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift test --filter DockerHeadroomTests`
Expected: FAIL — `cannot find 'DockerHeadroom' in scope`.

- [ ] **Step 3: Write the implementation**

Create `Sources/DDEVUIApp/Models/DockerHeadroom.swift`:

```swift
import Foundation

/// Free space on the Docker VM's filesystem — the figure that actually governs whether a
/// `ddev start` succeeds. Derived from `df -Pk` run inside a container, because the size of
/// `Docker.raw` on the host says nothing about how full the VM believes it is.
public struct DockerHeadroom: Equatable, Sendable {
    public let totalBytes: Int64
    public let usedBytes: Int64
    public let availableBytes: Int64

    public init(totalBytes: Int64, usedBytes: Int64, availableBytes: Int64) {
        self.totalBytes = totalBytes
        self.usedBytes = usedBytes
        self.availableBytes = availableBytes
    }

    /// Used as a proportion of usable space. Mirrors df's own Capacity column, which excludes
    /// reserved blocks — so this is deliberately not `usedBytes / totalBytes`.
    public var usedFraction: Double {
        let usable = usedBytes + availableBytes
        guard usable > 0 else { return 0 }
        return Double(usedBytes) / Double(usable)
    }

    public var percentUsed: Int {
        Int((usedFraction * 100).rounded())
    }

    /// Parses POSIX `df -Pk` output. Only column *position* is trusted: the two probe paths
    /// report different filesystem names (`overlay` vs `/dev/vda1`) and mount points
    /// (`/` vs `/probe`), so neither may be matched on.
    public static func parse(_ text: String) throws -> DockerHeadroom {
        let rows = text
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.hasPrefix("Filesystem") }

        guard let row = rows.last else {
            throw DockerSystemError.malformedOutput("`df` returned no data rows")
        }

        let fields = row.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        guard fields.count >= 6,
              let blocks = Int64(fields[1]),
              let used = Int64(fields[2]),
              let available = Int64(fields[3])
        else {
            throw DockerSystemError.malformedOutput("unreadable `df` row: \(row)")
        }

        return DockerHeadroom(
            totalBytes: blocks * 1024,
            usedBytes: used * 1024,
            availableBytes: available * 1024
        )
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `swift test --filter DockerHeadroomTests`
Expected: PASS, 6 tests.

- [ ] **Step 5: Commit**

```bash
git add Sources/DDEVUIApp/Models/DockerHeadroom.swift Tests/DDEVUIAppTests/DockerHeadroomTests.swift
git commit -m "feat: Parse Docker VM disk headroom from df output"
```

---

### Task 5: DockerVolume model and `-v --format json` decoding

Unlike the non-`-v` form, this returns a **single JSON object** containing arrays. Each volume carries `Links`, the count of containers using it — the in-use signal.

**Files:**
- Create: `Sources/DDEVUIApp/Models/DockerVolume.swift`
- Test: `Tests/DDEVUIAppTests/DockerVolumeTests.swift`

**Interfaces:**
- Consumes: `DockerSize.parse` (Task 1), `DockerSystemError` (Task 3).
- Produces: `DockerVolume` with `name: String`, `sizeBytes: Int64`, `links: Int`, `isInUse: Bool`; and `DockerVolume.decodeList(_ text: String) throws -> [DockerVolume]`.

- [ ] **Step 1: Write the failing tests**

Create `Tests/DDEVUIAppTests/DockerVolumeTests.swift`:

```swift
import XCTest
@testable import DDEVUIApp

final class DockerVolumeTests: XCTestCase {
    private func fixture() throws -> String {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "docker-system-df-v", withExtension: "json"))
        return try String(contentsOf: url, encoding: .utf8)
    }

    func testDecodesRealFixture() throws {
        let volumes = try DockerVolume.decodeList(try fixture())
        XCTAssertEqual(volumes.count, 7)

        let mutagen = try XCTUnwrap(volumes.first { $0.name == "aqua-pura_project_mutagen" })
        XCTAssertEqual(mutagen.sizeBytes, 546_000_000)
        XCTAssertEqual(mutagen.links, 0)
        XCTAssertFalse(mutagen.isInUse)
    }

    func testLinksDrivesInUse() throws {
        let text = #"{"Volumes":[{"Name":"busy","Size":"1GB","Links":"2"},{"Name":"idle","Size":"1GB","Links":"0"}]}"#
        let volumes = try DockerVolume.decodeList(text)
        XCTAssertTrue(try XCTUnwrap(volumes.first { $0.name == "busy" }).isInUse)
        XCTAssertFalse(try XCTUnwrap(volumes.first { $0.name == "idle" }).isInUse)
    }

    func testTreatsUnparseableSizeAsZeroRatherThanFailing() throws {
        // Docker prints "N/A" in several columns; one odd size must not lose the whole list.
        let text = #"{"Volumes":[{"Name":"odd","Size":"N/A","Links":"0"}]}"#
        let volumes = try DockerVolume.decodeList(text)
        XCTAssertEqual(volumes.first?.sizeBytes, 0)
    }

    func testReturnsEmptyWhenNoVolumes() throws {
        XCTAssertEqual(try DockerVolume.decodeList(#"{"Volumes":[]}"#).count, 0)
    }

    func testThrowsOnGarbageInput() {
        XCTAssertThrowsError(try DockerVolume.decodeList("not json")) { error in
            guard case DockerSystemError.malformedOutput = error else {
                return XCTFail("expected malformedOutput, got \(error)")
            }
        }
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift test --filter DockerVolumeTests`
Expected: FAIL — `cannot find 'DockerVolume' in scope`.

- [ ] **Step 3: Write the implementation**

Create `Sources/DDEVUIApp/Models/DockerVolume.swift`:

```swift
import Foundation

/// A local Docker volume as reported by `docker system df -v --format json`.
public struct DockerVolume: Equatable, Sendable {
    public let name: String
    public let sizeBytes: Int64
    /// Number of containers currently using this volume. Docker reports it directly, so no
    /// cross-reference against `docker ps` is needed.
    public let links: Int

    public init(name: String, sizeBytes: Int64, links: Int) {
        self.name = name
        self.sizeBytes = sizeBytes
        self.links = links
    }

    public var isInUse: Bool { links > 0 }

    /// The `-v` form returns a single object containing arrays — unlike the plain
    /// `docker system df --format json`, which is JSON-lines.
    private struct Payload: Decodable {
        struct Volume: Decodable {
            let Name: String
            let Size: String
            let Links: String
        }
        let Volumes: [Volume]
    }

    public static func decodeList(_ text: String) throws -> [DockerVolume] {
        guard let payload = try? JSONDecoder().decode(Payload.self, from: Data(text.utf8)) else {
            throw DockerSystemError.malformedOutput("unreadable `docker system df -v` payload")
        }
        return payload.Volumes.map { volume in
            DockerVolume(
                name: volume.Name,
                sizeBytes: DockerSize.parse(volume.Size) ?? 0,
                links: Int(volume.Links) ?? 0
            )
        }
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `swift test --filter DockerVolumeTests`
Expected: PASS, 5 tests.

- [ ] **Step 5: Commit**

```bash
git add Sources/DDEVUIApp/Models/DockerVolume.swift Tests/DDEVUIAppTests/DockerVolumeTests.swift
git commit -m "feat: Decode Docker volume inventory"
```

---

### Task 6: ReclaimPlan model types

Pure value types describing what may be reclaimed. Separated from the planner so the planner file stays focused on the rule.

**Files:**
- Create: `Sources/DDEVUIApp/Models/ReclaimPlan.swift`
- Test: covered by Task 7's suite (these are data declarations with one computed property; a dedicated suite would test the compiler).

**Interfaces:**
- Consumes: `DockerVolume` (Task 5).
- Produces: `VolumeKind`, `ProjectState`, `ClassifiedVolume`, `ReclaimAction`, `ReclaimItem`, `ReclaimPlan`.

- [ ] **Step 1: Write the implementation**

Create `Sources/DDEVUIApp/Models/ReclaimPlan.swift`:

```swift
import Foundation

/// What a volume holds. Only `.mutagen` is disposable without consequence — it is a file-sync
/// cache that DDEV rebuilds on the next start.
public enum VolumeKind: Equatable, Sendable {
    case mutagen
    case database
    case other
}

/// The state of the DDEV project a volume belongs to.
public enum ProjectState: Equatable, Sendable {
    case running
    case stopped
    /// No DDEV project of this name is registered — a leftover from a deleted project.
    case orphaned
}

public struct ClassifiedVolume: Equatable, Sendable, Identifiable {
    public let volume: DockerVolume
    public let kind: VolumeKind
    /// `nil` when the volume name doesn't follow a DDEV naming convention at all.
    public let projectName: String?
    public let state: ProjectState

    public var id: String { volume.name }

    public init(volume: DockerVolume, kind: VolumeKind, projectName: String?, state: ProjectState) {
        self.volume = volume
        self.kind = kind
        self.projectName = projectName
        self.state = state
    }
}

/// A single reclaim operation. Which service executes it is decided by the view model:
/// `mutagenReset` goes through `DDEVServicing`, the rest through `DockerSystemServicing`.
///
/// There is deliberately no `staleDDEVImages` case. `docker image prune -af` already removes
/// every image not used by a container, which includes stale `ddev/ddev-*` images from earlier
/// DDEV versions — so `unusedImages` subsumes what the old "Delete DDEV Images" button did,
/// and running `ddev delete images` as well would be redundant.
public enum ReclaimAction: Equatable, Sendable {
    case buildCache
    case unusedImages
    /// `ddev mutagen reset` is keyed by working directory, not project name.
    case mutagenReset(project: String, appRoot: String)
    case removeVolume(name: String)
}

public struct ReclaimItem: Equatable, Sendable, Identifiable {
    public let action: ReclaimAction
    public let label: String
    public let detail: String
    public let estimatedBytes: Int64

    public var id: String { label }

    public init(action: ReclaimAction, label: String, detail: String, estimatedBytes: Int64) {
        self.action = action
        self.label = label
        self.detail = detail
        self.estimatedBytes = estimatedBytes
    }
}

public struct ReclaimPlan: Equatable, Sendable {
    public let items: [ReclaimItem]

    public init(items: [ReclaimItem]) {
        self.items = items
    }

    public var totalBytes: Int64 {
        items.reduce(0) { $0 + $1.estimatedBytes }
    }

    public var isEmpty: Bool { items.isEmpty }
}
```

- [ ] **Step 2: Verify it compiles**

Run: `swift build 2>&1 | tail -5`
Expected: `Build complete!`

- [ ] **Step 3: Commit**

```bash
git add Sources/DDEVUIApp/Models/ReclaimPlan.swift
git commit -m "feat: Add reclaim plan model types"
```

---

### Task 7: ReclaimPlanner — the safety rule

**This is the safety-critical task.** Everything that protects a database lives here, and it is pure so it can be tested exhaustively without Docker.

Classification is by **exact suffix strip then exact-set membership**. Prefix matching would misclassify real projects: `thethreeswords` and `thethreeswordsguiseley` both exist in the fixture.

**Files:**
- Create: `Sources/DDEVUIApp/Services/ReclaimPlanner.swift`
- Test: `Tests/DDEVUIAppTests/ReclaimPlannerTests.swift`

**Interfaces:**
- Consumes: `DockerVolume` (Task 5), `ReclaimPlan` types (Task 6), `DockerUsage` (Task 3), `DDEVProject`.
- Produces:
  - `ReclaimPlanner.classify(volumes:projects:) -> [ClassifiedVolume]`
  - `ReclaimPlanner.plan(volumes:projects:usage:) -> ReclaimPlan`

- [ ] **Step 1: Write the failing tests**

Create `Tests/DDEVUIAppTests/ReclaimPlannerTests.swift`:

```swift
import XCTest
@testable import DDEVUIApp

final class ReclaimPlannerTests: XCTestCase {

    // MARK: - Helpers

    private func project(_ name: String, status: DDEVProjectStatus) -> DDEVProject {
        DDEVProject(
            name: name,
            appRoot: "/Users/dave/Development/\(name)",
            shortRoot: "~/Development/\(name)",
            status: status,
            statusDescription: "",
            projectType: .wordpress,
            docroot: "",
            primaryURL: nil,
            httpURL: nil,
            httpsURL: nil,
            mailpitURL: nil,
            mailpitHTTPSURL: nil,
            xhguiURL: nil,
            xhguiHTTPSURL: nil,
            mutagenEnabled: true,
            mutagenStatus: nil
        )
    }

    private func volume(_ name: String, gigabytes: Double = 1, links: Int = 0) -> DockerVolume {
        DockerVolume(name: name, sizeBytes: Int64(gigabytes * 1_000_000_000), links: links)
    }

    private func emptyUsage() -> DockerUsage {
        let zero = DockerUsageCategory(totalCount: 0, active: 0, sizeBytes: 0, reclaimableBytes: 0)
        return DockerUsage(images: zero, containers: zero, volumes: zero, buildCache: zero)
    }

    // MARK: - Classification

    func testClassifiesMutagenAndDatabaseVolumes() {
        let classified = ReclaimPlanner.classify(
            volumes: [volume("aqua-pura_project_mutagen"), volume("aqua-pura-mariadb")],
            projects: [project("aqua-pura", status: .stopped)]
        )

        let mutagen = classified.first { $0.volume.name.hasSuffix("_project_mutagen") }
        XCTAssertEqual(mutagen?.kind, .mutagen)
        XCTAssertEqual(mutagen?.projectName, "aqua-pura")
        XCTAssertEqual(mutagen?.state, .stopped)

        let database = classified.first { $0.volume.name.hasSuffix("-mariadb") }
        XCTAssertEqual(database?.kind, .database)
        XCTAssertEqual(database?.state, .stopped)
    }

    func testUnrecognisedVolumeNameIsOther() {
        let classified = ReclaimPlanner.classify(
            volumes: [volume("some-random-volume")],
            projects: []
        )
        XCTAssertEqual(classified.first?.kind, .other)
        XCTAssertNil(classified.first?.projectName)
    }

    func testVolumeForUnregisteredProjectIsOrphaned() {
        let classified = ReclaimPlanner.classify(
            volumes: [volume("westlife_project_mutagen")],
            projects: [project("aqua-pura", status: .running)]
        )
        XCTAssertEqual(classified.first?.state, .orphaned)
        XCTAssertEqual(classified.first?.projectName, "westlife")
    }

    func testInUseVolumeIsRunningEvenIfProjectReportsStopped() {
        // Docker's own Links count is the authority on whether something is mounted.
        let classified = ReclaimPlanner.classify(
            volumes: [volume("aqua-pura_project_mutagen", links: 1)],
            projects: [project("aqua-pura", status: .stopped)]
        )
        XCTAssertEqual(classified.first?.state, .running)
    }

    func testPrefixCollisionIsNotMisclassified() {
        // `thethreeswords` is a strict prefix of `thethreeswordsguiseley`. Naive prefix
        // matching would attribute the longer project's volume to the shorter project.
        let classified = ReclaimPlanner.classify(
            volumes: [
                volume("thethreeswords_project_mutagen"),
                volume("thethreeswordsguiseley_project_mutagen")
            ],
            projects: [
                project("thethreeswords", status: .stopped),
                project("thethreeswordsguiseley", status: .running)
            ]
        )

        let short = classified.first { $0.volume.name == "thethreeswords_project_mutagen" }
        let long = classified.first { $0.volume.name == "thethreeswordsguiseley_project_mutagen" }
        XCTAssertEqual(short?.projectName, "thethreeswords")
        XCTAssertEqual(short?.state, .stopped)
        XCTAssertEqual(long?.projectName, "thethreeswordsguiseley")
        XCTAssertEqual(long?.state, .running)
    }

    // MARK: - The safety rule

    func testRunningProjectMutagenVolumeIsExcluded() {
        let plan = ReclaimPlanner.plan(
            volumes: [volume("aqua-pura_project_mutagen", links: 1)],
            projects: [project("aqua-pura", status: .running)],
            usage: emptyUsage()
        )
        XCTAssertFalse(plan.items.contains { $0.action == .mutagenReset(project: "aqua-pura", appRoot: "/Users/dave/Development/aqua-pura") })
    }

    func testStoppedProjectMutagenVolumeIsIncludedAsMutagenReset() {
        let plan = ReclaimPlanner.plan(
            volumes: [volume("aqua-pura_project_mutagen", gigabytes: 0.546)],
            projects: [project("aqua-pura", status: .stopped)],
            usage: emptyUsage()
        )
        XCTAssertTrue(plan.items.contains {
            $0.action == .mutagenReset(project: "aqua-pura", appRoot: "/Users/dave/Development/aqua-pura")
        })
    }

    func testRegisteredProjectDatabaseIsNeverInABulkPlan() {
        // The single most important assertion in the suite.
        let plan = ReclaimPlanner.plan(
            volumes: [
                volume("aqua-pura-mariadb", gigabytes: 5),
                volume("thethreeswords-mariadb", gigabytes: 5)
            ],
            projects: [
                project("aqua-pura", status: .running),
                project("thethreeswords", status: .stopped)
            ],
            usage: emptyUsage()
        )
        XCTAssertTrue(plan.isEmpty, "a registered project's database must never be bulk-eligible")
    }

    func testOrphanedProjectDatabaseIsOffered() {
        let plan = ReclaimPlanner.plan(
            volumes: [volume("westlife-mariadb", gigabytes: 0.141)],
            projects: [project("aqua-pura", status: .running)],
            usage: emptyUsage()
        )
        XCTAssertTrue(plan.items.contains { $0.action == .removeVolume(name: "westlife-mariadb") })
    }

    func testOrphanMutagenUsesRemoveVolumeNotMutagenReset() {
        // There is no DDEV project left to run `ddev mutagen reset` against.
        let plan = ReclaimPlanner.plan(
            volumes: [volume("westlife_project_mutagen")],
            projects: [],
            usage: emptyUsage()
        )
        XCTAssertTrue(plan.items.contains { $0.action == .removeVolume(name: "westlife_project_mutagen") })
        XCTAssertFalse(plan.items.contains {
            if case .mutagenReset = $0.action { return true }
            return false
        })
    }

    func testUnrecognisedVolumesAreNeverBulkEligible() {
        let plan = ReclaimPlanner.plan(
            volumes: [volume("some-random-volume", gigabytes: 10)],
            projects: [],
            usage: emptyUsage()
        )
        XCTAssertTrue(plan.isEmpty)
    }

    func testInUseOrphanVolumeIsExcluded() {
        // Orphaned but currently mounted — removal would fail, so don't offer it.
        let plan = ReclaimPlanner.plan(
            volumes: [volume("westlife_project_mutagen", links: 1)],
            projects: [],
            usage: emptyUsage()
        )
        XCTAssertTrue(plan.isEmpty)
    }

    // MARK: - Usage-derived items

    func testIncludesBuildCacheAndUnusedImagesWhenReclaimable() {
        let usage = DockerUsage(
            images: DockerUsageCategory(totalCount: 30, active: 10, sizeBytes: 15_000_000_000, reclaimableBytes: 2_400_000_000),
            containers: DockerUsageCategory(totalCount: 0, active: 0, sizeBytes: 0, reclaimableBytes: 0),
            volumes: DockerUsageCategory(totalCount: 0, active: 0, sizeBytes: 0, reclaimableBytes: 0),
            buildCache: DockerUsageCategory(totalCount: 49, active: 0, sizeBytes: 1_807_000_000, reclaimableBytes: 1_216_000_000)
        )
        let plan = ReclaimPlanner.plan(volumes: [], projects: [], usage: usage)

        XCTAssertTrue(plan.items.contains { $0.action == .buildCache })
        XCTAssertTrue(plan.items.contains { $0.action == .unusedImages })
        XCTAssertEqual(plan.totalBytes, 2_400_000_000 + 1_216_000_000)
    }

    func testOmitsZeroSizedCategories() {
        let plan = ReclaimPlanner.plan(volumes: [], projects: [], usage: emptyUsage())
        XCTAssertTrue(plan.isEmpty)
    }

    func testTotalBytesSumsAllItems() {
        let plan = ReclaimPlanner.plan(
            volumes: [
                volume("aqua-pura_project_mutagen", gigabytes: 2),
                volume("westlife-mariadb", gigabytes: 1)
            ],
            projects: [project("aqua-pura", status: .stopped)],
            usage: emptyUsage()
        )
        XCTAssertEqual(plan.totalBytes, 3_000_000_000)
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift test --filter ReclaimPlannerTests`
Expected: FAIL — `cannot find 'ReclaimPlanner' in scope`.

If `DDEVProjectStatus.stopped` does not exist, check the real case names with
`grep -n "case " Sources/DDEVUIApp/Models/DDEVProject.swift | head -30` and adjust the
helper — do not change the assertions.

- [ ] **Step 3: Write the implementation**

Create `Sources/DDEVUIApp/Services/ReclaimPlanner.swift`:

```swift
import Foundation

/// Decides what is safe to reclaim. Deliberately pure and I/O-free so the entire safety
/// policy is unit-testable without Docker running.
///
/// **The safety rule** — a volume is bulk-eligible if and only if it is `.mutagen` and not
/// `.running`, or it belongs to an `.orphaned` project. A `.database` volume for a registered
/// project is never in a bulk plan. This rule exists in this file and nowhere else.
public enum ReclaimPlanner {
    private static let mutagenSuffix = "_project_mutagen"
    private static let databaseSuffix = "-mariadb"

    /// Attributes each volume to a project and works out what it holds.
    ///
    /// Matching strips the exact suffix and then requires exact membership of the project set.
    /// Prefix matching would be wrong: `thethreeswords` is a strict prefix of
    /// `thethreeswordsguiseley`, and both are real projects.
    public static func classify(volumes: [DockerVolume], projects: [DDEVProject]) -> [ClassifiedVolume] {
        let projectsByName = Dictionary(uniqueKeysWithValues: projects.map { ($0.name, $0) })

        return volumes.map { volume in
            let (kind, projectName): (VolumeKind, String?) = {
                if volume.name.hasSuffix(mutagenSuffix) {
                    return (.mutagen, String(volume.name.dropLast(mutagenSuffix.count)))
                }
                if volume.name.hasSuffix(databaseSuffix) {
                    return (.database, String(volume.name.dropLast(databaseSuffix.count)))
                }
                return (.other, nil)
            }()

            let state: ProjectState = {
                // Docker's own link count is the authority on whether the volume is mounted,
                // regardless of what DDEV believes the project's status to be.
                if volume.isInUse { return .running }
                guard let projectName, let project = projectsByName[projectName] else {
                    return projectName == nil ? .stopped : .orphaned
                }
                return project.status == .running ? .running : .stopped
            }()

            return ClassifiedVolume(volume: volume, kind: kind, projectName: projectName, state: state)
        }
    }

    /// Builds the safe-by-default bulk plan.
    public static func plan(
        volumes: [DockerVolume],
        projects: [DDEVProject],
        usage: DockerUsage
    ) -> ReclaimPlan {
        var items: [ReclaimItem] = []
        let projectsByName = Dictionary(uniqueKeysWithValues: projects.map { ($0.name, $0) })

        if usage.buildCache.reclaimableBytes > 0 {
            items.append(ReclaimItem(
                action: .buildCache,
                label: "Build cache",
                detail: "Rebuilt automatically when needed",
                estimatedBytes: usage.buildCache.reclaimableBytes
            ))
        }

        if usage.images.reclaimableBytes > 0 {
            // Covers stale `ddev/ddev-*` images from earlier versions too — anything not
            // currently used by a container.
            items.append(ReclaimItem(
                action: .unusedImages,
                label: "Unused images",
                detail: "Re-pulled on next start",
                estimatedBytes: usage.images.reclaimableBytes
            ))
        }

        for classified in classify(volumes: volumes, projects: projects) {
            // An in-use volume can never be removed, whatever it holds.
            guard classified.state != .running else { continue }

            switch (classified.kind, classified.state) {
            case (.mutagen, .stopped):
                // A registered, stopped project — reset through DDEV so its own state stays
                // consistent. `ddev mutagen reset` is keyed by working directory.
                guard let projectName = classified.projectName,
                      let project = projectsByName[projectName] else { continue }
                items.append(ReclaimItem(
                    action: .mutagenReset(project: projectName, appRoot: project.appRoot),
                    label: "\(projectName) sync cache",
                    detail: "Rebuilt on next start",
                    estimatedBytes: classified.volume.sizeBytes
                ))

            case (.mutagen, .orphaned), (.database, .orphaned), (.other, .orphaned):
                // No DDEV project remains, so remove the volume directly.
                items.append(ReclaimItem(
                    action: .removeVolume(name: classified.volume.name),
                    label: classified.volume.name,
                    detail: "Orphaned — no such DDEV project",
                    estimatedBytes: classified.volume.sizeBytes
                ))

            default:
                // Registered projects' databases and unrecognised volumes are never
                // bulk-eligible. They are removable only by explicit per-item selection.
                continue
            }
        }

        return ReclaimPlan(items: items)
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `swift test --filter ReclaimPlannerTests`
Expected: PASS, 15 tests.

- [ ] **Step 5: Run the whole suite to check nothing regressed**

Run: `swift test 2>&1 | tail -20`
Expected: all tests pass.

- [ ] **Step 6: Commit**

```bash
git add Sources/DDEVUIApp/Services/ReclaimPlanner.swift Tests/DDEVUIAppTests/ReclaimPlannerTests.swift
git commit -m "feat: Add reclaim planner with database safety rule"
```

---

### Task 8: DockerSystemService

All `docker` CLI calls. Mirrors `DDEVCommandService`'s shape exactly: injected `CommandRunning`, injected executable path, private `runDocker` helper.

**Files:**
- Create: `Sources/DDEVUIApp/Services/DockerSystemService.swift`
- Test: `Tests/DDEVUIAppTests/DockerSystemServiceTests.swift`

**Interfaces:**
- Consumes: `CommandRunning`, `CommandSpec`, `CommandResult`, `DockerExecutableResolver`, `DockerUsage` (Task 3), `DockerHeadroom` (Task 4), `DockerVolume` (Task 5).
- Produces:
  - `DockerSystemService(commandRunner:dockerExecutable:)`
  - `usage() async throws -> DockerUsage`
  - `headroom() async throws -> DockerHeadroom`
  - `volumes() async throws -> [DockerVolume]`
  - `pruneBuildCache() async throws -> CommandResult`
  - `pruneUnusedImages() async throws -> CommandResult`
  - `removeVolumes(_ names: [String]) async -> [VolumeRemovalResult]`
  - `VolumeRemovalResult` with `name: String`, `succeeded: Bool`, `message: String?`

- [ ] **Step 1: Write the failing tests**

Create `Tests/DDEVUIAppTests/DockerSystemServiceTests.swift`:

```swift
import XCTest
@testable import DDEVUIApp

private final class RecordingCommandRunner: CommandRunning, @unchecked Sendable {
    private let lock = NSLock()
    private var results: [Result<CommandResult, Error>]
    private var recordedCommands: [CommandSpec] = []

    var commands: [CommandSpec] {
        lock.withLock { recordedCommands }
    }

    init(result: Result<CommandResult, Error>) {
        self.results = [result]
    }

    init(results: [Result<CommandResult, Error>]) {
        self.results = results
    }

    func run(_ spec: CommandSpec) async throws -> CommandResult {
        let result = lock.withLock {
            recordedCommands.append(spec)
            if results.count > 1 {
                return results.removeFirst()
            }
            return results.first ?? .success(CommandResult.success())
        }
        return try result.get()
    }
}

final class DockerSystemServiceTests: XCTestCase {

    func testUsageRunsSystemDFWithJSONFormat() async throws {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "docker-system-df", withExtension: "json"))
        let stdout = try String(contentsOf: url, encoding: .utf8)
        let runner = RecordingCommandRunner(result: .success(CommandResult.success(stdout: stdout)))
        let service = DockerSystemService(commandRunner: runner, dockerExecutable: "/usr/local/bin/docker")

        let usage = try await service.usage()

        XCTAssertEqual(runner.commands, [
            CommandSpec(
                executable: "/usr/local/bin/docker",
                arguments: ["system", "df", "--format", "json"],
                workingDirectory: nil
            )
        ])
        XCTAssertEqual(usage.images.totalCount, 32)
    }

    func testVolumesRunsSystemDFVerbose() async throws {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "docker-system-df-v", withExtension: "json"))
        let stdout = try String(contentsOf: url, encoding: .utf8)
        let runner = RecordingCommandRunner(result: .success(CommandResult.success(stdout: stdout)))
        let service = DockerSystemService(commandRunner: runner, dockerExecutable: "docker")

        let volumes = try await service.volumes()

        XCTAssertEqual(runner.commands.first?.arguments, ["system", "df", "-v", "--format", "json"])
        XCTAssertEqual(volumes.count, 7)
    }

    func testHeadroomExecsIntoFirstRunningContainer() async throws {
        let dfOutput = """
        Filesystem           1024-blocks    Used Available Capacity Mounted on
        overlay               98759140  66888912  26820732  71% /
        """
        let runner = RecordingCommandRunner(results: [
            .success(CommandResult.success(stdout: "ddev-router\nddev-aqua-pura-web\n")),
            .success(CommandResult.success(stdout: dfOutput))
        ])
        let service = DockerSystemService(commandRunner: runner, dockerExecutable: "docker")

        let headroom = try await service.headroom()

        XCTAssertEqual(runner.commands.count, 2)
        XCTAssertEqual(runner.commands[0].arguments, ["ps", "--format", "{{.Names}}"])
        XCTAssertEqual(runner.commands[1].arguments, ["exec", "ddev-router", "df", "-Pk", "/"])
        XCTAssertEqual(headroom.percentUsed, 71)
    }

    func testHeadroomFallsBackToProbeVolumeWhenNothingIsRunning() async throws {
        let dfOutput = """
        Filesystem           1024-blocks    Used Available Capacity Mounted on
        /dev/vda1             98759140  66597752  27111892  71% /probe
        """
        let runner = RecordingCommandRunner(results: [
            .success(CommandResult.success(stdout: "\n")),            // docker ps — nothing running
            .success(CommandResult.success()),                        // volume create
            .success(CommandResult.success(stdout: dfOutput)),        // run … df
            .success(CommandResult.success())                         // volume rm
        ])
        let service = DockerSystemService(commandRunner: runner, dockerExecutable: "docker")

        let headroom = try await service.headroom()

        XCTAssertEqual(runner.commands[1].arguments, ["volume", "create", "ddevui-diskprobe"])
        XCTAssertEqual(runner.commands[2].arguments, [
            "run", "--rm", "-v", "ddevui-diskprobe:/probe", "alpine", "df", "-Pk", "/probe"
        ])
        // The probe volume must always be cleaned up.
        XCTAssertEqual(runner.commands[3].arguments, ["volume", "rm", "ddevui-diskprobe"])
        XCTAssertEqual(headroom.availableBytes, 27_111_892 * 1024)
    }

    func testHeadroomRemovesProbeVolumeEvenWhenDFFails() async {
        struct Boom: Error {}
        let runner = RecordingCommandRunner(results: [
            .success(CommandResult.success(stdout: "")),
            .success(CommandResult.success()),
            .failure(Boom()),
            .success(CommandResult.success())
        ])
        let service = DockerSystemService(commandRunner: runner, dockerExecutable: "docker")

        _ = try? await service.headroom()

        XCTAssertTrue(
            runner.commands.contains { $0.arguments == ["volume", "rm", "ddevui-diskprobe"] },
            "probe volume must be cleaned up even on failure"
        )
    }

    func testPruneCommands() async throws {
        let runner = RecordingCommandRunner(result: .success(CommandResult.success()))
        let service = DockerSystemService(commandRunner: runner, dockerExecutable: "docker")

        _ = try await service.pruneBuildCache()
        _ = try await service.pruneUnusedImages()

        XCTAssertEqual(runner.commands.map(\.arguments), [
            ["builder", "prune", "-af"],
            ["image", "prune", "-af"]
        ])
    }

    func testRemoveVolumesReportsPerItemResultsAndContinuesAfterFailure() async {
        struct Boom: Error {}
        let runner = RecordingCommandRunner(results: [
            .success(CommandResult.success()),
            .failure(Boom()),
            .success(CommandResult.success())
        ])
        let service = DockerSystemService(commandRunner: runner, dockerExecutable: "docker")

        let results = await service.removeVolumes(["a", "b", "c"])

        XCTAssertEqual(results.count, 3, "a failure must not abort the batch")
        XCTAssertTrue(results[0].succeeded)
        XCTAssertFalse(results[1].succeeded)
        XCTAssertTrue(results[2].succeeded)
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift test --filter DockerSystemServiceTests`
Expected: FAIL — `cannot find 'DockerSystemService' in scope`.

- [ ] **Step 3: Write the implementation**

Create `Sources/DDEVUIApp/Services/DockerSystemService.swift`:

```swift
import Foundation

/// Result of attempting to remove one volume. Removal is reported per item so a single
/// stuck volume neither aborts the batch nor leaves it ambiguous what actually happened.
public struct VolumeRemovalResult: Equatable, Sendable {
    public let name: String
    public let succeeded: Bool
    public let message: String?

    public init(name: String, succeeded: Bool, message: String?) {
        self.name = name
        self.succeeded = succeeded
        self.message = message
    }
}

/// Reads Docker's disk usage and performs reclaim operations that DDEV cannot express.
/// Mirrors `DDEVCommandService`: inject a `CommandRunning`, resolve the executable once.
public final class DockerSystemService: Sendable {
    /// Name of the throwaway volume used to measure headroom when nothing is running.
    /// Must satisfy Docker's `[a-zA-Z0-9][a-zA-Z0-9_.-]` rule — no leading underscore.
    static let probeVolumeName = "ddevui-diskprobe"

    private let commandRunner: CommandRunning
    private let dockerExecutable: String

    public init(
        commandRunner: CommandRunning = ProcessCommandRunner(),
        dockerExecutable: String = DockerExecutableResolver().resolve()
    ) {
        self.commandRunner = commandRunner
        self.dockerExecutable = dockerExecutable
    }

    // MARK: - Reads

    /// Category totals. Emits JSON-lines, one object per category.
    public func usage() async throws -> DockerUsage {
        let result = try await runDocker(["system", "df", "--format", "json"])
        return try DockerUsage.decode(result.stdout)
    }

    /// Per-volume inventory. Walks every volume, so this takes seconds on a machine with
    /// many projects — call it on demand, never on a background refresh cycle.
    public func volumes() async throws -> [DockerVolume] {
        let result = try await runDocker(["system", "df", "-v", "--format", "json"])
        return try DockerVolume.decodeList(result.stdout)
    }

    /// Free space on the Docker VM's filesystem.
    ///
    /// Prefers `docker exec` into an already-running container — effectively free. Falls back
    /// to mounting a throwaway volume, which is slower and may pull `alpine`.
    public func headroom() async throws -> DockerHeadroom {
        if let container = try? await firstRunningContainer() {
            let result = try await runDocker(["exec", container, "df", "-Pk", "/"])
            return try DockerHeadroom.parse(result.stdout)
        }
        return try await headroomViaProbeVolume()
    }

    private func firstRunningContainer() async throws -> String {
        let result = try await runDocker(["ps", "--format", "{{.Names}}"])
        let names = result.stdout
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        guard let first = names.first else {
            throw DockerSystemError.malformedOutput("no running containers")
        }
        return first
    }

    private func headroomViaProbeVolume() async throws -> DockerHeadroom {
        _ = try await runDocker(["volume", "create", Self.probeVolumeName])
        defer {
            // Fire-and-forget cleanup: the probe volume must never be left behind, even if
            // the measurement itself failed.
            Task { [commandRunner, dockerExecutable] in
                _ = try? await commandRunner.run(CommandSpec(
                    executable: dockerExecutable,
                    arguments: ["volume", "rm", Self.probeVolumeName]
                ))
            }
        }

        let result = try await runDocker([
            "run", "--rm", "-v", "\(Self.probeVolumeName):/probe", "alpine", "df", "-Pk", "/probe"
        ])
        return try DockerHeadroom.parse(result.stdout)
    }

    // MARK: - Reclaim

    @discardableResult
    public func pruneBuildCache() async throws -> CommandResult {
        try await runDocker(["builder", "prune", "-af"])
    }

    @discardableResult
    public func pruneUnusedImages() async throws -> CommandResult {
        try await runDocker(["image", "prune", "-af"])
    }

    /// Removes volumes one at a time, reporting each outcome. Never throws — a volume that
    /// became in-use mid-run must not abort the remaining removals.
    public func removeVolumes(_ names: [String]) async -> [VolumeRemovalResult] {
        var results: [VolumeRemovalResult] = []
        for name in names {
            do {
                _ = try await runDocker(["volume", "rm", name])
                results.append(VolumeRemovalResult(name: name, succeeded: true, message: nil))
            } catch {
                results.append(VolumeRemovalResult(
                    name: name,
                    succeeded: false,
                    message: error.presentableMessage
                ))
            }
        }
        return results
    }

    // MARK: - Plumbing

    private func runDocker(_ arguments: [String]) async throws -> CommandResult {
        try await commandRunner.run(CommandSpec(executable: dockerExecutable, arguments: arguments))
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `swift test --filter DockerSystemServiceTests`
Expected: PASS, 7 tests.

Note on `testHeadroomRemovesProbeVolumeEvenWhenDFFails`: cleanup is dispatched in a detached
`Task`, so it may not have been recorded by the time the assertion runs. If the test is flaky,
make cleanup synchronous by replacing the `defer` block with an explicit
`do { … } catch { await cleanup(); throw error }` structure rather than weakening the assertion.

- [ ] **Step 5: Commit**

```bash
git add Sources/DDEVUIApp/Services/DockerSystemService.swift Tests/DDEVUIAppTests/DockerSystemServiceTests.swift
git commit -m "feat: Add Docker system service for disk reads and reclaim"
```

---

### Task 9: Threshold preferences

Two user-tunable thresholds, following the existing `AppPreferences` / `PreferencesModel` pattern.

**Files:**
- Modify: `Sources/DDEVUIApp/Models/AppPreferences.swift`
- Modify: `Sources/DDEVUIApp/ViewModels/PreferencesModel.swift`
- Test: `Tests/DDEVUIAppTests/AppPreferencesTests.swift` (extend)

**Interfaces:**
- Consumes: existing `AppPreferences`, `AppPreferencesStoring`, `UserDefaultsAppPreferencesStore`, `PreferencesModel`.
- Produces: `AppPreferences.diskWarnThreshold: Double` (default `0.85`), `AppPreferences.diskCriticalThreshold: Double` (default `0.93`), and `PreferencesModel.setDiskWarnThreshold(_:)` / `setDiskCriticalThreshold(_:)`.

- [ ] **Step 1: Read the existing files to match their exact pattern**

Run:
```bash
cat Sources/DDEVUIApp/Models/AppPreferences.swift
```

Note precisely how an existing scalar preference (e.g. `projectSort`) declares its property,
its `UserDefaults` key, its default, and its `save…` method. Mirror that structure exactly —
do not invent a different persistence style.

- [ ] **Step 2: Write the failing tests**

Append to `Tests/DDEVUIAppTests/AppPreferencesTests.swift`:

```swift
    func testDiskThresholdDefaults() {
        let defaults = UserDefaults(suiteName: "DiskThresholdDefaults-\(UUID().uuidString)")!
        let store = UserDefaultsAppPreferencesStore(defaults: defaults)
        let preferences = store.loadPreferences()

        XCTAssertEqual(preferences.diskWarnThreshold, 0.85, accuracy: 0.0001)
        XCTAssertEqual(preferences.diskCriticalThreshold, 0.93, accuracy: 0.0001)
    }

    func testDiskThresholdsRoundTrip() {
        let defaults = UserDefaults(suiteName: "DiskThresholdRoundTrip-\(UUID().uuidString)")!
        let store = UserDefaultsAppPreferencesStore(defaults: defaults)

        store.saveDiskWarnThreshold(0.7)
        store.saveDiskCriticalThreshold(0.9)

        let reloaded = store.loadPreferences()
        XCTAssertEqual(reloaded.diskWarnThreshold, 0.7, accuracy: 0.0001)
        XCTAssertEqual(reloaded.diskCriticalThreshold, 0.9, accuracy: 0.0001)
    }
```

If `UserDefaultsAppPreferencesStore` does not take a `defaults:` parameter, use whatever
injection point the existing tests in this file already use.

- [ ] **Step 3: Run to verify they fail**

Run: `swift test --filter AppPreferencesTests`
Expected: FAIL — `value of type 'AppPreferences' has no member 'diskWarnThreshold'`.

- [ ] **Step 4: Add the properties, keys, defaults, and save methods**

In `AppPreferences.swift`, following the established pattern for existing scalars:

```swift
    /// Fraction of Docker VM disk usage at which the menu bar starts warning. Default 0.85 —
    /// on a ~99 GB VM that leaves roughly 15 GB, about two project starts of headroom.
    public var diskWarnThreshold: Double

    /// Fraction at which the warning escalates to critical. Default 0.93.
    public var diskCriticalThreshold: Double
```

Add matching `UserDefaults` keys (`"diskWarnThreshold"`, `"diskCriticalThreshold"`), defaults
of `0.85` and `0.93` when unset, and `saveDiskWarnThreshold(_ value: Double)` /
`saveDiskCriticalThreshold(_ value: Double)` on `AppPreferencesStoring` and its
`UserDefaults` implementation. Update any other `AppPreferencesStoring` conformers (test
doubles) that the compiler flags.

- [ ] **Step 5: Forward them from PreferencesModel**

In `PreferencesModel.swift`, after `setProjectSort`:

```swift
    public func setDiskWarnThreshold(_ value: Double) {
        preferences.diskWarnThreshold = value
        preferencesStore.saveDiskWarnThreshold(value)
    }

    public func setDiskCriticalThreshold(_ value: Double) {
        preferences.diskCriticalThreshold = value
        preferencesStore.saveDiskCriticalThreshold(value)
    }
```

- [ ] **Step 6: Run the tests to verify they pass**

Run: `swift test --filter AppPreferencesTests`
Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add Sources/DDEVUIApp/Models/AppPreferences.swift Sources/DDEVUIApp/ViewModels/PreferencesModel.swift Tests/DDEVUIAppTests/AppPreferencesTests.swift
git commit -m "feat: Add Docker disk threshold preferences"
```

---

### Task 10: DockerDiskViewModel

Joins the service and the planner, holds poll state, and executes reclaim through `CommandScheduler`.

**Files:**
- Create: `Sources/DDEVUIApp/ViewModels/DockerDiskViewModel.swift`
- Test: `Tests/DDEVUIAppTests/DockerDiskViewModelTests.swift`

**Interfaces:**
- Consumes: `DockerSystemService` (Task 8), `ReclaimPlanner` (Task 7), `DDEVServicing`, `CommandScheduler`, `PreferencesModel` (Task 9).
- Produces:
  - `DockerSystemServicing` protocol
  - `DiskAlertLevel` enum: `.normal`, `.warning`, `.critical`
  - `DockerDiskViewModel` with `headroom`, `usage`, `plan`, `inventory`, `alertLevel`, `isReclaiming`, `errorMessage`, `lastReclaimSummary`
  - `refreshHeadroom()`, `refreshFullInventory()`, `executeReclaim()`, `removeVolume(named:)`, `prefetchImages()`

- [ ] **Step 1: Write the failing tests**

Create `Tests/DDEVUIAppTests/DockerDiskViewModelTests.swift`:

```swift
import XCTest
@testable import DDEVUIApp

private final class FakeDockerSystemService: DockerSystemServicing, @unchecked Sendable {
    var headroomResult: Result<DockerHeadroom, Error> = .success(
        DockerHeadroom(totalBytes: 100_000, usedBytes: 50_000, availableBytes: 50_000)
    )
    var usageResult: Result<DockerUsage, Error>
    var volumesResult: Result<[DockerVolume], Error> = .success([])
    private(set) var prunedBuildCache = false
    private(set) var prunedImages = false
    private(set) var removedVolumes: [String] = []

    init() {
        let zero = DockerUsageCategory(totalCount: 0, active: 0, sizeBytes: 0, reclaimableBytes: 0)
        usageResult = .success(DockerUsage(images: zero, containers: zero, volumes: zero, buildCache: zero))
    }

    func usage() async throws -> DockerUsage { try usageResult.get() }
    func headroom() async throws -> DockerHeadroom { try headroomResult.get() }
    func volumes() async throws -> [DockerVolume] { try volumesResult.get() }

    func pruneBuildCache() async throws -> CommandResult {
        prunedBuildCache = true
        return CommandResult.success()
    }

    func pruneUnusedImages() async throws -> CommandResult {
        prunedImages = true
        return CommandResult.success()
    }

    func removeVolumes(_ names: [String]) async -> [VolumeRemovalResult] {
        removedVolumes.append(contentsOf: names)
        return names.map { VolumeRemovalResult(name: $0, succeeded: true, message: nil) }
    }
}

@MainActor
final class DockerDiskViewModelTests: XCTestCase {

    private func makeViewModel(
        docker: FakeDockerSystemService = FakeDockerSystemService()
    ) -> DockerDiskViewModel {
        DockerDiskViewModel(dockerService: docker, warnThreshold: 0.85, criticalThreshold: 0.93)
    }

    func testAlertLevelIsNormalBelowWarnThreshold() async {
        let docker = FakeDockerSystemService()
        docker.headroomResult = .success(
            DockerHeadroom(totalBytes: 1000, usedBytes: 700, availableBytes: 300)  // 70%
        )
        let viewModel = makeViewModel(docker: docker)

        await viewModel.refreshHeadroom()

        XCTAssertEqual(viewModel.alertLevel, .normal)
    }

    func testAlertLevelIsWarningAtWarnThreshold() async {
        let docker = FakeDockerSystemService()
        docker.headroomResult = .success(
            DockerHeadroom(totalBytes: 1000, usedBytes: 870, availableBytes: 130)  // 87%
        )
        let viewModel = makeViewModel(docker: docker)

        await viewModel.refreshHeadroom()

        XCTAssertEqual(viewModel.alertLevel, .warning)
    }

    func testAlertLevelIsCriticalAtCriticalThreshold() async {
        let docker = FakeDockerSystemService()
        docker.headroomResult = .success(
            DockerHeadroom(totalBytes: 1000, usedBytes: 950, availableBytes: 50)  // 95%
        )
        let viewModel = makeViewModel(docker: docker)

        await viewModel.refreshHeadroom()

        XCTAssertEqual(viewModel.alertLevel, .critical)
    }

    func testFailedHeadroomProbeProducesNoWarning() async {
        // Critical: a failed probe must never be read as "0% free".
        struct Boom: Error {}
        let docker = FakeDockerSystemService()
        docker.headroomResult = .failure(Boom())
        let viewModel = makeViewModel(docker: docker)

        await viewModel.refreshHeadroom()

        XCTAssertNil(viewModel.headroom)
        XCTAssertEqual(viewModel.alertLevel, .normal, "unmeasurable disk must not raise an alert")
    }

    func testExecuteReclaimRunsPlannedActions() async {
        let docker = FakeDockerSystemService()
        docker.usageResult = .success(DockerUsage(
            images: DockerUsageCategory(totalCount: 5, active: 1, sizeBytes: 10_000, reclaimableBytes: 5_000),
            containers: DockerUsageCategory(totalCount: 0, active: 0, sizeBytes: 0, reclaimableBytes: 0),
            volumes: DockerUsageCategory(totalCount: 0, active: 0, sizeBytes: 0, reclaimableBytes: 0),
            buildCache: DockerUsageCategory(totalCount: 3, active: 0, sizeBytes: 2_000, reclaimableBytes: 2_000)
        ))
        docker.volumesResult = .success([
            DockerVolume(name: "westlife_project_mutagen", sizeBytes: 1_000, links: 0)
        ])
        let viewModel = makeViewModel(docker: docker)

        await viewModel.refreshFullInventory(projects: [])
        await viewModel.executeReclaim()

        XCTAssertTrue(docker.prunedBuildCache)
        XCTAssertTrue(docker.prunedImages)
        XCTAssertEqual(docker.removedVolumes, ["westlife_project_mutagen"])
    }

    func testErrorMessageIsSetWhenInventoryFails() async {
        struct Boom: Error {}
        let docker = FakeDockerSystemService()
        docker.usageResult = .failure(Boom())
        let viewModel = makeViewModel(docker: docker)

        await viewModel.refreshFullInventory(projects: [])

        XCTAssertNotNil(viewModel.errorMessage)
    }
}
```

- [ ] **Step 2: Run to verify they fail**

Run: `swift test --filter DockerDiskViewModelTests`
Expected: FAIL — `cannot find 'DockerDiskViewModel' in scope`.

- [ ] **Step 3: Write the implementation**

Create `Sources/DDEVUIApp/ViewModels/DockerDiskViewModel.swift`:

```swift
import Foundation
import Observation

/// The view model's view of `DockerSystemService`, declared here so tests can substitute a
/// fake. Mirrors how `DDEVServicing` is declared alongside `ProjectDashboardViewModel`.
public protocol DockerSystemServicing: Sendable {
    func usage() async throws -> DockerUsage
    func headroom() async throws -> DockerHeadroom
    func volumes() async throws -> [DockerVolume]
    func pruneBuildCache() async throws -> CommandResult
    func pruneUnusedImages() async throws -> CommandResult
    func removeVolumes(_ names: [String]) async -> [VolumeRemovalResult]
}

extension DockerSystemService: DockerSystemServicing {}

public enum DiskAlertLevel: Equatable, Sendable {
    case normal
    case warning
    case critical
}

@MainActor
@Observable
public final class DockerDiskViewModel {
    public private(set) var headroom: DockerHeadroom?
    public private(set) var usage: DockerUsage?
    public private(set) var inventory: [ClassifiedVolume] = []
    public private(set) var plan: ReclaimPlan = ReclaimPlan(items: [])
    public private(set) var isLoadingInventory = false
    public private(set) var isReclaiming = false
    public private(set) var errorMessage: String?
    public private(set) var lastReclaimSummary: String?

    @ObservationIgnored private let dockerService: DockerSystemServicing
    @ObservationIgnored private let ddevService: DDEVServicing?
    @ObservationIgnored private let scheduler: CommandScheduler?
    @ObservationIgnored private let warnThreshold: Double
    @ObservationIgnored private let criticalThreshold: Double

    public init(
        dockerService: DockerSystemServicing = DockerSystemService(),
        ddevService: DDEVServicing? = nil,
        scheduler: CommandScheduler? = nil,
        warnThreshold: Double = 0.85,
        criticalThreshold: Double = 0.93
    ) {
        self.dockerService = dockerService
        self.ddevService = ddevService
        self.scheduler = scheduler
        self.warnThreshold = warnThreshold
        self.criticalThreshold = criticalThreshold
    }

    /// `.normal` whenever headroom is unknown. An unmeasurable disk must never raise an
    /// alert — a failed probe is not evidence of a full disk.
    public var alertLevel: DiskAlertLevel {
        guard let headroom else { return .normal }
        if headroom.usedFraction >= criticalThreshold { return .critical }
        if headroom.usedFraction >= warnThreshold { return .warning }
        return .normal
    }

    /// Cheap enough for the background refresh cycle.
    public func refreshHeadroom() async {
        do {
            headroom = try await dockerService.headroom()
        } catch {
            // Deliberately silent: Docker may simply not be running. Clearing the value keeps
            // `alertLevel` at `.normal` rather than reporting a false emergency.
            headroom = nil
        }
    }

    /// Expensive — walks every volume. Call only when the screen is open or on explicit refresh.
    public func refreshFullInventory(projects: [DDEVProject]) async {
        isLoadingInventory = true
        errorMessage = nil
        defer { isLoadingInventory = false }

        do {
            async let usageTask = dockerService.usage()
            async let volumesTask = dockerService.volumes()
            let (loadedUsage, loadedVolumes) = try await (usageTask, volumesTask)

            usage = loadedUsage
            inventory = ReclaimPlanner.classify(volumes: loadedVolumes, projects: projects)
            plan = ReclaimPlanner.plan(volumes: loadedVolumes, projects: projects, usage: loadedUsage)
            await refreshHeadroom()
        } catch {
            errorMessage = error.presentableMessage
        }
    }

    /// Runs every action in the current plan. Individual failures are collected rather than
    /// aborting the batch.
    public func executeReclaim() async {
        guard !plan.isEmpty else { return }
        isReclaiming = true
        errorMessage = nil
        defer { isReclaiming = false }

        var failures: [String] = []
        var volumeNames: [String] = []

        for item in plan.items {
            switch item.action {
            case .buildCache:
                await record(&failures, item.label) { _ = try await self.dockerService.pruneBuildCache() }
            case .unusedImages:
                await record(&failures, item.label) { _ = try await self.dockerService.pruneUnusedImages() }
            case let .mutagenReset(_, appRoot):
                await record(&failures, item.label) {
                    guard let ddevService = self.ddevService else { return }
                    _ = try await ddevService.mutagen(.reset, in: appRoot)
                }
            case let .removeVolume(name):
                volumeNames.append(name)
            }
        }

        if !volumeNames.isEmpty {
            let results = await dockerService.removeVolumes(volumeNames)
            failures.append(contentsOf: results.filter { !$0.succeeded }.map(\.name))
        }

        lastReclaimSummary = failures.isEmpty
            ? "Reclaimed \(plan.totalBytes.formattedBytes)."
            : "Reclaimed with \(failures.count) failure(s): \(failures.joined(separator: ", "))."

        await refreshHeadroom()
    }

    /// Explicit per-item removal — the only route by which a registered project's database
    /// can be deleted.
    public func removeVolume(named name: String) async {
        isReclaiming = true
        defer { isReclaiming = false }

        let results = await dockerService.removeVolumes([name])
        if let failure = results.first(where: { !$0.succeeded }) {
            errorMessage = failure.message ?? "Could not remove \(name)."
        }
        await refreshHeadroom()
    }

    /// Maintenance action — this *consumes* disk rather than reclaiming it.
    public func prefetchImages() async {
        guard let ddevService else { return }
        isReclaiming = true
        errorMessage = nil
        defer { isReclaiming = false }
        do {
            _ = try await ddevService.downloadImages()
        } catch {
            errorMessage = error.presentableMessage
        }
    }

    private func record(
        _ failures: inout [String],
        _ label: String,
        _ operation: () async throws -> Void
    ) async {
        do {
            if let scheduler {
                // `run` is generic over a Sendable return; wrap the void operation.
                try await scheduler.run { try await operation() }
            } else {
                try await operation()
            }
        } catch {
            failures.append(label)
        }
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `swift test --filter DockerDiskViewModelTests`
Expected: PASS, 6 tests.

If the `scheduler.run { try await operation() }` line fails to compile because `operation`
is a non-escaping, non-`Sendable` closure, change `record` to take an
`@escaping @Sendable () async throws -> Void` and pass the closures accordingly.

- [ ] **Step 5: Commit**

```bash
git add Sources/DDEVUIApp/ViewModels/DockerDiskViewModel.swift Tests/DDEVUIAppTests/DockerDiskViewModelTests.swift
git commit -m "feat: Add Docker disk view model"
```

---

### Task 11: Docker Disk screen

The destination. Built on the `DiagnosticsView` template.

**Files:**
- Create: `Sources/DDEVUIApp/Views/DockerDiskView.swift`
- Modify: `Sources/DDEVUIApp/ViewModels/ProjectDashboardViewModel.swift:69-114` (add `.dockerDisk` case)
- Modify: `Sources/DDEVUIApp/Views/ContentView.swift:82-92` (route the new case)

**Interfaces:**
- Consumes: `DockerDiskViewModel` (Task 10), `ProjectDashboardViewModel`, `Int64.formattedBytes` (Task 1).
- Produces: `DockerDiskView(viewModel:dashboard:)`; `ProjectSidebarItem.dockerDisk`.

- [ ] **Step 1: Add the sidebar case**

In `ProjectDashboardViewModel.swift`, add to `ProjectSidebarItem`:

```swift
    case dockerDisk
```

placed after `case diagnostics`. Then add to the two `switch` statements:

```swift
        case .dockerDisk:
            "Docker Disk"
```

in `title`, and:

```swift
        case .dockerDisk:
            "internaldrive"
```

in `systemImage`.

- [ ] **Step 2: Verify the enum change compiles**

Run: `swift build 2>&1 | tail -20`
Expected: build errors *only* in `ContentView.swift` if any switch there is exhaustive over
`ProjectSidebarItem`. Note them; Step 4 fixes them. If the build succeeds, continue.

- [ ] **Step 3: Create the screen**

Create `Sources/DDEVUIApp/Views/DockerDiskView.swift`:

```swift
import SwiftUI

/// Shows what is consuming the Docker VM's disk and offers a safe-by-default reclaim.
/// Follows the `DiagnosticsView` full-pane layout.
struct DockerDiskView: View {
    var viewModel: DockerDiskViewModel
    var dashboard: ProjectDashboardViewModel

    @State private var confirmReclaim = false
    @State private var volumePendingRemoval: ClassifiedVolume?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header
                headroomSection

                if let message = viewModel.errorMessage {
                    Label(message, systemImage: "xmark.octagon.fill")
                        .font(.callout)
                        .foregroundStyle(.red)
                }

                if let summary = viewModel.lastReclaimSummary {
                    Label(summary, systemImage: "checkmark.circle.fill")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                breakdownSection
                reclaimSection
                volumesSection
                maintenanceSection
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationTitle("Docker Disk")
        .task { await viewModel.refreshFullInventory(projects: dashboard.projects) }
        .confirmationDialog("Reclaim disk space?", isPresented: $confirmReclaim) {
            Button("Reclaim \(viewModel.plan.totalBytes.formattedBytes)", role: .destructive) {
                Task { await viewModel.executeReclaim() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(
                "Removes build cache, unused images, and sync caches for stopped projects. "
                + "Sync caches rebuild automatically on the next start. No project database is touched."
            )
        }
        .confirmationDialog(
            "Delete this volume?",
            isPresented: .isPresent($volumePendingRemoval),
            presenting: volumePendingRemoval
        ) { classified in
            Button("Delete \(classified.volume.name)", role: .destructive) {
                Task { await viewModel.removeVolume(named: classified.volume.name) }
            }
            Button("Cancel", role: .cancel) {}
        } message: { classified in
            Text(
                classified.kind == .database
                ? "This permanently deletes the database for \(classified.projectName ?? classified.volume.name). "
                  + "Take a snapshot first if you might need it."
                : "This permanently deletes \(classified.volume.name)."
            )
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("Docker Disk")
                    .font(.largeTitle.bold())
                Spacer()
                Button {
                    Task { await viewModel.refreshFullInventory(projects: dashboard.projects) }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .disabled(viewModel.isLoadingInventory)
            }
            Text("DDEV fails to start when the Docker VM runs out of space. Reclaim it here.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    private var headroomSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Headroom").sectionHeaderStyle()

            if let headroom = viewModel.headroom {
                VStack(alignment: .leading, spacing: 6) {
                    ProgressView(value: headroom.usedFraction)
                        .tint(tint(for: viewModel.alertLevel))
                    Text(
                        "\(headroom.usedBytes.formattedBytes) of \(headroom.totalBytes.formattedBytes) used "
                        + "· \(headroom.availableBytes.formattedBytes) free"
                    )
                    .font(.callout)
                    .foregroundStyle(.secondary)
                }
            } else {
                Text("Headroom unavailable — is Docker running?")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var breakdownSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Breakdown").sectionHeaderStyle()

            if let usage = viewModel.usage {
                VStack(spacing: 4) {
                    breakdownRow("Images", usage.images)
                    breakdownRow("Containers", usage.containers)
                    breakdownRow("Volumes", usage.volumes)
                    breakdownRow("Build cache", usage.buildCache)
                }
            } else if viewModel.isLoadingInventory {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Reading Docker usage…").foregroundStyle(.secondary)
                }
            }
        }
    }

    private func breakdownRow(_ title: String, _ category: DockerUsageCategory) -> some View {
        HStack {
            Text(title).frame(width: 140, alignment: .leading)
            Text(category.sizeBytes.formattedBytes)
                .frame(width: 100, alignment: .trailing)
            Text("\(category.reclaimableBytes.formattedBytes) reclaimable")
                .foregroundStyle(.secondary)
            Spacer()
        }
        .font(.callout)
    }

    private var reclaimSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Reclaim safely").sectionHeaderStyle()

            if viewModel.plan.isEmpty {
                Text("Nothing to reclaim.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(viewModel.plan.items) { item in
                        HStack {
                            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                            Text(item.label)
                            Text(item.detail).foregroundStyle(.secondary).font(.caption)
                            Spacer()
                            Text(item.estimatedBytes.formattedBytes).foregroundStyle(.secondary)
                        }
                        .font(.callout)
                    }
                }

                Button {
                    confirmReclaim = true
                } label: {
                    Label("Reclaim \(viewModel.plan.totalBytes.formattedBytes)", systemImage: "trash")
                }
                .buttonStyle(.borderedProminent)
                .disabled(viewModel.isReclaiming)

                Text("Project databases are never included here.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if viewModel.isReclaiming {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Reclaiming…").foregroundStyle(.secondary)
                }
            }
        }
    }

    private var volumesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("All volumes").sectionHeaderStyle()

            ForEach(viewModel.inventory) { classified in
                HStack {
                    Text(classified.volume.name)
                        .font(.system(.caption, design: .monospaced))
                    Text(stateLabel(classified))
                        .font(.caption)
                        .foregroundStyle(classified.state == .orphaned ? .orange : .secondary)
                    Spacer()
                    Text(classified.volume.sizeBytes.formattedBytes)
                        .foregroundStyle(.secondary)
                    Button(role: .destructive) {
                        volumePendingRemoval = classified
                    } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.borderless)
                    .disabled(classified.state == .running || viewModel.isReclaiming)
                    .help(classified.state == .running ? "In use — stop the project first" : "Delete this volume")
                }
            }
        }
    }

    private var maintenanceSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Maintenance").sectionHeaderStyle()
            Button {
                Task { await viewModel.prefetchImages() }
            } label: {
                Label("Prefetch Images", systemImage: "arrow.down.circle")
            }
            .disabled(viewModel.isReclaiming)
            .help("Pre-pull every image DDEV needs (ddev utility download-images)")

            Text("Uses disk space rather than reclaiming it — makes the next start faster.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func stateLabel(_ classified: ClassifiedVolume) -> String {
        let kind = switch classified.kind {
        case .mutagen: "sync cache"
        case .database: "database"
        case .other: "other"
        }
        let state = switch classified.state {
        case .running: "running"
        case .stopped: "stopped"
        case .orphaned: "orphaned — no such DDEV project"
        }
        return "\(kind) · \(state)"
    }

    private func tint(for level: DiskAlertLevel) -> Color {
        switch level {
        case .normal: .accentColor
        case .warning: .orange
        case .critical: .red
        }
    }
}
```

- [ ] **Step 4: Route the new sidebar case**

In `ContentView.swift`, in the `content:` closure, add before `default:`:

```swift
            case .library(.dockerDisk):
                DockerDiskView(viewModel: dockerDiskViewModel, dashboard: viewModel)
                    .navigationSplitViewColumnWidth(min: 520, ideal: 720)
```

`ContentView` needs a `DockerDiskViewModel`. Add the stored property alongside the existing
ones:

```swift
    var dockerDiskViewModel: DockerDiskViewModel
```

In `DDEVUIApp.swift`, construct it once as a `@State` property on the `App` struct, next to
the existing view model, and pass it to both `ContentView` and `MenuBarContentView`:

```swift
    @State private var dockerDiskViewModel = DockerDiskViewModel(
        dockerService: DockerSystemService(),
        ddevService: DDEVCommandService(),
        warnThreshold: 0.85,
        criticalThreshold: 0.93
    )
```

Then update the `ContentView` construction site to pass it:

```swift
            ContentView(
                viewModel: viewModel,
                prerequisites: prerequisites,
                dockerDiskViewModel: dockerDiskViewModel
            )
```

In the `detail:` closure of `ContentView`'s `NavigationSplitView`, find the arm that handles
`.library(.diagnostics)` with a `ContentUnavailableView` and add an identical arm for
`.library(.dockerDisk)`:

```swift
            case .library(.dockerDisk):
                ContentUnavailableView(
                    "Docker Disk",
                    systemImage: "internaldrive",
                    description: Text("Disk usage and reclaim actions are shown in the middle column.")
                )
```

If the existing diagnostics arm is written differently (e.g. folded into a `default:`), match
that structure instead of introducing a new one.

**Note on thresholds:** the constructor above hardcodes the defaults rather than reading
`PreferencesModel`, because `DDEVUIApp` builds these before the preferences model is
available. Reading the stored preferences here is a follow-up; the defaults are correct and
the properties added in Task 9 are what a future Settings control will bind to. Do not block
this task on it.

- [ ] **Step 5: Build and confirm the screen renders**

Run: `swift build 2>&1 | tail -5`
Expected: `Build complete!`

Then build and launch the real app (per the repo's verification note, `swift run` crashes on
`UNUserNotificationCenter` — use a proper bundle):

```bash
xcodebuild -project DDEVUI.xcodeproj -scheme DDEVUI -configuration Debug -derivedDataPath /tmp/ddevui-build build 2>&1 | tail -5
open /tmp/ddevui-build/Build/Products/Debug/DDEVUI.app
```

Confirm: a "Docker Disk" item appears in the sidebar; selecting it shows headroom, a
breakdown, and a reclaim plan. **Do not press Reclaim yet** — Task 12 has not wired the
menu bar, and manual verification of the destructive path belongs in Task 13.

- [ ] **Step 6: Commit**

```bash
git add Sources/DDEVUIApp/Views/DockerDiskView.swift Sources/DDEVUIApp/Views/ContentView.swift Sources/DDEVUIApp/ViewModels/ProjectDashboardViewModel.swift Sources/DDEVUIApp/DDEVUIApp.swift
git commit -m "feat: Add Docker Disk screen"
```

---

### Task 12: Menu bar warning

The proactive surface. Absent entirely below the warning threshold.

**Files:**
- Modify: `Sources/DDEVUIApp/Views/MenuBarContentView.swift`
- Modify: `Sources/DDEVUIApp/DDEVUIApp.swift` (icon + tint)

**Interfaces:**
- Consumes: `DockerDiskViewModel.alertLevel`, `.headroom` (Task 10).
- Produces: no new public API.

- [ ] **Step 1: Add the headroom row**

In `MenuBarContentView.swift`, add the property:

```swift
    var dockerDisk: DockerDiskViewModel
```

and insert at the very top of `body`, before the project list:

```swift
        if dockerDisk.alertLevel != .normal, let headroom = dockerDisk.headroom {
            Text("Docker disk \(headroom.percentUsed)% · \(headroom.availableBytes.formattedBytes) free")

            Button("Reclaim \(dockerDisk.plan.totalBytes.formattedBytes)…") {
                openWindow(id: DDEVUIApp.mainWindowID)
                NSApp.activate(ignoringOtherApps: true)
                viewModel.selection = .library(.dockerDisk)
            }

            Divider()
        }
```

The button navigates rather than executing — a destructive bulk operation must not be one
hover away.

- [ ] **Step 2: Drive the menu bar icon from the alert level**

In `DDEVUIApp.swift`, replace the static `MenuBarExtra("DDEVUI", systemImage: "shippingbox.fill")`
label with a computed one:

```swift
        MenuBarExtra {
            MenuBarContentView(viewModel: viewModel, dockerDisk: dockerDiskViewModel)
        } label: {
            Image(systemName: dockerDiskViewModel.alertLevel == .normal
                  ? "shippingbox.fill"
                  : "exclamationmark.triangle.fill")
        }
```

- [ ] **Step 3: Refresh headroom on the existing cycle**

Find where `ContentView` triggers the periodic project refresh (search for
`refreshProjectsFromDDEV` or the `.task` on `ContentView`) and add alongside it:

```swift
            await dockerDiskViewModel.refreshHeadroom()
```

Do **not** call `refreshFullInventory` here — it walks every volume and takes seconds.

- [ ] **Step 4: Build and verify manually**

Run:
```bash
xcodebuild -project DDEVUI.xcodeproj -scheme DDEVUI -configuration Debug -derivedDataPath /tmp/ddevui-build build 2>&1 | tail -5
open /tmp/ddevui-build/Build/Products/Debug/DDEVUI.app
```

Confirm the menu bar shows the normal box icon and **no** disk row, since the disk currently
sits at ~71%, below the 85% threshold.

To verify the warning path without filling the disk, temporarily construct the view model
with `warnThreshold: 0.5` in `DDEVUIApp.swift`, rebuild, and confirm the triangle icon and
the disk row both appear. **Revert the threshold to `0.85` before committing.**

- [ ] **Step 5: Run the full suite**

Run: `swift test 2>&1 | tail -20`
Expected: all tests pass.

- [ ] **Step 6: Commit**

```bash
git add Sources/DDEVUIApp/Views/MenuBarContentView.swift Sources/DDEVUIApp/DDEVUIApp.swift Sources/DDEVUIApp/Views/ContentView.swift
git commit -m "feat: Warn about low Docker disk in the menu bar"
```

---

### Task 13: Absorb the old Settings buttons

Remove the two overlapping Maintenance entries now that the Docker Disk screen covers them.

**Files:**
- Modify: `Sources/DDEVUIApp/Views/ContentView.swift` (Maintenance section ~331-377, dialog ~396-404)

**Interfaces:**
- Consumes: nothing new.
- Produces: nothing new. `ProjectDashboardViewModel.deleteDDEVImages()` / `downloadDDEVImages()`
  remain but lose their Settings call sites.

- [ ] **Step 1: Remove the Download Images button**

Delete from the `Maintenance` section:

```swift
                Button {
                    Task { await viewModel.downloadDDEVImages() }
                } label: {
                    Label("Download Images", systemImage: "arrow.down.circle")
                }
                .help("Pre-pull every image DDEV needs (ddev utility download-images)")
```

- [ ] **Step 2: Remove the Delete DDEV Images button**

Delete:

```swift
                Button(role: .destructive) {
                    confirmDeleteImages = true
                } label: {
                    Label("Delete DDEV Images", systemImage: "trash")
                }
                .help("Remove DDEV Docker images to reclaim disk (ddev delete images)")
```

- [ ] **Step 3: Remove the now-unused dialog and state**

Delete the `confirmDeleteImages` confirmation dialog:

```swift
        .confirmationDialog("Delete DDEV images?", isPresented: $confirmDeleteImages) {
            Button("Delete Images", role: .destructive) {
                Task { await viewModel.deleteDDEVImages() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Removes DDEV's Docker images to reclaim disk. They're re-downloaded on next start — no project data is lost.")
        }
```

and the state property `@State private var confirmDeleteImages = false`.

Leave `confirmPowerOff`, `Power Off All Projects`, and `Stop Paused Projects` untouched —
those are lifecycle actions, not disk.

- [ ] **Step 4: Add a pointer to the new screen**

At the end of the `Maintenance` section, add:

```swift
                Text("Image and disk cleanup has moved to Docker Disk.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
```

- [ ] **Step 5: Build and check for unused-variable warnings**

Run: `swift build 2>&1 | tail -20`
Expected: `Build complete!` with no warnings about an unused `confirmDeleteImages`.

- [ ] **Step 6: Verify manually, including the destructive path**

Run:
```bash
xcodebuild -project DDEVUI.xcodeproj -scheme DDEVUI -configuration Debug -derivedDataPath /tmp/ddevui-build build 2>&1 | tail -5
open /tmp/ddevui-build/Build/Products/Debug/DDEVUI.app
```

Confirm:
1. Settings → Maintenance no longer lists the two image buttons.
2. Docker Disk lists a plan.
3. **Before pressing Reclaim**, record the current state:
   ```bash
   docker volume ls --format '{{.Name}}' | grep -c mariadb
   ```
   Note the number.
4. Press **Reclaim**, confirm the dialog, and wait for it to finish.
5. Re-run the same command. **The mariadb count must be unchanged.** If a single database
   volume disappeared, stop and treat it as a `ReclaimPlanner` bug — that is the one
   outcome this whole feature exists to prevent.
6. Confirm reported free space increased.

- [ ] **Step 7: Run the full suite**

Run: `swift test 2>&1 | tail -20`
Expected: all tests pass.

- [ ] **Step 8: Commit**

```bash
git add Sources/DDEVUIApp/Views/ContentView.swift
git commit -m "refactor: Move image cleanup into Docker Disk screen"
```

---

## Verification Checklist

Run before opening a PR. Paste real output — do not assert from memory.

- [ ] `swift build 2>&1 | tail -5` → `Build complete!`
- [ ] `swift test 2>&1 | tail -20` → all pass, including 15 `ReclaimPlannerTests`
- [ ] App launches from an `xcodebuild` bundle and the Docker Disk screen renders
- [ ] Menu bar shows no disk row below 85%, and a warning row above it
- [ ] A live Reclaim leaves the `-mariadb` volume count unchanged
- [ ] `git log --oneline main..HEAD` shows one commit per task, conventional format
