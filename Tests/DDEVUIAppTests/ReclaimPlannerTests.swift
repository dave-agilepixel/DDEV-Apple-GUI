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
