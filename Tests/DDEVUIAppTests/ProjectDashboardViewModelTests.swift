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

        XCTAssertEqual(service.commands, ["start:aqua-pura", "list"])
        XCTAssertEqual(viewModel.lastCommandResult?.succeeded, true)
    }

    func testDatabaseToolLaunchUsesSelectedProjectFolder() async {
        let service = FakeDDEVService(projects: [.sampleWordPress])
        let viewModel = ProjectDashboardViewModel(ddevService: service)
        viewModel.selectedProject = .sampleWordPress

        await viewModel.launchDatabaseTool(.tablePlus)

        XCTAssertEqual(service.commands, ["db:tableplus:/Users/dave/Development/agilepixel/aqua-pura", "list"])
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
            "wp-plugins:/Users/dave/Development/agilepixel/aqua-pura",
            "list",
            "wp-themes:/Users/dave/Development/agilepixel/aqua-pura",
            "list"
        ])
    }

    func testDeleteDDEVDataRefreshesAfterCommand() async {
        let service = FakeDDEVService(projects: [.sampleWordPress])
        let viewModel = ProjectDashboardViewModel(ddevService: service)
        viewModel.selectedProject = .sampleWordPress

        await viewModel.deleteSelectedDDEVData()

        XCTAssertEqual(service.commands, ["delete:aqua-pura", "list"])
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
}

private final class FakeDDEVService: DDEVServicing, @unchecked Sendable {
    private let lock = NSLock()
    private let loadedProjects: [DDEVProject]
    private var recordedCommands: [String] = []

    var commands: [String] {
        lock.withLock { recordedCommands }
    }

    init(projects: [DDEVProject]) {
        self.loadedProjects = projects
    }

    func listProjects() async throws -> [DDEVProject] {
        record("list")
        return loadedProjects
    }

    func start(projectName: String) async throws -> CommandResult {
        record("start:\(projectName)")
        return .success()
    }

    func stop(projectName: String) async throws -> CommandResult {
        record("stop:\(projectName)")
        return .success()
    }

    func restart(projectName: String) async throws -> CommandResult {
        record("restart:\(projectName)")
        return .success()
    }

    func unlink(projectName: String) async throws -> CommandResult {
        record("unlink:\(projectName)")
        return .success()
    }

    func deleteDDEVData(projectName: String) async throws -> CommandResult {
        record("delete:\(projectName)")
        return .success()
    }

    func startProject(in appRoot: String) async throws -> CommandResult {
        record("start-folder:\(appRoot)")
        return .success()
    }

    func configureProject(in appRoot: String, name: String, type: DDEVProjectType, docroot: String) async throws -> CommandResult {
        record("config:\(appRoot):\(name):\(type.rawValue):\(docroot)")
        return .success()
    }

    func launchDatabaseTool(_ tool: DDEVDatabaseTool, in appRoot: String) async throws -> CommandResult {
        record("db:\(tool.rawValue):\(appRoot)")
        return .success()
    }

    func updateWordPressCore(in appRoot: String) async throws -> CommandResult {
        record("wp-core:\(appRoot)")
        return .success()
    }

    func updateWordPressPlugins(in appRoot: String) async throws -> CommandResult {
        record("wp-plugins:\(appRoot)")
        return .success()
    }

    func updateWordPressThemes(in appRoot: String) async throws -> CommandResult {
        record("wp-themes:\(appRoot)")
        return .success()
    }

    private func record(_ command: String) {
        lock.withLock {
            recordedCommands.append(command)
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
        mutagenStatus: "ok"
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
        mutagenStatus: "ok"
    )
}
