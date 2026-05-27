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
        XCTAssertNil(viewModel.lastErrorMessage)
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
    }

    func testRefreshAddsPHPVersionsFromProjectDetails() async {
        let service = FakeDDEVService(projects: [.sampleWordPress], phpVersions: ["aqua-pura": "8.4"])
        let viewModel = ProjectDashboardViewModel(ddevService: service)

        await viewModel.refresh()

        XCTAssertEqual(viewModel.projects.first?.phpVersion, "8.4")
        XCTAssertEqual(service.commands, ["list", "describe:aqua-pura"])
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

    func testRefreshFailureKeepsCachedProjectsVisible() async {
        let service = FakeDDEVService(projects: [], listError: TestError.expected)
        let cache = InMemoryProjectCacheStore(projects: [.sampleWordPress])
        let viewModel = ProjectDashboardViewModel(ddevService: service, projectCache: cache)

        await viewModel.loadCachedProjectsThenRefresh()

        XCTAssertEqual(viewModel.projects, [.sampleWordPress])
        XCTAssertEqual(viewModel.selectedProject, .sampleWordPress)
        XCTAssertNotNil(viewModel.lastErrorMessage)
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

        XCTAssertEqual(service.commands, ["start:aqua-pura", "list", "describe:aqua-pura"])
        XCTAssertEqual(viewModel.lastCommandResult?.succeeded, true)
    }

    func testDatabaseToolLaunchUsesSelectedProjectFolder() async {
        let service = FakeDDEVService(projects: [.sampleWordPress])
        let viewModel = ProjectDashboardViewModel(ddevService: service)
        viewModel.selectedProject = .sampleWordPress

        await viewModel.launchDatabaseTool(.tablePlus)

        XCTAssertEqual(service.commands, [
            "db:tableplus:/Users/dave/Development/agilepixel/aqua-pura",
            "list",
            "describe:aqua-pura"
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
            "db:tableplus:/Users/dave/Development/agilepixel/aqua-pura",
            "list",
            "describe:aqua-pura"
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
            "list",
            "describe:aqua-pura",
            "wp-plugins:/Users/dave/Development/agilepixel/aqua-pura",
            "list",
            "describe:aqua-pura",
            "wp-themes:/Users/dave/Development/agilepixel/aqua-pura",
            "list",
            "describe:aqua-pura"
        ])
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
            "list",
            "describe:aqua-pura"
        ])
    }

    func testSetPHPVersionRecordsEachMutatingCommandInHistory() async {
        let service = FakeDDEVService(projects: [.sampleWordPress], phpVersions: ["aqua-pura": "8.3"])
        let viewModel = ProjectDashboardViewModel(ddevService: service)
        viewModel.selectedProject = .sampleWordPress

        await viewModel.setPHPVersionForSelectedProject("8.3")

        XCTAssertEqual(viewModel.commandHistory.map(\.result.arguments), [
            ["config", "--php-version=8.3"],
            ["restart", "aqua-pura"]
        ])
        XCTAssertEqual(viewModel.lastCommandResult?.arguments, ["restart", "aqua-pura"])
    }

    func testSetPHPVersionDoesNotRestartPausedProject() async {
        let service = FakeDDEVService(projects: [.sampleLaravel], phpVersions: ["agilebugs": "8.2"])
        let viewModel = ProjectDashboardViewModel(ddevService: service)
        viewModel.selectedProject = .sampleLaravel

        await viewModel.setPHPVersionForSelectedProject("8.2")

        XCTAssertEqual(service.commands, [
            "php:8.2:/Users/dave/Development/agilepixel/agilebugs",
            "list",
            "describe:agilebugs"
        ])
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
            "list",
            "describe:aqua-pura"
        ])
        XCTAssertEqual(viewModel.lastCommandResult?.succeeded, true)
        XCTAssertEqual(viewModel.commandOutputExpansionRequest, 1)
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
        XCTAssertEqual(viewModel.lastCommandResult?.succeeded, true)
        XCTAssertEqual(viewModel.commandOutputExpansionRequest, 1)
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

        XCTAssertEqual(viewModel.lastCommandResult, failure)
        XCTAssertEqual(viewModel.lastErrorMessage, "Command failed with exit code 1.")
        XCTAssertEqual(viewModel.commandOutputExpansionRequest, 1)
    }

    func testEachCompletedCommandRequestsOutputExpansion() async {
        let service = FakeDDEVService(projects: [.sampleWordPress])
        let viewModel = ProjectDashboardViewModel(ddevService: service)
        viewModel.selectedProject = .sampleWordPress

        await viewModel.exportDatabase(DDEVDatabaseExportOptions(outputPath: "/Users/dave/Backups/first.sql.gz"))
        await viewModel.exportDatabase(DDEVDatabaseExportOptions(outputPath: "/Users/dave/Backups/second.sql.gz"))

        XCTAssertEqual(viewModel.commandOutputExpansionRequest, 2)
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

        XCTAssertEqual(viewModel.commandHistory.map(\.result), [failure])
    }
}

private final class FakeDDEVService: DDEVServicing, @unchecked Sendable {
    private let lock = NSLock()
    private let loadedProjects: [DDEVProject]
    private let phpVersions: [String: String]
    private let listError: Error?
    private let importError: Error?
    private var recordedCommands: [String] = []

    var commands: [String] {
        lock.withLock { recordedCommands }
    }

    init(
        projects: [DDEVProject],
        phpVersions: [String: String] = [:],
        listError: Error? = nil,
        importError: Error? = nil
    ) {
        self.loadedProjects = projects
        self.phpVersions = phpVersions
        self.listError = listError
        self.importError = importError
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
        return DDEVProjectDetails(phpVersion: phpVersions[projectName])
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

    func importFiles(_ options: DDEVFileImportOptions, in appRoot: String) async throws -> CommandResult {
        record("import-files:\(appRoot):\(options.sourcePath)")
        return commandResult(arguments: ["import-files"], workingDirectory: appRoot)
    }

    func createSnapshot(name: String?, in appRoot: String) async throws -> CommandResult {
        record("snapshot:\(appRoot):\(name ?? "")")
        return commandResult(arguments: ["snapshot"], workingDirectory: appRoot)
    }

    func listSnapshots(in appRoot: String) async throws -> CommandResult {
        record("snapshot-list:\(appRoot)")
        return commandResult(arguments: ["snapshot", "--list"], workingDirectory: appRoot)
    }

    func restoreSnapshot(named snapshotName: String, in appRoot: String) async throws -> CommandResult {
        record("snapshot-restore:\(appRoot):\(snapshotName)")
        return commandResult(arguments: ["snapshot", "restore", snapshotName], workingDirectory: appRoot)
    }

    func logs(projectName: String, service: String, tail: Int, includeTimestamps: Bool, in appRoot: String) async throws -> CommandResult {
        record("logs:\(appRoot):\(projectName):\(service):\(tail):\(includeTimestamps)")
        return commandResult(arguments: ["logs", projectName], workingDirectory: appRoot)
    }

    func listInstalledAddOns(in appRoot: String) async throws -> CommandResult {
        record("addon-list:\(appRoot)")
        return commandResult(arguments: ["add-on", "list", "--installed"], workingDirectory: appRoot)
    }

    func searchAddOns(query: String, in appRoot: String) async throws -> CommandResult {
        record("addon-search:\(appRoot):\(query)")
        return commandResult(arguments: ["add-on", "search", query], workingDirectory: appRoot)
    }

    func getAddOn(_ repository: String, in appRoot: String) async throws -> CommandResult {
        record("addon-get:\(appRoot):\(repository)")
        return commandResult(arguments: ["add-on", "get", repository], workingDirectory: appRoot)
    }

    func removeAddOn(named name: String, in appRoot: String) async throws -> CommandResult {
        record("addon-remove:\(appRoot):\(name)")
        return commandResult(arguments: ["add-on", "remove", name], workingDirectory: appRoot)
    }

    func config(flags: [String], in appRoot: String) async throws -> CommandResult {
        record("config-flags:\(appRoot):\(flags.joined(separator: ","))")
        return commandResult(arguments: ["config"] + flags, workingDirectory: appRoot)
    }

    func utilityDiagnose(in appRoot: String) async throws -> CommandResult {
        record("diagnose:\(appRoot)")
        return commandResult(arguments: ["utility", "diagnose"], workingDirectory: appRoot)
    }

    func utilityConfigYAML(omitKeys: [String], in appRoot: String) async throws -> CommandResult {
        record("configyaml:\(appRoot):\(omitKeys.joined(separator: ","))")
        return commandResult(arguments: ["utility", "configyaml"], workingDirectory: appRoot)
    }

    func mutagen(_ command: DDEVMutagenCommand, in appRoot: String) async throws -> CommandResult {
        record("mutagen:\(appRoot):\(command.rawValue)")
        return commandResult(arguments: ["mutagen", command.rawValue], workingDirectory: appRoot)
    }

    func xhgui(_ command: DDEVXHGuiCommand, in appRoot: String) async throws -> CommandResult {
        record("xhgui:\(appRoot):\(command.rawValue)")
        return commandResult(arguments: ["xhgui", command.rawValue], workingDirectory: appRoot)
    }

    private func record(_ command: String) {
        lock.withLock {
            recordedCommands.append(command)
        }
    }

    private func commandResult(arguments: [String], workingDirectory: String? = nil) -> CommandResult {
        let now = Date()
        return CommandResult(
            executable: "ddev",
            arguments: arguments,
            workingDirectory: workingDirectory,
            exitCode: 0,
            stdout: "",
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
        mutagenEnabled: true,
        mutagenStatus: "ok",
        phpVersion: nil
    )
}
