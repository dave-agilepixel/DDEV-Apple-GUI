import XCTest
@testable import DDEVUIApp

@MainActor
final class ProjectDashboardViewModelTests: XCTestCase {
    func testRefreshLoadsProjectsAndSelectsFirstProject() async {
        let service = FakeDDEVService(projects: [.sampleWordPress])
        let viewModel = ProjectDashboardViewModel(ddevService: service)

        await viewModel.refresh()

        XCTAssertEqual(viewModel.projects, [.sampleWordPress])
        XCTAssertEqual(viewModel.selectedProject, .sampleWordPress)
        XCTAssertNil(viewModel.globalErrorMessage)
    }

    func testSearchFiltersProjectsByNamePathAndType() {
        let viewModel = ProjectDashboardViewModel(ddevService: FakeDDEVService(projects: []))
        viewModel.projects = [.sampleWordPress, .sampleLaravel]

        viewModel.searchText = "bugs"
        XCTAssertEqual(viewModel.filteredProjects, [.sampleLaravel])

        viewModel.searchText = "wordpress"
        XCTAssertEqual(viewModel.filteredProjects, [.sampleWordPress])
    }

    func testSidebarFiltersProjectsBySection() {
        let viewModel = ProjectDashboardViewModel(ddevService: FakeDDEVService(projects: []))
        viewModel.projects = [.sampleWordPress, .sampleLaravel]

        viewModel.selectedSidebarItem = .projects
        XCTAssertEqual(viewModel.filteredProjects, [.sampleWordPress, .sampleLaravel])

        viewModel.selectedSidebarItem = .running
        XCTAssertEqual(viewModel.filteredProjects, [.sampleWordPress])

        viewModel.selectedSidebarItem = .wordpress
        XCTAssertEqual(viewModel.filteredProjects, [.sampleWordPress])

        viewModel.selectedSidebarItem = .diagnostics
        XCTAssertEqual(viewModel.filteredProjects, [])
        XCTAssertEqual(ProjectSidebarItem.diagnostics.title, "Diagnostics")
    }

    func testRefreshAddsPHPVersionsFromProjectDetails() async {
        let service = FakeDDEVService(projects: [.sampleWordPress], phpVersions: ["aqua-pura": "8.4"])
        let viewModel = ProjectDashboardViewModel(ddevService: service)

        await viewModel.refresh()

        XCTAssertEqual(viewModel.projects.first?.phpVersion, "8.4")
        XCTAssertEqual(service.commands, ["list", "describe:aqua-pura"])
    }

    func testRefreshAddsXHGuiStatusFromProjectDetails() async {
        let project = DDEVProject.sampleWordPress.withXHGuiURLs(
            xhguiURL: URL(string: "http://aqua-pura.ddev.site:8143"),
            xhguiHTTPSURL: URL(string: "https://aqua-pura.ddev.site:8142")
        )
        let service = FakeDDEVService(
            projects: [project],
            xhguiStatuses: ["aqua-pura": .disabled]
        )
        let viewModel = ProjectDashboardViewModel(ddevService: service)

        await viewModel.refresh()

        XCTAssertEqual(viewModel.projects.first?.xhguiStatus, .disabled)
        XCTAssertNil(viewModel.projects.first?.openableXHGuiURL)
    }

    func testLoadCachedProjectsThenRefreshShowsFreshProjectsAndPersistsThem() async {
        let service = FakeDDEVService(projects: [.sampleLaravel])
        let cache = InMemoryProjectCacheStore(projects: [.sampleWordPress])
        let viewModel = ProjectDashboardViewModel(ddevService: service, projectCache: cache)

        await viewModel.loadCachedProjectsThenRefresh()

        XCTAssertEqual(viewModel.projects, [.sampleLaravel])
        XCTAssertEqual(viewModel.selectedProject, .sampleLaravel)
        XCTAssertEqual(service.commands, ["list", "describe:agilebugs"])
        XCTAssertEqual(cache.projects, [.sampleLaravel])
    }

    func testBackgroundRefreshFailureKeepsCachedProjectsVisibleWithoutSurfacingError() async {
        let service = FakeDDEVService(projects: [], listError: TestError.expected)
        let cache = InMemoryProjectCacheStore(projects: [.sampleWordPress])
        let viewModel = ProjectDashboardViewModel(ddevService: service, projectCache: cache)

        await viewModel.loadCachedProjectsThenRefresh()

        XCTAssertEqual(viewModel.projects, [.sampleWordPress])
        XCTAssertEqual(viewModel.selectedProject, .sampleWordPress)
        XCTAssertNil(viewModel.globalErrorMessage)
        XCTAssertFalse(viewModel.isRunningGlobalCommand)
    }

    func testInitialRefreshFailureSurfacesErrorWhenNoCacheExists() async {
        let service = FakeDDEVService(projects: [], listError: TestError.expected)
        let cache = InMemoryProjectCacheStore()
        let viewModel = ProjectDashboardViewModel(ddevService: service, projectCache: cache)

        await viewModel.loadCachedProjectsThenRefresh()

        XCTAssertTrue(viewModel.projects.isEmpty)
        XCTAssertNotNil(viewModel.globalErrorMessage)
        XCTAssertFalse(viewModel.isRunningGlobalCommand)
    }

    func testRefreshPreservesSelectedProjectWhenCurrentSelectionIsFilteredOut() async {
        let service = FakeDDEVService(projects: [.sampleWordPress, .sampleLaravel])
        let viewModel = ProjectDashboardViewModel(ddevService: service)
        viewModel.selectedProject = .sampleLaravel
        viewModel.selectedSidebarItem = .running

        await viewModel.refresh()

        XCTAssertEqual(viewModel.selectedProject, .sampleLaravel)
    }

    func testWordPressActionsOnlyAvailableForWordPressProjects() {
        let viewModel = ProjectDashboardViewModel(ddevService: FakeDDEVService(projects: []))

        XCTAssertTrue(viewModel.canRunWordPressActions(for: .sampleWordPress))
        XCTAssertFalse(viewModel.canRunWordPressActions(for: .sampleLaravel))
        XCTAssertFalse(viewModel.canRunWordPressActions(for: nil))
    }

    func testStartSelectedProjectRefreshesAfterCommand() async {
        let service = FakeDDEVService(projects: [.sampleWordPress])
        let viewModel = ProjectDashboardViewModel(ddevService: service)
        viewModel.selectedProject = .sampleWordPress

        await viewModel.startSelectedProject()

        XCTAssertEqual(service.commands, ["start:aqua-pura", "describe:aqua-pura"])
        XCTAssertEqual(viewModel.selectedProjectState.lastResult?.succeeded, true)
    }

    func testRowActionTargetsGivenProjectNotSelection() async {
        let service = FakeDDEVService(projects: [.sampleWordPress, .sampleLaravel])
        let viewModel = ProjectDashboardViewModel(ddevService: service)

        await viewModel.refresh()
        XCTAssertEqual(viewModel.selectedProject, .sampleWordPress)

        await viewModel.stop(.sampleLaravel)

        XCTAssertTrue(service.commands.contains("stop:agilebugs"))
        XCTAssertEqual(viewModel.selectedProject, .sampleWordPress)
    }

    func testDatabaseToolLaunchUsesSelectedProjectFolder() async {
        let service = FakeDDEVService(projects: [.sampleWordPress])
        let viewModel = ProjectDashboardViewModel(ddevService: service)
        viewModel.selectedProject = .sampleWordPress

        await viewModel.launchDatabaseTool(.tablePlus)

        XCTAssertEqual(service.commands, [
            "db:tableplus:/Users/dave/Development/agilepixel/aqua-pura"
        ])
    }

    func testViewModelExposesEffectiveDefaultEditor() {
        let viewModel = ProjectDashboardViewModel(
            ddevService: FakeDDEVService(projects: []),
            preferencesStore: InMemoryAppPreferencesStore(),
            appAvailability: StaticAppAvailabilityService(installedBundleIdentifiers: ["com.microsoft.VSCode"])
        )

        XCTAssertEqual(viewModel.availableEditors, [.visualStudioCode, .finder])
        XCTAssertEqual(viewModel.effectiveDefaultEditor, .visualStudioCode)
    }

    func testViewModelLaunchesDefaultDatabaseTool() async {
        let service = FakeDDEVService(projects: [.sampleWordPress])
        let viewModel = ProjectDashboardViewModel(
            ddevService: service,
            preferencesStore: InMemoryAppPreferencesStore(),
            appAvailability: StaticAppAvailabilityService(installedBundleIdentifiers: ["com.tinyapp.TablePlus"])
        )
        viewModel.selectedProject = .sampleWordPress

        await viewModel.launchDefaultDatabaseTool()

        XCTAssertEqual(service.commands, [
            "db:tableplus:/Users/dave/Development/agilepixel/aqua-pura"
        ])
    }

    func testViewModelDoesNotLaunchDatabaseWhenNoToolIsInstalled() async {
        let service = FakeDDEVService(projects: [.sampleWordPress])
        let viewModel = ProjectDashboardViewModel(
            ddevService: service,
            preferencesStore: InMemoryAppPreferencesStore(),
            appAvailability: StaticAppAvailabilityService(installedBundleIdentifiers: [])
        )
        viewModel.selectedProject = .sampleWordPress

        await viewModel.launchDefaultDatabaseTool()

        XCTAssertEqual(service.commands, [])
    }

    func testDefaultAppSettersUpdateStateAndPersist() {
        let preferencesStore = InMemoryAppPreferencesStore()
        let viewModel = ProjectDashboardViewModel(
            ddevService: FakeDDEVService(projects: []),
            preferencesStore: preferencesStore,
            appAvailability: StaticAppAvailabilityService(installedBundleIdentifiers: [
                "com.microsoft.VSCode",
                "com.tinyapp.TablePlus"
            ])
        )

        viewModel.setDefaultEditor(.visualStudioCode)
        viewModel.setDefaultDatabaseTool(.tablePlus)

        XCTAssertEqual(viewModel.preferences, AppPreferences(defaultEditor: .visualStudioCode, defaultDatabaseTool: .tablePlus))
        XCTAssertEqual(viewModel.effectiveDefaultEditor, .visualStudioCode)
        XCTAssertEqual(viewModel.effectiveDefaultDatabaseTool, .tablePlus)
        XCTAssertEqual(preferencesStore.preferences, AppPreferences(defaultEditor: .visualStudioCode, defaultDatabaseTool: .tablePlus))
    }

    func testWordPressPresetActionsUseSelectedProjectFolder() async {
        let service = FakeDDEVService(projects: [.sampleWordPress])
        let viewModel = ProjectDashboardViewModel(ddevService: service)
        viewModel.selectedProject = .sampleWordPress

        await viewModel.updateWordPressCore()
        await viewModel.updateWordPressPlugins()
        await viewModel.updateWordPressThemes()

        XCTAssertEqual(service.commands, [
            "wp-core:/Users/dave/Development/agilepixel/aqua-pura",
            "describe:aqua-pura",
            "wp-plugins:/Users/dave/Development/agilepixel/aqua-pura",
            "describe:aqua-pura",
            "wp-themes:/Users/dave/Development/agilepixel/aqua-pura",
            "describe:aqua-pura"
        ])
    }

    func testFrameworkCommandPresetsAreTypeAware() {
        let viewModel = ProjectDashboardViewModel(ddevService: FakeDDEVService(projects: []))

        XCTAssertEqual(viewModel.frameworkCommands(for: .sampleWordPress).map(\.title), [
            "Update Core",
            "Update Plugins",
            "Update Themes",
            "Flush Cache"
        ])
        XCTAssertEqual(viewModel.frameworkCommands(for: .sampleLaravel).map(\.title), [
            "Migrate",
            "Fresh Migrate Seed",
            "Clear Cache",
            "List Routes"
        ])
    }

    func testRunFrameworkCommandUsesSelectedProjectFolderAndShowsOutput() async {
        let service = FakeDDEVService(projects: [.sampleLaravel])
        let viewModel = ProjectDashboardViewModel(ddevService: service)
        viewModel.selectedProject = .sampleLaravel

        let command = DDEVFrameworkCommand.presets(for: .laravel)
            .first { $0.title == "Clear Cache" }!

        await viewModel.runFrameworkCommandForSelectedProject(command)

        XCTAssertEqual(service.commands, [
            "project-command:/Users/dave/Development/agilepixel/agilebugs:artisan,cache:clear",
            "describe:agilebugs"
        ])
        XCTAssertEqual(viewModel.selectedProjectState.lastResult?.arguments, ["artisan", "cache:clear"])
        XCTAssertEqual(viewModel.selectedProjectState.history.map(\.result.arguments), [["artisan", "cache:clear"]])
        XCTAssertEqual(viewModel.selectedProjectState.outputExpansionRequest, 1)
    }

    func testDeleteDDEVDataRefreshesAfterCommand() async {
        let service = FakeDDEVService(projects: [.sampleWordPress])
        let viewModel = ProjectDashboardViewModel(ddevService: service)
        viewModel.selectedProject = .sampleWordPress

        await viewModel.deleteSelectedDDEVData()

        XCTAssertEqual(service.commands, ["delete:aqua-pura", "list", "describe:aqua-pura"])
    }

    func testConfigureProjectRunsDDEVConfigForFolder() async {
        let service = FakeDDEVService(projects: [])
        let viewModel = ProjectDashboardViewModel(ddevService: service)

        await viewModel.configureProject(
            folder: "/Users/dave/new-site",
            name: "new-site",
            type: .wordpress,
            docroot: "web"
        )

        XCTAssertEqual(service.commands, ["config:/Users/dave/new-site:new-site:wordpress:web", "list"])
    }

    func testSetPHPVersionUsesSelectedProjectFolder() async {
        let service = FakeDDEVService(projects: [.sampleWordPress], phpVersions: ["aqua-pura": "8.3"])
        let viewModel = ProjectDashboardViewModel(ddevService: service)
        viewModel.selectedProject = .sampleWordPress

        await viewModel.setPHPVersionForSelectedProject("8.3")

        XCTAssertEqual(service.commands, [
            "php:8.3:/Users/dave/Development/agilepixel/aqua-pura",
            "restart:aqua-pura",
            "describe:aqua-pura"
        ])
    }

    func testSetPHPVersionRecordsEachMutatingCommandInHistory() async {
        let service = FakeDDEVService(projects: [.sampleWordPress], phpVersions: ["aqua-pura": "8.3"])
        let viewModel = ProjectDashboardViewModel(ddevService: service)
        viewModel.selectedProject = .sampleWordPress

        await viewModel.setPHPVersionForSelectedProject("8.3")

        XCTAssertEqual(viewModel.selectedProjectState.history.map(\.result.arguments), [
            ["config", "--php-version=8.3"],
            ["restart", "aqua-pura"]
        ])
        XCTAssertEqual(viewModel.selectedProjectState.lastResult?.arguments, ["restart", "aqua-pura"])
    }

    func testSetPHPVersionDoesNotRestartPausedProject() async {
        let service = FakeDDEVService(projects: [.sampleLaravel], phpVersions: ["agilebugs": "8.2"])
        let viewModel = ProjectDashboardViewModel(ddevService: service)
        viewModel.selectedProject = .sampleLaravel

        await viewModel.setPHPVersionForSelectedProject("8.2")

        XCTAssertEqual(service.commands, [
            "php:8.2:/Users/dave/Development/agilepixel/agilebugs",
            "describe:agilebugs"
        ])
    }

    // MARK: - Live details (A1–A4)

    func testLoadDetailsPublishesDescribeDetailForSelectedProject() async {
        let details = DDEVProjectDetails(
            phpVersion: "8.3",
            xdebugEnabled: true,
            databaseInfo: DDEVDatabaseInfo(
                type: "mariadb", version: "11.8", host: "db", port: "3306",
                name: "db", username: "db", password: "db", publishedPort: 55043
            )
        )
        let service = FakeDDEVService(projects: [.sampleWordPress], describeDetails: ["aqua-pura": details])
        let viewModel = ProjectDashboardViewModel(ddevService: service)
        viewModel.selectedProject = .sampleWordPress

        await viewModel.loadDetailsForSelectedProject()

        XCTAssertEqual(viewModel.selectedProjectDetails?.xdebugEnabled, true)
        XCTAssertEqual(viewModel.selectedProjectDetails?.databaseInfo?.publishedPort, 55043)
    }

    func testSetXdebugRunsXdebugOnThenReReadsDetails() async {
        let enabled = DDEVProjectDetails(phpVersion: "8.3", xdebugEnabled: true)
        let service = FakeDDEVService(projects: [.sampleWordPress], describeDetails: ["aqua-pura": enabled])
        let viewModel = ProjectDashboardViewModel(ddevService: service)
        viewModel.selectedProject = .sampleWordPress

        await viewModel.setXdebugForSelectedProject(true)

        XCTAssertEqual(service.commands, [
            "xdebug:/Users/dave/Development/agilepixel/aqua-pura:on",
            "describe:aqua-pura"
        ])
        XCTAssertEqual(viewModel.selectedProjectDetails?.xdebugEnabled, true)
    }

    func testSetXdebugOffRunsXdebugOff() async {
        let service = FakeDDEVService(projects: [.sampleWordPress])
        let viewModel = ProjectDashboardViewModel(ddevService: service)
        viewModel.selectedProject = .sampleWordPress

        await viewModel.setXdebugForSelectedProject(false)

        XCTAssertEqual(service.commands.first, "xdebug:/Users/dave/Development/agilepixel/aqua-pura:off")
    }

    // MARK: - DB drift banner (A5)

    func testDBMatchWarningSetWhenCheckExitsNonZero() async {
        let mismatch = CommandResult.failure(
            stderr: "Database in volume mysql:8.0 does not match configured mariadb:11.8\n",
            exitCode: 1
        )
        let service = FakeDDEVService(
            projects: [.sampleWordPress],
            dbMatchResult: .failure(CommandRunnerError.nonZeroExit(mismatch))
        )
        let viewModel = ProjectDashboardViewModel(ddevService: service)
        viewModel.selectedProject = .sampleWordPress

        await viewModel.checkDBMatchForSelectedProject()

        XCTAssertEqual(
            viewModel.dbMatchWarning,
            "Database in volume mysql:8.0 does not match configured mariadb:11.8"
        )
    }

    func testDBMatchWarningClearedWhenVolumeMatches() async {
        let match = CommandResult.success(stdout: "database in volume matches configured database: mariadb:11.8\n")
        let service = FakeDDEVService(projects: [.sampleWordPress], dbMatchResult: .success(match))
        let viewModel = ProjectDashboardViewModel(ddevService: service)
        viewModel.selectedProject = .sampleWordPress

        await viewModel.checkDBMatchForSelectedProject()

        XCTAssertNil(viewModel.dbMatchWarning)
    }

    func testDBMatchCheckSkippedForNonRunningProject() async {
        let service = FakeDDEVService(
            projects: [.sampleLaravel],
            dbMatchResult: .failure(CommandRunnerError.nonZeroExit(CommandResult.failure(stderr: "drift", exitCode: 1)))
        )
        let viewModel = ProjectDashboardViewModel(ddevService: service)
        viewModel.selectedProject = .sampleLaravel // paused

        await viewModel.checkDBMatchForSelectedProject()

        XCTAssertNil(viewModel.dbMatchWarning)
        XCTAssertFalse(service.commands.contains { $0.hasPrefix("check-db-match") })
    }

    func testImportDatabaseUsesSelectedProjectFolderAndRefreshes() async {
        let service = FakeDDEVService(projects: [.sampleWordPress])
        let viewModel = ProjectDashboardViewModel(ddevService: service)
        viewModel.selectedProject = .sampleWordPress

        await viewModel.importDatabase(
            DDEVDatabaseImportOptions(
                filePath: "/Users/dave/Downloads/db.sql.gz",
                database: "legacy",
                dropExistingDatabase: false
            )
        )

        XCTAssertEqual(service.commands, [
            "import:/Users/dave/Development/agilepixel/aqua-pura:/Users/dave/Downloads/db.sql.gz:legacy::false",
            "describe:aqua-pura"
        ])
        XCTAssertEqual(viewModel.selectedProjectState.lastResult?.succeeded, true)
        XCTAssertEqual(viewModel.selectedProjectState.outputExpansionRequest, 1)
    }

    func testExportDatabaseUsesSelectedProjectFolderWithoutRefreshing() async {
        let service = FakeDDEVService(projects: [.sampleWordPress])
        let viewModel = ProjectDashboardViewModel(ddevService: service)
        viewModel.selectedProject = .sampleWordPress

        await viewModel.exportDatabase(
            DDEVDatabaseExportOptions(
                outputPath: "/Users/dave/Backups/db.sql.xz",
                database: "legacy",
                compression: .xz
            )
        )

        XCTAssertEqual(service.commands, [
            "export:/Users/dave/Development/agilepixel/aqua-pura:/Users/dave/Backups/db.sql.xz:legacy:xz"
        ])
        XCTAssertEqual(viewModel.selectedProjectState.lastResult?.succeeded, true)
        XCTAssertEqual(viewModel.selectedProjectState.outputExpansionRequest, 1)
    }

    func testFailedImportKeepsCommandOutputVisible() async {
        let failure = CommandResult(
            executable: "ddev",
            arguments: ["import-db"],
            workingDirectory: "/Users/dave/Development/agilepixel/aqua-pura",
            exitCode: 1,
            stdout: "Import started",
            stderr: "Invalid dump",
            startedAt: Date(),
            finishedAt: Date(),
            wasCancelled: false
        )
        let service = FakeDDEVService(projects: [.sampleWordPress], importError: CommandRunnerError.nonZeroExit(failure))
        let viewModel = ProjectDashboardViewModel(ddevService: service)
        viewModel.selectedProject = .sampleWordPress

        await viewModel.importDatabase(DDEVDatabaseImportOptions(filePath: "/Users/dave/Downloads/bad.sql"))

        XCTAssertEqual(viewModel.selectedProjectState.lastResult, failure)
        XCTAssertEqual(viewModel.selectedProjectState.lastErrorMessage, "Command failed with exit code 1.")
        XCTAssertEqual(viewModel.selectedProjectState.outputExpansionRequest, 1)
    }

    func testEachCompletedCommandRequestsOutputExpansion() async {
        let service = FakeDDEVService(projects: [.sampleWordPress])
        let viewModel = ProjectDashboardViewModel(ddevService: service)
        viewModel.selectedProject = .sampleWordPress

        await viewModel.exportDatabase(DDEVDatabaseExportOptions(outputPath: "/Users/dave/Backups/first.sql.gz"))
        await viewModel.exportDatabase(DDEVDatabaseExportOptions(outputPath: "/Users/dave/Backups/second.sql.gz"))

        XCTAssertEqual(viewModel.selectedProjectState.outputExpansionRequest, 2)
    }

    func testFailedImportIsRecordedInCommandHistory() async {
        let failure = CommandResult(
            executable: "ddev",
            arguments: ["import-db"],
            workingDirectory: "/Users/dave/Development/agilepixel/aqua-pura",
            exitCode: 1,
            stdout: "Import started",
            stderr: "Invalid dump",
            startedAt: Date(),
            finishedAt: Date(),
            wasCancelled: false
        )
        let service = FakeDDEVService(projects: [.sampleWordPress], importError: CommandRunnerError.nonZeroExit(failure))
        let viewModel = ProjectDashboardViewModel(ddevService: service)
        viewModel.selectedProject = .sampleWordPress

        await viewModel.importDatabase(DDEVDatabaseImportOptions(filePath: "/Users/dave/Downloads/bad.sql"))

        XCTAssertEqual(viewModel.selectedProjectState.history.map(\.result), [failure])
    }

    func testLoadSnapshotsUsesSelectedProjectFolder() async {
        let service = FakeDDEVService(
            projects: [.sampleWordPress],
            snapshotListOutput: "before-upgrade_mariadb_10.11.gz\n"
        )
        let viewModel = ProjectDashboardViewModel(ddevService: service)
        viewModel.selectedProject = .sampleWordPress

        await viewModel.loadSnapshotsForSelectedProject()

        XCTAssertEqual(service.commands, ["snapshot-list:/Users/dave/Development/agilepixel/aqua-pura"])
        XCTAssertEqual(viewModel.snapshots, [
            DDEVSnapshot(name: "before-upgrade", databaseSuffix: "mariadb 10.11")
        ])
    }

    func testCreateSnapshotRefreshesSnapshotListAndRecordsCreateOutput() async {
        let service = FakeDDEVService(
            projects: [.sampleWordPress],
            snapshotListOutput: "before-upgrade_mariadb_10.11.gz\n"
        )
        let viewModel = ProjectDashboardViewModel(ddevService: service)
        viewModel.selectedProject = .sampleWordPress

        await viewModel.createSnapshotForSelectedProject(name: "before-upgrade")

        XCTAssertEqual(service.commands, [
            "snapshot:/Users/dave/Development/agilepixel/aqua-pura:before-upgrade",
            "snapshot-list:/Users/dave/Development/agilepixel/aqua-pura"
        ])
        XCTAssertEqual(viewModel.selectedProjectState.lastResult?.arguments, ["snapshot"])
        XCTAssertEqual(viewModel.selectedProjectState.outputExpansionRequest, 1)
        XCTAssertEqual(viewModel.snapshots.count, 1)
    }

    func testRestoreSnapshotRefreshesProjectsAfterSuccessAndKeepsOutputVisible() async {
        let service = FakeDDEVService(projects: [.sampleWordPress])
        let viewModel = ProjectDashboardViewModel(ddevService: service)
        viewModel.selectedProject = .sampleWordPress

        await viewModel.restoreSnapshotForSelectedProject(named: "before-upgrade")

        XCTAssertEqual(service.commands, [
            "snapshot-restore:/Users/dave/Development/agilepixel/aqua-pura:before-upgrade",
            "describe:aqua-pura"
        ])
        XCTAssertEqual(viewModel.selectedProjectState.lastResult?.arguments, ["snapshot", "restore", "before-upgrade"])
        XCTAssertEqual(viewModel.selectedProjectState.outputExpansionRequest, 1)
        XCTAssertEqual(viewModel.selectedProjectState.history.map(\.result.arguments), [["snapshot", "restore", "before-upgrade"]])
    }

    func testRestoreLatestSnapshotUsesExplicitServiceMethodAndRefreshes() async {
        let service = FakeDDEVService(projects: [.sampleWordPress])
        let viewModel = ProjectDashboardViewModel(ddevService: service)
        viewModel.selectedProject = .sampleWordPress

        await viewModel.restoreLatestSnapshotForSelectedProject()

        XCTAssertEqual(service.commands, [
            "snapshot-restore-latest:/Users/dave/Development/agilepixel/aqua-pura",
            "describe:aqua-pura"
        ])
        XCTAssertEqual(viewModel.selectedProjectState.lastResult?.arguments, ["snapshot", "restore", "--latest"])
    }

    func testCleanupSnapshotsUsesExplicitCleanupMethodAndRefreshesSnapshotList() async {
        let service = FakeDDEVService(projects: [.sampleWordPress])
        let viewModel = ProjectDashboardViewModel(ddevService: service)
        viewModel.selectedProject = .sampleWordPress

        await viewModel.cleanupSnapshotsForSelectedProject()

        XCTAssertEqual(service.commands, [
            "snapshot-cleanup:/Users/dave/Development/agilepixel/aqua-pura",
            "snapshot-list:/Users/dave/Development/agilepixel/aqua-pura"
        ])
        XCTAssertEqual(viewModel.selectedProjectState.lastResult?.arguments, ["snapshot", "--cleanup", "-y"])
    }

    func testCleanupSingleSnapshotUsesNamedCleanupMethod() async {
        let service = FakeDDEVService(projects: [.sampleWordPress])
        let viewModel = ProjectDashboardViewModel(ddevService: service)
        viewModel.selectedProject = .sampleWordPress

        await viewModel.cleanupSnapshotForSelectedProject(named: "before-upgrade")

        XCTAssertEqual(service.commands, [
            "snapshot-cleanup-one:/Users/dave/Development/agilepixel/aqua-pura:before-upgrade",
            "snapshot-list:/Users/dave/Development/agilepixel/aqua-pura"
        ])
        XCTAssertEqual(viewModel.selectedProjectState.lastResult?.arguments, ["snapshot", "--cleanup", "--name=before-upgrade", "-y"])
    }

    func testLoadLogsUsesSelectedProjectAndStoresOutputWithoutExpandingCommandPanel() async {
        let service = FakeDDEVService(projects: [.sampleWordPress], logsOutput: "web_1  | ready\n")
        let viewModel = ProjectDashboardViewModel(ddevService: service)
        viewModel.selectedProject = .sampleWordPress

        await viewModel.loadLogsForSelectedProject(
            DDEVLogRequest(service: .db, tailCount: 250, includeTimestamps: true)
        )

        XCTAssertEqual(service.commands, [
            "logs:/Users/dave/Development/agilepixel/aqua-pura:aqua-pura:db:250:true"
        ])
        XCTAssertEqual(viewModel.projectLogsResult?.stdout, "web_1  | ready\n")
        XCTAssertEqual(viewModel.selectedProjectState.lastResult?.arguments, ["logs", "aqua-pura"])
        XCTAssertEqual(viewModel.selectedProjectState.history.map(\.result.arguments), [["logs", "aqua-pura"]])
        XCTAssertEqual(viewModel.selectedProjectState.outputExpansionRequest, 0)
    }

    func testAutoLoadLogsLoadsForRunningSelectedProject() async {
        let service = FakeDDEVService(projects: [.sampleWordPress], logsOutput: "web_1  | ready\n")
        let viewModel = ProjectDashboardViewModel(ddevService: service)
        viewModel.selectedProject = .sampleWordPress

        await viewModel.loadLogsForSelectedProjectIfRunning(DDEVLogRequest())

        XCTAssertEqual(service.commands, [
            "logs:/Users/dave/Development/agilepixel/aqua-pura:aqua-pura:web:100:false"
        ])
        XCTAssertEqual(viewModel.projectLogsResult?.stdout, "web_1  | ready\n")
    }

    func testAutoLoadLogsSkipsPausedSelectedProject() async {
        let pausedProject = DDEVProject.sampleWordPress.withStatus(.paused)
        let service = FakeDDEVService(projects: [pausedProject], logsOutput: "web_1  | ready\n")
        let viewModel = ProjectDashboardViewModel(ddevService: service)
        viewModel.selectedProject = pausedProject

        await viewModel.loadLogsForSelectedProjectIfRunning(DDEVLogRequest())

        XCTAssertEqual(service.commands, [])
        XCTAssertNil(viewModel.projectLogsResult)
    }

    func testLoadProjectConfigOmitsWebEnvironmentAndStoresParsedConfig() async {
        let service = FakeDDEVService(
            projects: [.sampleWordPress],
            configYAMLOutput: """
            php_version: "8.4"
            nodejs_version: "24"
            database:
              type: mariadb
              version: "11.8"
            webserver_type: nginx-fpm
            performance_mode: mutagen
            xdebug_enabled: false
            xhprof_mode: xhgui
            upload_dirs: [web/app/uploads]
            additional_hostnames: [www]
            """
        )
        let viewModel = ProjectDashboardViewModel(ddevService: service)
        viewModel.selectedProject = .sampleWordPress

        await viewModel.loadConfigForSelectedProject()

        XCTAssertEqual(service.commands, [
            "configyaml:/Users/dave/Development/agilepixel/aqua-pura:web_environment"
        ])
        XCTAssertEqual(viewModel.projectConfig?.phpVersion, "8.4")
        XCTAssertEqual(viewModel.projectConfig?.databaseType, .mariadb)
        XCTAssertNil(viewModel.projectConfigErrorMessage)
        XCTAssertNil(viewModel.selectedProjectState.lastResult)
    }

    func testApplyProjectConfigChangeRecordsCommandAndPromptsRestartForRunningProject() async {
        let service = FakeDDEVService(projects: [.sampleWordPress])
        let viewModel = ProjectDashboardViewModel(ddevService: service)
        viewModel.selectedProject = .sampleWordPress

        await viewModel.applyConfigChangeForSelectedProject(.nodeJSVersion("22"))

        XCTAssertEqual(service.commands, [
            "config-change:/Users/dave/Development/agilepixel/aqua-pura:--nodejs-version=22"
        ])
        XCTAssertEqual(viewModel.selectedProjectState.lastResult?.arguments, ["config", "--nodejs-version=22"])
        XCTAssertEqual(viewModel.selectedProjectState.outputExpansionRequest, 1)
        XCTAssertTrue(viewModel.projectConfigRestartRecommended)
    }

    func testApplyProjectConfigChangeDoesNotPromptRestartForStoppedProject() async {
        let stoppedProject = DDEVProject.sampleWordPress.withStatus(.stopped)
        let service = FakeDDEVService(projects: [stoppedProject])
        let viewModel = ProjectDashboardViewModel(ddevService: service)
        viewModel.selectedProject = stoppedProject

        await viewModel.applyConfigChangeForSelectedProject(.xdebugEnabled(false))

        XCTAssertEqual(service.commands, [
            "config-change:/Users/dave/Development/agilepixel/aqua-pura:--xdebug-enabled=false"
        ])
        XCTAssertFalse(viewModel.projectConfigRestartRecommended)
    }

    func testLoadInstalledAddOnsUsesSelectedProjectNameAndParsesOutput() async {
        let service = FakeDDEVService(
            projects: [.sampleWordPress],
            addonListOutput: """
            {"raw":[{"title":"ddev/ddev-redis","description":"Redis cache","tag_name":"v2.2.0","dependencies":[],"type":"official"}]}
            """
        )
        let viewModel = ProjectDashboardViewModel(ddevService: service)
        viewModel.selectedProject = .sampleWordPress

        await viewModel.loadInstalledAddOnsForSelectedProject()

        XCTAssertEqual(service.commands, [
            "addon-list:/Users/dave/Development/agilepixel/aqua-pura:aqua-pura"
        ])
        XCTAssertEqual(viewModel.installedAddOns.map(\.repository), ["ddev/ddev-redis"])
        XCTAssertNil(viewModel.addonErrorMessage)
    }

    func testSearchAddOnsUsesSelectedProjectFolderAndParsesResults() async {
        let service = FakeDDEVService(
            projects: [.sampleWordPress],
            addonSearchOutput: """
            {"raw":[{"title":"ddev/ddev-redis-insight","description":"Redis Insight","tag_name":"v1.0.2","dependencies":["ddev/ddev-redis"],"type":"official"}]}
            """
        )
        let viewModel = ProjectDashboardViewModel(ddevService: service)
        viewModel.selectedProject = .sampleWordPress

        await viewModel.searchAddOnsForSelectedProject(query: "redis insight")

        XCTAssertEqual(service.commands, [
            "addon-search:/Users/dave/Development/agilepixel/aqua-pura:redis insight"
        ])
        XCTAssertEqual(viewModel.addonSearchResults.map(\.repository), ["ddev/ddev-redis-insight"])
        XCTAssertEqual(viewModel.addonSearchResults.first?.dependencies, ["ddev/ddev-redis"])
    }

    func testInstallAndRemoveAddOnsRecordOutputAndPromptRestart() async {
        let service = FakeDDEVService(projects: [.sampleWordPress])
        let viewModel = ProjectDashboardViewModel(ddevService: service)
        viewModel.selectedProject = .sampleWordPress

        await viewModel.installAddOnForSelectedProject("ddev/ddev-redis")
        await viewModel.removeAddOnForSelectedProject(named: "ddev-redis")

        XCTAssertEqual(service.commands, [
            "addon-get:/Users/dave/Development/agilepixel/aqua-pura:aqua-pura:ddev/ddev-redis",
            "addon-list:/Users/dave/Development/agilepixel/aqua-pura:aqua-pura",
            "addon-remove:/Users/dave/Development/agilepixel/aqua-pura:aqua-pura:ddev-redis",
            "addon-list:/Users/dave/Development/agilepixel/aqua-pura:aqua-pura"
        ])
        XCTAssertEqual(viewModel.selectedProjectState.lastResult?.arguments, ["add-on", "remove", "ddev-redis"])
        XCTAssertTrue(viewModel.addOnRestartRecommended)
        XCTAssertEqual(viewModel.selectedProjectState.outputExpansionRequest, 2)
    }

    func testAddOnCommandFailuresSurfacePanelError() async {
        let now = Date()
        let failure = CommandResult(
            executable: "ddev",
            arguments: ["add-on", "search", "redis", "--json-output"],
            workingDirectory: "/Users/dave/Development/agilepixel/aqua-pura",
            exitCode: 1,
            stdout: "",
            stderr: "GitHub API rate limit exceeded",
            startedAt: now,
            finishedAt: now,
            wasCancelled: false
        )
        let service = FakeDDEVService(
            projects: [.sampleWordPress],
            addonError: CommandRunnerError.nonZeroExit(failure)
        )
        let viewModel = ProjectDashboardViewModel(ddevService: service)
        viewModel.selectedProject = .sampleWordPress

        await viewModel.searchAddOnsForSelectedProject(query: "redis")

        XCTAssertEqual(viewModel.addonErrorMessage, "Command failed with exit code 1.")
        XCTAssertEqual(viewModel.selectedProjectState.lastResult?.stderr, "GitHub API rate limit exceeded")
    }

    func testGlobalDiagnosticsRunWithoutSelectedProject() async {
        let service = FakeDDEVService(projects: [])
        let viewModel = ProjectDashboardViewModel(ddevService: service)

        await viewModel.runGlobalDiagnostics()

        XCTAssertEqual(service.commands, [
            "version",
            "diagnose:"
        ])
        XCTAssertEqual(viewModel.diagnosticReport.entries.map(\.check), [.ddevVersion, .globalDiagnose])
        XCTAssertTrue(viewModel.copyableDiagnosticOutput.contains("DDEV Version"))
        XCTAssertNil(viewModel.diagnosticsErrorMessage)
    }

    func testProjectDiagnosticsIncludeProjectAndMutagenChecks() async {
        let service = FakeDDEVService(projects: [.sampleWordPress])
        let viewModel = ProjectDashboardViewModel(ddevService: service)
        viewModel.selectedProject = .sampleWordPress

        await viewModel.runProjectDiagnosticsForSelectedProject()

        XCTAssertEqual(service.commands, [
            "diagnose:/Users/dave/Development/agilepixel/aqua-pura",
            "check-custom-config:/Users/dave/Development/agilepixel/aqua-pura",
            "check-db-match:/Users/dave/Development/agilepixel/aqua-pura",
            "mutagen:/Users/dave/Development/agilepixel/aqua-pura:status"
        ])
        XCTAssertEqual(
            viewModel.diagnosticReport.entries.map(\.check),
            [.projectDiagnose, .customConfig, .dbMatch, .mutagenStatus]
        )
    }

    func testMutagenResetRecordsDiagnosticOutput() async {
        let service = FakeDDEVService(projects: [.sampleWordPress])
        let viewModel = ProjectDashboardViewModel(ddevService: service)
        viewModel.selectedProject = .sampleWordPress

        await viewModel.runMutagenDiagnosticForSelectedProject(.reset)

        XCTAssertEqual(service.commands, [
            "mutagen:/Users/dave/Development/agilepixel/aqua-pura:reset"
        ])
        XCTAssertEqual(viewModel.diagnosticReport.entries.map(\.check), [.mutagenReset])
        XCTAssertEqual(viewModel.diagnosticReport.entries.first?.result.arguments, ["mutagen", "reset"])
    }

    func testEnableXHGuiRunsInSelectedProjectAndRefreshes() async {
        let service = FakeDDEVService(projects: [.sampleWordPress])
        let viewModel = ProjectDashboardViewModel(ddevService: service)
        viewModel.selectedProject = .sampleWordPress

        await viewModel.enableXHGuiForSelectedProject()

        XCTAssertEqual(service.commands, [
            "xhgui:/Users/dave/Development/agilepixel/aqua-pura:on",
            "describe:aqua-pura"
        ])
        XCTAssertEqual(viewModel.selectedProjectState.lastResult?.arguments, ["xhgui", "on"])
    }

    // MARK: - M10: error presentation + snapshot error surface

    func testPresentableMessagePrefersStderrThenExitCodeAndNeverDumpsStruct() {
        let withStderr = CommandResult(executable: "ddev", arguments: ["start"], workingDirectory: nil,
                                       exitCode: 7, stdout: "", stderr: "daemon unreachable",
                                       startedAt: Date(), finishedAt: Date(), wasCancelled: false)
        XCTAssertEqual(CommandRunnerError.nonZeroExit(withStderr).presentableMessage, "daemon unreachable")
        XCTAssertFalse(CommandRunnerError.nonZeroExit(withStderr).presentableMessage.contains("CommandResult"),
                       "Never dumps the internal result struct into a user-facing message")

        let noStderr = CommandResult(executable: "ddev", arguments: ["start"], workingDirectory: nil,
                                     exitCode: 3, stdout: "", stderr: "  ",
                                     startedAt: Date(), finishedAt: Date(), wasCancelled: false)
        XCTAssertEqual(CommandRunnerError.nonZeroExit(noStderr).presentableMessage, "Command failed with exit code 3.")
        XCTAssertEqual(CommandRunnerError.timedOut(noStderr).presentableMessage, "Command timed out.")
    }

    func testSnapshotRefreshFailureRoutesToSnapshotSurfaceNotGlobalBanner() async {
        let failure = CommandResult(executable: "ddev", arguments: ["snapshot", "--list"], workingDirectory: nil,
                                    exitCode: 1, stdout: "", stderr: "snapshot dir unreadable",
                                    startedAt: Date(), finishedAt: Date(), wasCancelled: false)
        let service = FakeDDEVService(projects: [.sampleWordPress],
                                      snapshotListError: CommandRunnerError.nonZeroExit(failure))
        let viewModel = ProjectDashboardViewModel(ddevService: service)
        viewModel.selectedProject = .sampleWordPress

        await viewModel.createSnapshotForSelectedProject(name: "snap")

        XCTAssertEqual(viewModel.snapshotErrorMessage, "snapshot dir unreadable",
                       "Snapshot-list refresh failure surfaces on the snapshot-scoped property")
        XCTAssertNil(viewModel.globalErrorMessage, "…not the list-level global banner")
    }

    // MARK: - S1: trash path is asserted under the home directory

    func testTrashRefusesFolderOutsideHomeDirectory() {
        let outsideProject = DDEVProject(
            name: "evil", appRoot: "/opt/ddevui-evil-target", shortRoot: "/opt/ddevui-evil-target",
            status: .stopped, statusDescription: "stopped", projectType: .php, docroot: "",
            primaryURL: nil, httpURL: nil, httpsURL: nil, mailpitURL: nil, mailpitHTTPSURL: nil,
            xhguiURL: nil, xhguiHTTPSURL: nil, xhguiStatus: nil,
            mutagenEnabled: false, mutagenStatus: nil, phpVersion: nil
        )
        let viewModel = ProjectDashboardViewModel(ddevService: FakeDDEVService(projects: [outsideProject]))
        viewModel.projects = [outsideProject]
        viewModel.selectedProject = outsideProject

        viewModel.moveSelectedProjectFolderToTrash()

        XCTAssertTrue(viewModel.globalErrorMessage?.contains("outside your home directory") ?? false,
                      "A cache-supplied appRoot outside the home directory is refused before trashing")
        XCTAssertTrue(viewModel.projects.contains(where: { $0.id == outsideProject.id }),
                      "The project is not removed when the trash is refused")
    }

    // MARK: - M2: commandStates pruning

    func testApplyProjectsPrunesStaleCommandStates() async {
        let service = FakeDDEVService(projects: [.sampleWordPress])
        let viewModel = ProjectDashboardViewModel(ddevService: service)
        // A leftover entry for a project that is no longer in the list.
        viewModel.commandStates["ghost-project"] = ProjectCommandState()
        viewModel.commandStates["aqua-pura"] = ProjectCommandState()

        await viewModel.refresh()

        XCTAssertNil(viewModel.commandStates["ghost-project"], "Entry for a vanished project is pruned")
        XCTAssertNotNil(viewModel.commandStates["aqua-pura"], "Entry for a live project is retained")
    }

    func testApplyProjectsKeepsBusyEntriesEvenIfNotInList() async {
        let service = FakeDDEVService(projects: [.sampleWordPress])
        let viewModel = ProjectDashboardViewModel(ddevService: service)
        var busy = ProjectCommandState()
        busy.activity = .running
        viewModel.commandStates["ghost-busy"] = busy

        await viewModel.refresh()

        XCTAssertNotNil(viewModel.commandStates["ghost-busy"],
                        "A busy entry is retained so an in-flight command briefly off the list isn't lost")
    }
}

private final class FakeDDEVService: DDEVServicing, @unchecked Sendable {
    private let lock = NSLock()
    private let loadedProjects: [DDEVProject]
    private let phpVersions: [String: String]
    private let xhguiStatuses: [String: DDEVXHGuiStatus]
    private let describeDetails: [String: DDEVProjectDetails]
    private let dbMatchResult: Result<CommandResult, Error>?
    private let listError: Error?
    private let importError: Error?
    private let snapshotListOutput: String
    private let snapshotListError: Error?
    private let logsOutput: String
    private let configYAMLOutput: String
    private let addonListOutput: String
    private let addonSearchOutput: String
    private let addonError: Error?
    private let diagnosticError: Error?
    private var recordedCommands: [String] = []

    var commands: [String] {
        lock.withLock { recordedCommands }
    }

    init(
        projects: [DDEVProject],
        phpVersions: [String: String] = [:],
        xhguiStatuses: [String: DDEVXHGuiStatus] = [:],
        describeDetails: [String: DDEVProjectDetails] = [:],
        dbMatchResult: Result<CommandResult, Error>? = nil,
        listError: Error? = nil,
        importError: Error? = nil,
        snapshotListOutput: String = "",
        snapshotListError: Error? = nil,
        logsOutput: String = "",
        configYAMLOutput: String = "",
        addonListOutput: String = "",
        addonSearchOutput: String = "",
        addonError: Error? = nil,
        diagnosticError: Error? = nil
    ) {
        self.loadedProjects = projects
        self.phpVersions = phpVersions
        self.xhguiStatuses = xhguiStatuses
        self.describeDetails = describeDetails
        self.dbMatchResult = dbMatchResult
        self.listError = listError
        self.importError = importError
        self.snapshotListOutput = snapshotListOutput
        self.snapshotListError = snapshotListError
        self.logsOutput = logsOutput
        self.configYAMLOutput = configYAMLOutput
        self.addonListOutput = addonListOutput
        self.addonSearchOutput = addonSearchOutput
        self.addonError = addonError
        self.diagnosticError = diagnosticError
    }

    func listProjects() async throws -> [DDEVProject] {
        record("list")
        if let listError {
            throw listError
        }
        return loadedProjects
    }

    func describe(projectName: String) async throws -> DDEVProjectDetails {
        record("describe:\(projectName)")
        if let details = describeDetails[projectName] {
            return details
        }
        return DDEVProjectDetails(phpVersion: phpVersions[projectName], xhguiStatus: xhguiStatuses[projectName])
    }

    func start(projectName: String) async throws -> CommandResult {
        record("start:\(projectName)")
        return commandResult(arguments: ["start", projectName])
    }

    func stop(projectName: String) async throws -> CommandResult {
        record("stop:\(projectName)")
        return commandResult(arguments: ["stop", projectName])
    }

    func restart(projectName: String) async throws -> CommandResult {
        record("restart:\(projectName)")
        return commandResult(arguments: ["restart", projectName])
    }

    func unlink(projectName: String) async throws -> CommandResult {
        record("unlink:\(projectName)")
        return commandResult(arguments: ["stop", "--unlist", projectName])
    }

    func deleteDDEVData(projectName: String) async throws -> CommandResult {
        record("delete:\(projectName)")
        return commandResult(arguments: ["delete", projectName])
    }

    func startProject(in appRoot: String) async throws -> CommandResult {
        record("start-folder:\(appRoot)")
        return commandResult(arguments: ["start"], workingDirectory: appRoot)
    }

    func configureProject(in appRoot: String, name: String, type: DDEVProjectType, docroot: String) async throws -> CommandResult {
        record("config:\(appRoot):\(name):\(type.rawValue):\(docroot)")
        return commandResult(
            arguments: ["config", "--project-name=\(name)", "--project-type=\(type.rawValue)", "--docroot=\(docroot)"],
            workingDirectory: appRoot
        )
    }

    func launchDatabaseTool(_ tool: DDEVDatabaseTool, in appRoot: String) async throws -> CommandResult {
        record("db:\(tool.rawValue):\(appRoot)")
        return commandResult(arguments: [tool.rawValue], workingDirectory: appRoot)
    }

    func updateWordPressCore(in appRoot: String) async throws -> CommandResult {
        record("wp-core:\(appRoot)")
        return commandResult(arguments: ["wp", "core", "update"], workingDirectory: appRoot)
    }

    func updateWordPressPlugins(in appRoot: String) async throws -> CommandResult {
        record("wp-plugins:\(appRoot)")
        return commandResult(arguments: ["wp", "plugin", "update", "--all"], workingDirectory: appRoot)
    }

    func updateWordPressThemes(in appRoot: String) async throws -> CommandResult {
        record("wp-themes:\(appRoot)")
        return commandResult(arguments: ["wp", "theme", "update", "--all"], workingDirectory: appRoot)
    }

    func setPHPVersion(_ version: String, in appRoot: String) async throws -> CommandResult {
        record("php:\(version):\(appRoot)")
        return commandResult(arguments: ["config", "--php-version=\(version)"], workingDirectory: appRoot)
    }

    func importDatabase(_ options: DDEVDatabaseImportOptions, in appRoot: String) async throws -> CommandResult {
        record("import:\(appRoot):\(options.filePath):\(options.database):\(options.extractPath ?? ""):\(options.dropExistingDatabase)")
        if let importError {
            throw importError
        }
        return commandResult(arguments: ["import-db"], workingDirectory: appRoot)
    }

    func exportDatabase(_ options: DDEVDatabaseExportOptions, in appRoot: String) async throws -> CommandResult {
        record("export:\(appRoot):\(options.outputPath):\(options.database):\(options.compression.rawValue)")
        return commandResult(arguments: ["export-db"], workingDirectory: appRoot)
    }


    func createSnapshot(name: String?, in appRoot: String) async throws -> CommandResult {
        record("snapshot:\(appRoot):\(name ?? "")")
        return commandResult(arguments: ["snapshot"], workingDirectory: appRoot)
    }

    func listSnapshots(in appRoot: String) async throws -> CommandResult {
        record("snapshot-list:\(appRoot)")
        if let snapshotListError { throw snapshotListError }
        return commandResult(arguments: ["snapshot", "--list"], workingDirectory: appRoot, stdout: snapshotListOutput)
    }

    func restoreSnapshot(named snapshotName: String, in appRoot: String) async throws -> CommandResult {
        record("snapshot-restore:\(appRoot):\(snapshotName)")
        return commandResult(arguments: ["snapshot", "restore", snapshotName], workingDirectory: appRoot)
    }

    func restoreLatestSnapshot(in appRoot: String) async throws -> CommandResult {
        record("snapshot-restore-latest:\(appRoot)")
        return commandResult(arguments: ["snapshot", "restore", "--latest"], workingDirectory: appRoot)
    }

    func cleanupSnapshots(in appRoot: String) async throws -> CommandResult {
        record("snapshot-cleanup:\(appRoot)")
        return commandResult(arguments: ["snapshot", "--cleanup", "-y"], workingDirectory: appRoot)
    }

    func cleanupSnapshot(named snapshotName: String, in appRoot: String) async throws -> CommandResult {
        record("snapshot-cleanup-one:\(appRoot):\(snapshotName)")
        return commandResult(arguments: ["snapshot", "--cleanup", "--name=\(snapshotName)", "-y"], workingDirectory: appRoot)
    }

    func logs(projectName: String, service: String, tail: Int, includeTimestamps: Bool, in appRoot: String) async throws -> CommandResult {
        record("logs:\(appRoot):\(projectName):\(service):\(tail):\(includeTimestamps)")
        return commandResult(arguments: ["logs", projectName], workingDirectory: appRoot, stdout: logsOutput)
    }

    func listInstalledAddOns(projectName: String, in appRoot: String) async throws -> CommandResult {
        record("addon-list:\(appRoot):\(projectName)")
        if let addonError {
            throw addonError
        }
        return commandResult(arguments: ["add-on", "list", "--installed"], workingDirectory: appRoot, stdout: addonListOutput)
    }

    func searchAddOns(query: String, in appRoot: String) async throws -> CommandResult {
        record("addon-search:\(appRoot):\(query)")
        if let addonError {
            throw addonError
        }
        return commandResult(arguments: ["add-on", "search", query], workingDirectory: appRoot, stdout: addonSearchOutput)
    }

    func getAddOn(_ repository: String, projectName: String, in appRoot: String) async throws -> CommandResult {
        record("addon-get:\(appRoot):\(projectName):\(repository)")
        if let addonError {
            throw addonError
        }
        return commandResult(arguments: ["add-on", "get", repository], workingDirectory: appRoot)
    }

    func removeAddOn(named name: String, projectName: String, in appRoot: String) async throws -> CommandResult {
        record("addon-remove:\(appRoot):\(projectName):\(name)")
        if let addonError {
            throw addonError
        }
        return commandResult(arguments: ["add-on", "remove", name], workingDirectory: appRoot)
    }

    func applyConfigChange(_ change: DDEVConfigChange, in appRoot: String) async throws -> CommandResult {
        record("config-change:\(appRoot):\(change.ddevFlags.joined(separator: ","))")
        return commandResult(arguments: ["config"] + change.ddevFlags, workingDirectory: appRoot)
    }

    func runProjectCommand(arguments: [String], in appRoot: String) async throws -> CommandResult {
        record("project-command:\(appRoot):\(arguments.joined(separator: ","))")
        return commandResult(arguments: arguments, workingDirectory: appRoot)
    }

    func version() async throws -> CommandResult {
        record("version")
        if let diagnosticError {
            throw diagnosticError
        }
        return commandResult(arguments: ["version"], stdout: "ddev version v1.24.8\n")
    }

    func utilityDiagnose(in appRoot: String?) async throws -> CommandResult {
        record("diagnose:\(appRoot ?? "")")
        if let diagnosticError {
            throw diagnosticError
        }
        return commandResult(arguments: ["utility", "diagnose"], workingDirectory: appRoot)
    }

    func utilityConfigYAML(omitKeys: [String], in appRoot: String) async throws -> CommandResult {
        record("configyaml:\(appRoot):\(omitKeys.joined(separator: ","))")
        return commandResult(arguments: ["utility", "configyaml"], workingDirectory: appRoot, stdout: configYAMLOutput)
    }

    func utilityCheckCustomConfig(in appRoot: String) async throws -> CommandResult {
        record("check-custom-config:\(appRoot)")
        if let diagnosticError {
            throw diagnosticError
        }
        return commandResult(arguments: ["utility", "check-custom-config"], workingDirectory: appRoot)
    }

    func utilityCheckDBMatch(in appRoot: String) async throws -> CommandResult {
        record("check-db-match:\(appRoot)")
        if let dbMatchResult {
            return try dbMatchResult.get()
        }
        if let diagnosticError {
            throw diagnosticError
        }
        return commandResult(arguments: ["utility", "check-db-match"], workingDirectory: appRoot)
    }

    func mutagen(_ command: DDEVMutagenCommand, in appRoot: String) async throws -> CommandResult {
        record("mutagen:\(appRoot):\(command.rawValue)")
        if let diagnosticError {
            throw diagnosticError
        }
        return commandResult(arguments: ["mutagen", command.rawValue], workingDirectory: appRoot)
    }

    func xhgui(_ command: DDEVXHGuiCommand, in appRoot: String) async throws -> CommandResult {
        record("xhgui:\(appRoot):\(command.rawValue)")
        return commandResult(arguments: ["xhgui", command.rawValue], workingDirectory: appRoot)
    }

    func xdebug(_ command: DDEVXdebugCommand, in appRoot: String) async throws -> CommandResult {
        record("xdebug:\(appRoot):\(command.rawValue)")
        return commandResult(arguments: ["xdebug", command.rawValue], workingDirectory: appRoot)
    }

    private func record(_ command: String) {
        lock.withLock {
            recordedCommands.append(command)
        }
    }

    private func commandResult(arguments: [String], workingDirectory: String? = nil, stdout: String = "") -> CommandResult {
        let now = Date()
        return CommandResult(
            executable: "ddev",
            arguments: arguments,
            workingDirectory: workingDirectory,
            exitCode: 0,
            stdout: stdout,
            stderr: "",
            startedAt: now,
            finishedAt: now,
            wasCancelled: false
        )
    }
}

private enum TestError: Error {
    case expected
}

private final class InMemoryAppPreferencesStore: AppPreferencesStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var storedPreferences: AppPreferences

    var preferences: AppPreferences {
        lock.withLock { storedPreferences }
    }

    init(preferences: AppPreferences = AppPreferences()) {
        self.storedPreferences = preferences
    }

    func loadPreferences() -> AppPreferences {
        preferences
    }

    func saveDefaultEditor(_ editor: EditorChoice?) {
        lock.withLock {
            storedPreferences.defaultEditor = editor
        }
    }

    func saveDefaultDatabaseTool(_ databaseTool: DDEVDatabaseTool?) {
        lock.withLock {
            storedPreferences.defaultDatabaseTool = databaseTool
        }
    }
}

extension DDEVProject {
    static let sampleWordPress = DDEVProject(
        name: "aqua-pura",
        appRoot: "/Users/dave/Development/agilepixel/aqua-pura",
        shortRoot: "~/Development/agilepixel/aqua-pura",
        status: .running,
        statusDescription: "running",
        projectType: .wordpress,
        docroot: "",
        primaryURL: URL(string: "https://aqua-pura.ddev.site"),
        httpURL: nil,
        httpsURL: nil,
        mailpitURL: nil,
        mailpitHTTPSURL: nil,
        xhguiURL: nil,
        xhguiHTTPSURL: nil,
        xhguiStatus: nil,
        mutagenEnabled: true,
        mutagenStatus: "ok",
        phpVersion: nil
    )

    static let sampleLaravel = DDEVProject(
        name: "agilebugs",
        appRoot: "/Users/dave/Development/agilepixel/agilebugs",
        shortRoot: "~/Development/agilepixel/agilebugs",
        status: .paused,
        statusDescription: "paused",
        projectType: .laravel,
        docroot: "public",
        primaryURL: URL(string: "https://agilebugs.ddev.site"),
        httpURL: nil,
        httpsURL: nil,
        mailpitURL: nil,
        mailpitHTTPSURL: nil,
        xhguiURL: nil,
        xhguiHTTPSURL: nil,
        xhguiStatus: nil,
        mutagenEnabled: true,
        mutagenStatus: "ok",
        phpVersion: nil
    )

    func withStatus(_ status: DDEVProjectStatus) -> DDEVProject {
        DDEVProject(
            name: name,
            appRoot: appRoot,
            shortRoot: shortRoot,
            status: status,
            statusDescription: status.rawValue,
            projectType: projectType,
            docroot: docroot,
            primaryURL: primaryURL,
            httpURL: httpURL,
            httpsURL: httpsURL,
            mailpitURL: mailpitURL,
            mailpitHTTPSURL: mailpitHTTPSURL,
            xhguiURL: xhguiURL,
            xhguiHTTPSURL: xhguiHTTPSURL,
            xhguiStatus: xhguiStatus,
            mutagenEnabled: mutagenEnabled,
            mutagenStatus: mutagenStatus,
            phpVersion: phpVersion
        )
    }

    func withXHGuiURLs(xhguiURL: URL?, xhguiHTTPSURL: URL?) -> DDEVProject {
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
            xhguiStatus: xhguiStatus,
            mutagenEnabled: mutagenEnabled,
            mutagenStatus: mutagenStatus,
            phpVersion: phpVersion
        )
    }
}

extension CommandResult {
    /// Test helper mirroring `CommandResult.success`, for building a failed (non-zero exit) result.
    static func failure(stdout: String = "", stderr: String = "", exitCode: Int32 = 1) -> CommandResult {
        let now = Date()
        return CommandResult(
            executable: "ddev",
            arguments: [],
            workingDirectory: nil,
            exitCode: exitCode,
            stdout: stdout,
            stderr: stderr,
            startedAt: now,
            finishedAt: now,
            wasCancelled: false
        )
    }
}
