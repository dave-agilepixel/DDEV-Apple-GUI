import Combine
import Foundation

public protocol DDEVServicing: Sendable {
    func listProjects() async throws -> [DDEVProject]
    func describe(projectName: String) async throws -> DDEVProjectDetails
    func start(projectName: String) async throws -> CommandResult
    func stop(projectName: String) async throws -> CommandResult
    func restart(projectName: String) async throws -> CommandResult
    func unlink(projectName: String) async throws -> CommandResult
    func deleteDDEVData(projectName: String) async throws -> CommandResult
    func startProject(in appRoot: String) async throws -> CommandResult
    func configureProject(in appRoot: String, name: String, type: DDEVProjectType, docroot: String) async throws -> CommandResult
    func setPHPVersion(_ version: String, in appRoot: String) async throws -> CommandResult
    func launchDatabaseTool(_ tool: DDEVDatabaseTool, in appRoot: String) async throws -> CommandResult
    func importDatabase(_ options: DDEVDatabaseImportOptions, in appRoot: String) async throws -> CommandResult
    func exportDatabase(_ options: DDEVDatabaseExportOptions, in appRoot: String) async throws -> CommandResult
    func importFiles(_ options: DDEVFileImportOptions, in appRoot: String) async throws -> CommandResult
    func createSnapshot(name: String?, in appRoot: String) async throws -> CommandResult
    func listSnapshots(in appRoot: String) async throws -> CommandResult
    func restoreSnapshot(named snapshotName: String, in appRoot: String) async throws -> CommandResult
    func logs(projectName: String, service: String, tail: Int, includeTimestamps: Bool, in appRoot: String) async throws -> CommandResult
    func listInstalledAddOns(in appRoot: String) async throws -> CommandResult
    func searchAddOns(query: String, in appRoot: String) async throws -> CommandResult
    func getAddOn(_ repository: String, in appRoot: String) async throws -> CommandResult
    func removeAddOn(named name: String, in appRoot: String) async throws -> CommandResult
    func config(flags: [String], in appRoot: String) async throws -> CommandResult
    func utilityDiagnose(in appRoot: String) async throws -> CommandResult
    func utilityConfigYAML(omitKeys: [String], in appRoot: String) async throws -> CommandResult
    func mutagen(_ command: DDEVMutagenCommand, in appRoot: String) async throws -> CommandResult
    func xhgui(_ command: DDEVXHGuiCommand, in appRoot: String) async throws -> CommandResult
    func updateWordPressCore(in appRoot: String) async throws -> CommandResult
    func updateWordPressPlugins(in appRoot: String) async throws -> CommandResult
    func updateWordPressThemes(in appRoot: String) async throws -> CommandResult
}

extension DDEVCommandService: DDEVServicing {}

public struct CommandHistoryEntry: Equatable, Sendable {
    public let result: CommandResult

    public init(result: CommandResult) {
        self.result = result
    }
}

public enum ProjectSidebarItem: String, CaseIterable, Identifiable, Sendable {
    case projects
    case running
    case wordpress
    case settings

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .projects:
            "Projects"
        case .running:
            "Running"
        case .wordpress:
            "WordPress"
        case .settings:
            "Settings"
        }
    }

    public var systemImage: String {
        switch self {
        case .projects:
            "shippingbox"
        case .running:
            "play.circle"
        case .wordpress:
            "w.circle"
        case .settings:
            "gearshape"
        }
    }
}

@MainActor
public final class ProjectDashboardViewModel: ObservableObject {
    @Published public var projects: [DDEVProject] = []
    @Published public var selectedProjectID: DDEVProject.ID?
    @Published public var selectedSidebarItem: ProjectSidebarItem = .projects
    @Published public var searchText = ""
    @Published public var isRunningCommand = false
    @Published public var lastCommandResult: CommandResult?
    @Published public var lastErrorMessage: String?
    @Published public var commandOutputExpansionRequest = 0
    @Published public var commandHistory: [CommandHistoryEntry] = []

    public let supportedPHPVersions = ["8.4", "8.3", "8.2", "8.1", "8.0", "7.4"]

    private let ddevService: DDEVServicing
    private let projectCache: ProjectCacheStoring
    private var selectedProjectFallback: DDEVProject?

    public init(
        ddevService: DDEVServicing = DDEVCommandService(),
        projectCache: ProjectCacheStoring = FileProjectCacheStore()
    ) {
        self.ddevService = ddevService
        self.projectCache = projectCache
    }

    public var selectedProject: DDEVProject? {
        get {
            guard let selectedProjectID else { return nil }
            return projects.first { $0.id == selectedProjectID } ?? selectedProjectFallback
        }
        set {
            selectedProjectID = newValue?.id
            selectedProjectFallback = newValue
        }
    }

    public var filteredProjects: [DDEVProject] {
        filteredProjects(in: projects)
    }

    private func filteredProjects(in sourceProjects: [DDEVProject]) -> [DDEVProject] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let sectionProjects = sourceProjects.filter { project in
            switch selectedSidebarItem {
            case .projects:
                true
            case .running:
                project.status == .running
            case .wordpress:
                project.isWordPress
            case .settings:
                false
            }
        }

        guard !query.isEmpty else { return sectionProjects }

        return sectionProjects.filter { project in
            project.name.localizedCaseInsensitiveContains(query)
                || project.shortRoot.localizedCaseInsensitiveContains(query)
                || project.projectType.rawValue.localizedCaseInsensitiveContains(query)
                || (project.phpVersion?.localizedCaseInsensitiveContains(query) ?? false)
        }
    }

    public func refresh() async {
        await runAndCapture {
            let loadedProjects = try await self.ddevService.listProjects()
            let enrichedProjects = await self.enrichProjectsWithDetails(loadedProjects)
            self.applyProjects(enrichedProjects)
            try? self.projectCache.saveProjects(enrichedProjects)

            return nil
        }
    }

    public func loadCachedProjectsThenRefresh() async {
        loadCachedProjects()
        await refresh()
    }

    public func setPHPVersionForSelectedProject(_ version: String) async {
        guard let selectedProject else { return }
        await runAndCapture {
            let configResult = try await self.ddevService.setPHPVersion(version, in: selectedProject.appRoot)
            self.recordCommandResult(configResult, requestsOutputExpansion: false)

            if selectedProject.status == .running {
                let restartResult = try await self.ddevService.restart(projectName: selectedProject.name)
                self.recordCommandResult(restartResult, requestsOutputExpansion: false)
            }

            await self.refresh()
            return self.lastCommandResult
        }
    }

    public func startSelectedProject() async {
        guard let selectedProject else { return }
        await runMutation {
            try await self.ddevService.start(projectName: selectedProject.name)
        }
    }

    public func stopSelectedProject() async {
        guard let selectedProject else { return }
        await runMutation {
            try await self.ddevService.stop(projectName: selectedProject.name)
        }
    }

    public func restartSelectedProject() async {
        guard let selectedProject else { return }
        await runMutation {
            try await self.ddevService.restart(projectName: selectedProject.name)
        }
    }

    public func unlinkSelectedProject() async {
        guard let selectedProject else { return }
        await runMutation {
            try await self.ddevService.unlink(projectName: selectedProject.name)
        }
    }

    public func deleteSelectedDDEVData() async {
        guard let selectedProject else { return }
        await runMutation {
            try await self.ddevService.deleteDDEVData(projectName: selectedProject.name)
        }
    }

    public func startProject(atFolder path: String) async {
        await runMutation {
            try await self.ddevService.startProject(in: path)
        }
    }

    public func configureProject(folder: String, name: String, type: DDEVProjectType, docroot: String) async {
        await runMutation {
            try await self.ddevService.configureProject(in: folder, name: name, type: type, docroot: docroot)
        }
    }

    public func launchDatabaseTool(_ tool: DDEVDatabaseTool) async {
        guard let selectedProject else { return }
        await runMutation {
            try await self.ddevService.launchDatabaseTool(tool, in: selectedProject.appRoot)
        }
    }

    public func importDatabase(_ options: DDEVDatabaseImportOptions) async {
        guard let selectedProject else { return }
        await runMutation {
            try await self.ddevService.importDatabase(options, in: selectedProject.appRoot)
        }
    }

    public func exportDatabase(_ options: DDEVDatabaseExportOptions) async {
        guard let selectedProject else { return }
        await runAndCapture {
            let result = try await self.ddevService.exportDatabase(options, in: selectedProject.appRoot)
            self.recordCommandResult(result)
            return result
        }
    }

    public func updateWordPressCore() async {
        guard let selectedProject, selectedProject.isWordPress else { return }
        await runMutation {
            try await self.ddevService.updateWordPressCore(in: selectedProject.appRoot)
        }
    }

    public func updateWordPressPlugins() async {
        guard let selectedProject, selectedProject.isWordPress else { return }
        await runMutation {
            try await self.ddevService.updateWordPressPlugins(in: selectedProject.appRoot)
        }
    }

    public func updateWordPressThemes() async {
        guard let selectedProject, selectedProject.isWordPress else { return }
        await runMutation {
            try await self.ddevService.updateWordPressThemes(in: selectedProject.appRoot)
        }
    }

    public func canRunWordPressActions(for project: DDEVProject?) -> Bool {
        project?.isWordPress == true
    }

    public func moveSelectedProjectFolderToTrash() {
        guard let selectedProject else { return }

        do {
            try FileManager.default.trashItem(
                at: URL(fileURLWithPath: selectedProject.appRoot),
                resultingItemURL: nil
            )
            projects.removeAll { $0.id == selectedProject.id }
            self.selectedProject = projects.first
            lastCommandResult = nil
            lastErrorMessage = nil
        } catch {
            lastErrorMessage = String(describing: error)
        }
    }

    private func runMutation(_ operation: @escaping () async throws -> CommandResult) async {
        await runAndCapture {
            let result = try await operation()
            self.recordCommandResult(result)
            await self.refresh()
            return result
        }
    }

    private func runAndCapture(_ operation: @escaping () async throws -> CommandResult?) async {
        isRunningCommand = true
        lastErrorMessage = nil
        defer { isRunningCommand = false }

        do {
            _ = try await operation()
        } catch CommandRunnerError.nonZeroExit(let result) {
            recordCommandResult(result)
            lastErrorMessage = "Command failed with exit code \(result.exitCode)."
        } catch {
            lastErrorMessage = String(describing: error)
        }
    }

    private func recordCommandResult(_ result: CommandResult, requestsOutputExpansion: Bool = true) {
        lastCommandResult = result
        commandHistory.append(CommandHistoryEntry(result: result))

        if requestsOutputExpansion {
            commandOutputExpansionRequest += 1
        }
    }

    private func loadCachedProjects() {
        guard projects.isEmpty else { return }
        guard let cachedProjects = try? projectCache.loadProjects(), !cachedProjects.isEmpty else { return }

        applyProjects(cachedProjects)
    }

    private func applyProjects(_ projects: [DDEVProject]) {
        self.projects = projects

        if let selectedProjectID,
           let selectedProject = projects.first(where: { $0.id == selectedProjectID }) {
            selectedProjectFallback = selectedProject
        } else {
            let fallbackProject = filteredProjects(in: projects).first ?? projects.first
            selectedProjectID = fallbackProject?.id
            selectedProjectFallback = fallbackProject
        }
    }

    private func enrichProjectsWithDetails(_ projects: [DDEVProject]) async -> [DDEVProject] {
        var enrichedProjects: [DDEVProject] = []

        for project in projects {
            do {
                let details = try await ddevService.describe(projectName: project.name)
                enrichedProjects.append(project.applying(details: details))
            } catch {
                enrichedProjects.append(project)
            }
        }

        return enrichedProjects
    }
}
