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
    func restoreLatestSnapshot(in appRoot: String) async throws -> CommandResult
    func cleanupSnapshots(in appRoot: String) async throws -> CommandResult
    func cleanupSnapshot(named snapshotName: String, in appRoot: String) async throws -> CommandResult
    func logs(projectName: String, service: String, tail: Int, includeTimestamps: Bool, in appRoot: String) async throws -> CommandResult
    func listInstalledAddOns(in appRoot: String) async throws -> CommandResult
    func searchAddOns(query: String, in appRoot: String) async throws -> CommandResult
    func getAddOn(_ repository: String, in appRoot: String) async throws -> CommandResult
    func removeAddOn(named name: String, in appRoot: String) async throws -> CommandResult
    func config(flags: [String], in appRoot: String) async throws -> CommandResult
    func applyConfigChange(_ change: DDEVConfigChange, in appRoot: String) async throws -> CommandResult
    func runProjectCommand(arguments: [String], in appRoot: String) async throws -> CommandResult
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
    @Published public var snapshots: [DDEVSnapshot] = []
    @Published public var projectLogsResult: CommandResult?
    @Published public var projectLogsErrorMessage: String?
    @Published public var projectConfig: DDEVConfig?
    @Published public var projectConfigErrorMessage: String?
    @Published public var projectConfigRestartRecommended = false
    @Published public private(set) var preferences: AppPreferences
    @Published public private(set) var installedEditors: [EditorChoice]
    @Published public private(set) var installedDatabaseTools: [DDEVDatabaseTool]

    public let supportedPHPVersions = ["8.4", "8.3", "8.2", "8.1", "8.0", "7.4"]

    private let ddevService: DDEVServicing
    private let projectCache: ProjectCacheStoring
    private let preferencesStore: AppPreferencesStoring
    private let appAvailability: AppAvailabilityChecking
    private var selectedProjectFallback: DDEVProject?

    public init(
        ddevService: DDEVServicing = DDEVCommandService(),
        projectCache: ProjectCacheStoring = FileProjectCacheStore(),
        preferencesStore: AppPreferencesStoring = UserDefaultsAppPreferencesStore(),
        appAvailability: AppAvailabilityChecking = WorkspaceAppAvailabilityService()
    ) {
        self.ddevService = ddevService
        self.projectCache = projectCache
        self.preferencesStore = preferencesStore
        self.appAvailability = appAvailability
        self.preferences = preferencesStore.loadPreferences()
        self.installedEditors = appAvailability.installedEditors()
        self.installedDatabaseTools = appAvailability.installedDatabaseTools()
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

    public var availableEditors: [EditorChoice] {
        AppDefaults.availableEditors(installedEditors: installedEditors)
    }

    public var availableDatabaseTools: [DDEVDatabaseTool] {
        installedDatabaseTools
    }

    public var effectiveDefaultEditor: EditorChoice {
        AppDefaults.effectiveEditor(saved: preferences.defaultEditor, installedEditors: installedEditors)
    }

    public var effectiveDefaultDatabaseTool: DDEVDatabaseTool? {
        AppDefaults.effectiveDatabaseTool(
            saved: preferences.defaultDatabaseTool,
            installedDatabaseTools: installedDatabaseTools
        )
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

    public func setDefaultEditor(_ editor: EditorChoice?) {
        preferences.defaultEditor = editor
        preferencesStore.saveDefaultEditor(editor)
    }

    public func setDefaultDatabaseTool(_ databaseTool: DDEVDatabaseTool?) {
        preferences.defaultDatabaseTool = databaseTool
        preferencesStore.saveDefaultDatabaseTool(databaseTool)
    }

    public func refreshInstalledApps() {
        installedEditors = appAvailability.installedEditors()
        installedDatabaseTools = appAvailability.installedDatabaseTools()
    }

    public func refresh() async {
        await runAndCapture {
            try await self.refreshProjectsFromDDEV()
            return nil
        }
    }

    public func loadCachedProjectsThenRefresh() async {
        let loadedCachedProjects = loadCachedProjects()

        if loadedCachedProjects {
            await refreshProjectsFromDDEVInBackground()
        } else {
            await refresh()
        }
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

    public func launchDefaultDatabaseTool() async {
        guard let databaseTool = effectiveDefaultDatabaseTool else { return }
        await launchDatabaseTool(databaseTool)
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

    public func loadSnapshotsForSelectedProject() async {
        guard let selectedProject else { return }
        await runAndCapture {
            let result = try await self.ddevService.listSnapshots(in: selectedProject.appRoot)
            self.snapshots = DDEVSnapshot.parseListOutput(result.stdout)
            return nil
        }
    }

    public func createSnapshotForSelectedProject(name: String?) async {
        guard let selectedProject else { return }
        await runAndCapture {
            let result = try await self.ddevService.createSnapshot(name: name, in: selectedProject.appRoot)
            self.recordCommandResult(result)
            await self.refreshSnapshots(in: selectedProject.appRoot)
            return result
        }
    }

    public func restoreSnapshotForSelectedProject(named snapshotName: String) async {
        guard let selectedProject else { return }
        await runMutation {
            try await self.ddevService.restoreSnapshot(named: snapshotName, in: selectedProject.appRoot)
        }
    }

    public func restoreLatestSnapshotForSelectedProject() async {
        guard let selectedProject else { return }
        await runMutation {
            try await self.ddevService.restoreLatestSnapshot(in: selectedProject.appRoot)
        }
    }

    public func cleanupSnapshotsForSelectedProject() async {
        guard let selectedProject else { return }
        await runAndCapture {
            let result = try await self.ddevService.cleanupSnapshots(in: selectedProject.appRoot)
            self.recordCommandResult(result)
            await self.refreshSnapshots(in: selectedProject.appRoot)
            return result
        }
    }

    public func cleanupSnapshotForSelectedProject(named snapshotName: String) async {
        guard let selectedProject else { return }
        await runAndCapture {
            let result = try await self.ddevService.cleanupSnapshot(named: snapshotName, in: selectedProject.appRoot)
            self.recordCommandResult(result)
            await self.refreshSnapshots(in: selectedProject.appRoot)
            return result
        }
    }

    public func loadLogsForSelectedProject(_ request: DDEVLogRequest) async {
        guard let selectedProject else { return }

        isRunningCommand = true
        lastErrorMessage = nil
        projectLogsErrorMessage = nil
        defer { isRunningCommand = false }

        do {
            let result = try await ddevService.logs(
                projectName: selectedProject.name,
                service: request.service.rawValue,
                tail: request.tailCount,
                includeTimestamps: request.includeTimestamps,
                in: selectedProject.appRoot
            )
            projectLogsResult = result
            recordCommandResult(result, requestsOutputExpansion: false)
        } catch CommandRunnerError.nonZeroExit(let result) {
            projectLogsResult = result
            recordCommandResult(result, requestsOutputExpansion: false)
            let message = "Command failed with exit code \(result.exitCode)."
            lastErrorMessage = message
            projectLogsErrorMessage = message
        } catch {
            let message = String(describing: error)
            lastErrorMessage = message
            projectLogsErrorMessage = message
        }
    }

    public func loadLogsForSelectedProjectIfRunning(_ request: DDEVLogRequest) async {
        guard selectedProject?.status == .running else { return }

        await loadLogsForSelectedProject(request)
    }

    public func clearProjectLogs() {
        projectLogsResult = nil
        projectLogsErrorMessage = nil
    }

    public func loadConfigForSelectedProject() async {
        guard let selectedProject else { return }

        isRunningCommand = true
        lastErrorMessage = nil
        projectConfigErrorMessage = nil
        defer { isRunningCommand = false }

        do {
            let result = try await ddevService.utilityConfigYAML(omitKeys: ["web_environment"], in: selectedProject.appRoot)
            projectConfig = try DDEVConfig.parseYAML(result.stdout)
        } catch {
            let message = String(describing: error)
            lastErrorMessage = message
            projectConfigErrorMessage = message
        }
    }

    public func applyConfigChangeForSelectedProject(_ change: DDEVConfigChange) async {
        guard let selectedProject else { return }

        await runAndCapture {
            let result = try await self.ddevService.applyConfigChange(change, in: selectedProject.appRoot)
            self.recordCommandResult(result)
            self.projectConfigRestartRecommended = selectedProject.status == .running
            return result
        }
    }

    public func clearProjectConfigRestartRecommendation() {
        projectConfigRestartRecommended = false
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

    public func frameworkCommands(for project: DDEVProject) -> [DDEVFrameworkCommand] {
        DDEVFrameworkCommand.presets(for: project.projectType)
    }

    public func runFrameworkCommandForSelectedProject(_ command: DDEVFrameworkCommand) async {
        guard let selectedProject else { return }

        await runAndCapture {
            let result = try await self.ddevService.runProjectCommand(arguments: command.arguments, in: selectedProject.appRoot)
            self.recordCommandResult(result)
            return result
        }
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

    private func refreshSnapshots(in appRoot: String) async {
        do {
            let result = try await ddevService.listSnapshots(in: appRoot)
            snapshots = DDEVSnapshot.parseListOutput(result.stdout)
        } catch {
            lastErrorMessage = String(describing: error)
        }
    }

    private func refreshProjectsFromDDEV() async throws {
        let loadedProjects = try await ddevService.listProjects()
        let enrichedProjects = await enrichProjectsWithDetails(loadedProjects)
        applyProjects(enrichedProjects)
        try? projectCache.saveProjects(enrichedProjects)
    }

    private func refreshProjectsFromDDEVInBackground() async {
        do {
            try await refreshProjectsFromDDEV()
        } catch {
            return
        }
    }

    private func loadCachedProjects() -> Bool {
        guard projects.isEmpty else { return false }
        guard let cachedProjects = try? projectCache.loadProjects(), !cachedProjects.isEmpty else { return false }

        applyProjects(cachedProjects)
        return true
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
