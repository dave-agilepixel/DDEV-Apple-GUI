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
    func listInstalledAddOns(projectName: String, in appRoot: String) async throws -> CommandResult
    func searchAddOns(query: String, in appRoot: String) async throws -> CommandResult
    func getAddOn(_ repository: String, projectName: String, in appRoot: String) async throws -> CommandResult
    func removeAddOn(named name: String, projectName: String, in appRoot: String) async throws -> CommandResult
    func config(flags: [String], in appRoot: String) async throws -> CommandResult
    func applyConfigChange(_ change: DDEVConfigChange, in appRoot: String) async throws -> CommandResult
    func runProjectCommand(arguments: [String], in appRoot: String) async throws -> CommandResult
    func version() async throws -> CommandResult
    func utilityDiagnose(in appRoot: String?) async throws -> CommandResult
    func utilityConfigYAML(omitKeys: [String], in appRoot: String) async throws -> CommandResult
    func utilityCheckCustomConfig(in appRoot: String) async throws -> CommandResult
    func utilityCheckDBMatch(in appRoot: String) async throws -> CommandResult
    func mutagen(_ command: DDEVMutagenCommand, in appRoot: String) async throws -> CommandResult
    func xhgui(_ command: DDEVXHGuiCommand, in appRoot: String) async throws -> CommandResult
    func updateWordPressCore(in appRoot: String) async throws -> CommandResult
    func updateWordPressPlugins(in appRoot: String) async throws -> CommandResult
    func updateWordPressThemes(in appRoot: String) async throws -> CommandResult
}

extension DDEVCommandService: DDEVServicing {}

public enum ProjectSidebarItem: String, CaseIterable, Identifiable, Sendable {
    case projects
    case running
    case wordpress
    case diagnostics
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
        case .diagnostics:
            "Diagnostics"
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
        case .diagnostics:
            "stethoscope"
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

    /// Per-project command state, keyed by project id (the project name). The single source
    /// of truth for busy/queued lifecycle, last result, error, history, and output expansion.
    @Published public var commandStates: [DDEVProject.ID: ProjectCommandState] = [:]

    /// Busy/error for genuinely project-less operations: global list refresh, global
    /// diagnostics, and new-project creation (which has no project id yet).
    @Published public var isRunningGlobalCommand = false
    @Published public var globalErrorMessage: String?
    @Published public var snapshots: [DDEVSnapshot] = []
    @Published public var snapshotErrorMessage: String?
    @Published public var projectLogsResult: CommandResult?
    @Published public var projectLogsErrorMessage: String?
    @Published public var projectConfig: DDEVConfig?
    @Published public var projectConfigErrorMessage: String?
    @Published public var projectConfigRestartRecommended = false
    @Published public var installedAddOns: [DDEVAddon] = []
    @Published public var addonSearchResults: [DDEVAddon] = DDEVAddon.recommendedOfficial
    @Published public var addonErrorMessage: String?
    @Published public var addOnRestartRecommended = false
    @Published public var addonRawOutput: String?
    @Published public var diagnosticReport = DDEVDiagnosticReport()
    @Published public var diagnosticsErrorMessage: String?
    @Published public private(set) var preferences: AppPreferences
    @Published public private(set) var installedEditors: [EditorChoice]
    @Published public private(set) var installedDatabaseTools: [DDEVDatabaseTool]

    public let supportedPHPVersions = ["8.4", "8.3", "8.2", "8.1", "8.0", "7.4"]

    private let ddevService: DDEVServicing
    private let projectCache: ProjectCacheStoring
    private let preferencesStore: AppPreferencesStoring
    private let appAvailability: AppAvailabilityChecking
    private let scheduler: CommandScheduler
    private let notifier: NotificationScheduling
    private var selectedProjectFallback: DDEVProject?
    /// Guards `refreshProjectsFromDDEV` against overlapping runs (audit M4). Not `@Published`
    /// — it's internal serialization, not UI state (`isRunningGlobalCommand` drives the spinner).
    private var isRefreshInFlight = false

    public init(
        ddevService: DDEVServicing = DDEVCommandService(),
        projectCache: ProjectCacheStoring = FileProjectCacheStore(),
        preferencesStore: AppPreferencesStoring = UserDefaultsAppPreferencesStore(),
        appAvailability: AppAvailabilityChecking = WorkspaceAppAvailabilityService(),
        scheduler: CommandScheduler = CommandScheduler(maxConcurrent: 3),
        notifier: NotificationScheduling = NoopNotificationScheduler()
    ) {
        self.ddevService = ddevService
        self.projectCache = projectCache
        self.preferencesStore = preferencesStore
        self.appAvailability = appAvailability
        self.scheduler = scheduler
        self.notifier = notifier
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

    public var copyableDiagnosticOutput: String {
        diagnosticReport.copyableOutput
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
            case .diagnostics:
                false
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

    public func requestNotificationAuthorization() async {
        await notifier.requestAuthorizationIfNeeded()
    }

    public func refresh() async {
        isRunningGlobalCommand = true
        globalErrorMessage = nil
        defer { isRunningGlobalCommand = false }
        do {
            try await refreshProjectsFromDDEV()
        } catch {
            globalErrorMessage = error.presentableMessage
        }
    }

    public func loadCachedProjectsThenRefresh() async {
        let loadedCachedProjects = await loadCachedProjects()

        if loadedCachedProjects {
            await refreshProjectsFromDDEVInBackground()
        } else {
            await refresh()
        }
    }

    public func setPHPVersionForSelectedProject(_ version: String) async {
        guard let selectedProject else { return }
        let id = selectedProject.id
        guard !isBusy(selectedProject) else { return }

        setActivity(.queued, for: id)
        await scheduler.acquire()
        setActivity(.running, for: id)

        let outcome = await execute {
            let configResult = try await self.ddevService.setPHPVersion(version, in: selectedProject.appRoot)
            // PHP changes surface via the re-describe, not the Logs-tab output badge (matches prior behavior).
            self.recordResult(configResult, for: id, expandsOutput: false)
            if selectedProject.status == .running {
                let restartResult = try await self.ddevService.restart(projectName: selectedProject.name)
                self.recordResult(restartResult, for: id, expandsOutput: false)
                return restartResult
            }
            return configResult
        }
        await scheduler.release()
        setActivity(.idle, for: id)

        await finish(outcome, for: selectedProject, refresh: .project, recordResultOnComplete: false)
    }

    public func state(for id: DDEVProject.ID) -> ProjectCommandState {
        commandStates[id] ?? ProjectCommandState()
    }

    public func isBusy(_ project: DDEVProject) -> Bool {
        state(for: project.id).isBusy
    }

    public func isQueued(_ project: DDEVProject) -> Bool {
        state(for: project.id).activity == .queued
    }

    /// State of the currently-selected project (empty default when nothing is selected).
    public var selectedProjectState: ProjectCommandState {
        guard let selectedProjectID else { return ProjectCommandState() }
        return state(for: selectedProjectID)
    }

    public var isSelectedProjectBusy: Bool {
        selectedProjectState.isBusy
    }

    public func start(_ project: DDEVProject) async {
        await runProjectMutation(project) {
            try await self.ddevService.start(projectName: project.name)
        }
    }

    public func stop(_ project: DDEVProject) async {
        await runProjectMutation(project) {
            try await self.ddevService.stop(projectName: project.name)
        }
    }

    public func restart(_ project: DDEVProject) async {
        await runProjectMutation(project) {
            try await self.ddevService.restart(projectName: project.name)
        }
    }

    public func startSelectedProject() async {
        guard let selectedProject else { return }
        await start(selectedProject)
    }

    public func stopSelectedProject() async {
        guard let selectedProject else { return }
        await stop(selectedProject)
    }

    public func restartSelectedProject() async {
        guard let selectedProject else { return }
        await restart(selectedProject)
    }

    public func unlinkSelectedProject() async {
        guard let selectedProject else { return }
        await runProjectMutation(selectedProject, refresh: .fullList) {
            try await self.ddevService.unlink(projectName: selectedProject.name)
        }
    }

    public func deleteSelectedDDEVData() async {
        guard let selectedProject else { return }
        await runProjectMutation(selectedProject, refresh: .fullList) {
            try await self.ddevService.deleteDDEVData(projectName: selectedProject.name)
        }
    }

    public func startProject(atFolder path: String) async {
        await runGlobalMutation {
            try await self.ddevService.startProject(in: path)
        }
    }

    public func configureProject(folder: String, name: String, type: DDEVProjectType, docroot: String) async {
        await runGlobalMutation {
            try await self.ddevService.configureProject(in: folder, name: name, type: type, docroot: docroot)
        }
    }

    public func launchDatabaseTool(_ tool: DDEVDatabaseTool) async {
        guard let selectedProject else { return }
        await runProjectMutation(selectedProject, refresh: .none) {
            try await self.ddevService.launchDatabaseTool(tool, in: selectedProject.appRoot)
        }
    }

    public func launchDefaultDatabaseTool() async {
        guard let databaseTool = effectiveDefaultDatabaseTool else { return }
        await launchDatabaseTool(databaseTool)
    }

    public func importDatabase(_ options: DDEVDatabaseImportOptions) async {
        guard let selectedProject else { return }
        await runProjectMutation(selectedProject) {
            try await self.ddevService.importDatabase(options, in: selectedProject.appRoot)
        }
    }

    public func exportDatabase(_ options: DDEVDatabaseExportOptions) async {
        guard let selectedProject else { return }
        await runProjectMutation(selectedProject, refresh: .none) {
            try await self.ddevService.exportDatabase(options, in: selectedProject.appRoot)
        }
    }

    public func loadSnapshotsForSelectedProject() async {
        guard let selectedProject else { return }
        snapshotErrorMessage = nil
        await runSelectedProjectRead {
            let result = try await self.ddevService.listSnapshots(in: selectedProject.appRoot)
            self.snapshots = DDEVSnapshot.parseListOutput(result.stdout)
            return nil
        }
    }

    public func createSnapshotForSelectedProject(name: String?) async {
        guard let selectedProject else { return }
        await runProjectMutation(selectedProject, refresh: .none) {
            let result = try await self.ddevService.createSnapshot(name: name, in: selectedProject.appRoot)
            await self.refreshSnapshots(in: selectedProject.appRoot)
            return result
        }
    }

    public func restoreSnapshotForSelectedProject(named snapshotName: String) async {
        guard let selectedProject else { return }
        await runProjectMutation(selectedProject) {
            try await self.ddevService.restoreSnapshot(named: snapshotName, in: selectedProject.appRoot)
        }
    }

    public func restoreLatestSnapshotForSelectedProject() async {
        guard let selectedProject else { return }
        await runProjectMutation(selectedProject) {
            try await self.ddevService.restoreLatestSnapshot(in: selectedProject.appRoot)
        }
    }

    public func cleanupSnapshotsForSelectedProject() async {
        guard let selectedProject else { return }
        await runProjectMutation(selectedProject, refresh: .none) {
            let result = try await self.ddevService.cleanupSnapshots(in: selectedProject.appRoot)
            await self.refreshSnapshots(in: selectedProject.appRoot)
            return result
        }
    }

    public func cleanupSnapshotForSelectedProject(named snapshotName: String) async {
        guard let selectedProject else { return }
        await runProjectMutation(selectedProject, refresh: .none) {
            let result = try await self.ddevService.cleanupSnapshot(named: snapshotName, in: selectedProject.appRoot)
            await self.refreshSnapshots(in: selectedProject.appRoot)
            return result
        }
    }

    public func loadLogsForSelectedProject(_ request: DDEVLogRequest) async {
        guard let selectedProject else { return }
        projectLogsErrorMessage = nil
        await runSelectedProjectRead(recordOutput: true) {
            do {
                let result = try await self.ddevService.logs(
                    projectName: selectedProject.name,
                    service: request.service.rawValue,
                    tail: request.tailCount,
                    includeTimestamps: request.includeTimestamps,
                    in: selectedProject.appRoot
                )
                self.projectLogsResult = result
                return result
            } catch CommandRunnerError.nonZeroExit(let result) {
                self.projectLogsResult = result
                self.projectLogsErrorMessage = "Command failed with exit code \(result.exitCode)."
                throw CommandRunnerError.nonZeroExit(result)
            }
        }
        if projectLogsErrorMessage == nil { projectLogsErrorMessage = selectedProjectState.lastErrorMessage }
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
        projectConfigErrorMessage = nil
        projectConfig = nil
        await runSelectedProjectRead {
            do {
                let result = try await self.ddevService.utilityConfigYAML(omitKeys: ["web_environment"], in: selectedProject.appRoot)
                self.projectConfig = try DDEVConfig.parseYAML(result.stdout)
                return nil
            } catch CommandRunnerError.nonZeroExit(let result) {
                self.projectConfigErrorMessage = result.stderr.nilIfBlank ?? "Command failed with exit code \(result.exitCode)."
                throw CommandRunnerError.nonZeroExit(result)
            }
        }
    }

    public func applyConfigChangeForSelectedProject(_ change: DDEVConfigChange) async {
        guard let selectedProject else { return }
        await runProjectMutation(selectedProject, refresh: .none) {
            let result = try await self.ddevService.applyConfigChange(change, in: selectedProject.appRoot)
            self.projectConfigRestartRecommended = selectedProject.status == .running
            return result
        }
    }

    public func clearProjectConfigRestartRecommendation() {
        projectConfigRestartRecommended = false
    }

    public func loadInstalledAddOnsForSelectedProject() async {
        guard let selectedProject else { return }
        addonErrorMessage = nil
        await runSelectedProjectRead {
            do {
                let result = try await self.ddevService.listInstalledAddOns(
                    projectName: selectedProject.name, in: selectedProject.appRoot)
                self.installedAddOns = try DDEVAddon.parseListOutput(result.stdout)
                self.addonRawOutput = self.installedAddOns.isEmpty ? result.stdout.nilIfBlank : nil
                return nil
            } catch CommandRunnerError.nonZeroExit(let result) {
                self.addonErrorMessage = "Command failed with exit code \(result.exitCode)."
                throw CommandRunnerError.nonZeroExit(result)
            }
        }
    }

    public func searchAddOnsForSelectedProject(query: String) async {
        guard let selectedProject else { return }
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else {
            addonSearchResults = DDEVAddon.recommendedOfficial
            addonErrorMessage = nil
            return
        }
        addonErrorMessage = nil
        await runSelectedProjectRead {
            do {
                let result = try await self.ddevService.searchAddOns(query: trimmedQuery, in: selectedProject.appRoot)
                let parsedResults = try DDEVAddon.parseListOutput(result.stdout)
                self.addonSearchResults = parsedResults.isEmpty ? DDEVAddon.recommendedOfficial : parsedResults
                self.addonRawOutput = parsedResults.isEmpty ? result.stdout.nilIfBlank : nil
                return nil
            } catch CommandRunnerError.nonZeroExit(let result) {
                self.addonErrorMessage = "Command failed with exit code \(result.exitCode)."
                throw CommandRunnerError.nonZeroExit(result)
            }
        }
    }

    public func installAddOnForSelectedProject(_ repository: String) async {
        guard let selectedProject else { return }
        addonErrorMessage = nil
        await runProjectMutation(selectedProject, refresh: .none) {
            let result = try await self.ddevService.getAddOn(
                repository, projectName: selectedProject.name, in: selectedProject.appRoot)
            self.addOnRestartRecommended = true
            await self.refreshInstalledAddOns(in: selectedProject.appRoot, projectName: selectedProject.name)
            return result
        }
        addonErrorMessage = selectedProjectState.lastErrorMessage
    }

    public func removeAddOnForSelectedProject(named name: String) async {
        guard let selectedProject else { return }
        addonErrorMessage = nil
        await runProjectMutation(selectedProject, refresh: .none) {
            let result = try await self.ddevService.removeAddOn(
                named: name, projectName: selectedProject.name, in: selectedProject.appRoot)
            self.addOnRestartRecommended = true
            await self.refreshInstalledAddOns(in: selectedProject.appRoot, projectName: selectedProject.name)
            return result
        }
        addonErrorMessage = selectedProjectState.lastErrorMessage
    }

    public func clearAddOnRestartRecommendation() {
        addOnRestartRecommended = false
    }

    public func updateWordPressCore() async {
        guard let selectedProject, selectedProject.isWordPress else { return }
        await runProjectMutation(selectedProject) {
            try await self.ddevService.updateWordPressCore(in: selectedProject.appRoot)
        }
    }

    public func updateWordPressPlugins() async {
        guard let selectedProject, selectedProject.isWordPress else { return }
        await runProjectMutation(selectedProject) {
            try await self.ddevService.updateWordPressPlugins(in: selectedProject.appRoot)
        }
    }

    public func updateWordPressThemes() async {
        guard let selectedProject, selectedProject.isWordPress else { return }
        await runProjectMutation(selectedProject) {
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
        await runProjectMutation(selectedProject) {
            try await self.ddevService.runProjectCommand(arguments: command.arguments, in: selectedProject.appRoot)
        }
    }

    public func runGlobalDiagnostics() async {
        await runDiagnostics {
            [
                try await self.diagnosticEntry(.ddevVersion) {
                    try await self.ddevService.version()
                },
                try await self.diagnosticEntry(.globalDiagnose) {
                    try await self.ddevService.utilityDiagnose(in: nil)
                }
            ]
        }
    }

    public func runProjectDiagnosticsForSelectedProject() async {
        guard let selectedProject else {
            await runGlobalDiagnostics()
            return
        }

        await runDiagnostics {
            var entries = [
                try await self.diagnosticEntry(.projectDiagnose) {
                    try await self.ddevService.utilityDiagnose(in: selectedProject.appRoot)
                },
                try await self.diagnosticEntry(.customConfig) {
                    try await self.ddevService.utilityCheckCustomConfig(in: selectedProject.appRoot)
                },
                try await self.diagnosticEntry(.dbMatch) {
                    try await self.ddevService.utilityCheckDBMatch(in: selectedProject.appRoot)
                }
            ]

            if selectedProject.mutagenEnabled {
                entries.append(try await self.diagnosticEntry(.mutagenStatus) {
                    try await self.ddevService.mutagen(.status, in: selectedProject.appRoot)
                })
            }

            return entries
        }
    }

    public func runMutagenDiagnosticForSelectedProject(_ command: DDEVMutagenCommand) async {
        guard let selectedProject else { return }

        await runDiagnostics {
            [
                try await self.diagnosticEntry(DDEVDiagnosticCheck(mutagenCommand: command)) {
                    try await self.ddevService.mutagen(command, in: selectedProject.appRoot)
                }
            ]
        }
    }

    public func enableXHGuiForSelectedProject() async {
        guard let selectedProject else { return }
        await runProjectMutation(selectedProject) {
            try await self.ddevService.xhgui(.on, in: selectedProject.appRoot)
        }
    }

    public func moveSelectedProjectFolderToTrash() {
        guard let selectedProject else { return }

        do {
            try FileManager.default.trashItem(
                at: URL(fileURLWithPath: selectedProject.appRoot),
                resultingItemURL: nil
            )
            let removedID = selectedProject.id
            projects.removeAll { $0.id == removedID }
            commandStates[removedID] = nil
            self.selectedProject = projects.first
            globalErrorMessage = nil
        } catch {
            globalErrorMessage = error.presentableMessage
        }
    }

    enum RefreshScope {
        case project   // re-describe just the affected project (state changed)
        case fullList  // re-list everything (project added/removed/renamed)
        case none      // no refresh (e.g. export writes a file, changes nothing)
    }

    /// Runs a state-changing command for one project: cap-gated, per-project state, scoped
    /// refresh, and a notification when the project is not the focused one.
    private func runProjectMutation(
        _ project: DDEVProject,
        refresh: RefreshScope = .project,
        _ operation: @escaping () async throws -> CommandResult
    ) async {
        let id = project.id
        guard !isBusy(project) else { return } // one command per project at a time

        setActivity(.queued, for: id)
        // Manual acquire/release (not scheduler.run) so the permit frees before the re-describe read.
        await scheduler.acquire()              // resumes on MainActor
        setActivity(.running, for: id)

        let outcome = await execute(operation)
        await scheduler.release()              // free the slot before the read-y describe
        setActivity(.idle, for: id)

        await finish(outcome, for: project, refresh: refresh)
    }

    /// Shared tail for mutation pipelines: records the result (unless the caller already
    /// recorded each step), applies the refresh scope, and fires a background notification.
    private func finish(
        _ outcome: Result<CommandResult, MutationError>,
        for project: DDEVProject,
        refresh: RefreshScope,
        recordResultOnComplete: Bool = true
    ) async {
        let id = project.id
        switch outcome {
        case .success(let result):
            if recordResultOnComplete { recordResult(result, for: id) }
            await applyRefresh(refresh, for: project)
            await notifyIfBackground(project: project, succeeded: true, summary: summary(result))
        case .failure(.nonZeroExit(let result)):
            if recordResultOnComplete { recordResult(result, for: id) }
            commandStates[id, default: .init()].lastErrorMessage = "Command failed with exit code \(result.exitCode)."
            await notifyIfBackground(project: project, succeeded: false, summary: summary(result))
        case .failure(.other(let error)):
            commandStates[id, default: .init()].lastErrorMessage = error.presentableMessage
            await notifyIfBackground(project: project, succeeded: false, summary: "command failed")
        }
    }

    private enum MutationError: Error { case nonZeroExit(CommandResult), other(Error) }

    private func execute(_ operation: () async throws -> CommandResult) async -> Result<CommandResult, MutationError> {
        do { return .success(try await operation()) }
        catch CommandRunnerError.nonZeroExit(let result) { return .failure(.nonZeroExit(result)) }
        catch { return .failure(.other(error)) }
    }

    private func setActivity(_ activity: ProjectCommandState.Activity, for id: DDEVProject.ID) {
        commandStates[id, default: .init()].activity = activity
    }

    private func applyRefresh(_ scope: RefreshScope, for project: DDEVProject) async {
        switch scope {
        case .none: return
        case .fullList: await refreshProjectsFromDDEVInBackground()
        case .project: await reDescribe(project)
        }
    }

    /// Re-describe a single project and patch it into `projects` in place.
    private func reDescribe(_ project: DDEVProject) async {
        guard let refreshed = try? await ddevService.describe(projectName: project.name) else { return }
        guard let index = projects.firstIndex(where: { $0.id == project.id }) else { return }
        projects[index] = projects[index].applying(details: refreshed)
        if selectedProjectFallback?.id == project.id {
            selectedProjectFallback = projects[index]
        }
        try? await projectCache.saveProjects(projects)
    }

    private func summary(_ result: CommandResult) -> String {
        let joined = result.arguments.joined(separator: " ")
        return joined.isEmpty ? result.executable : "\(result.executable) \(joined)"
    }

    private func notifyIfBackground(project: DDEVProject, succeeded: Bool, summary: String) async {
        guard project.id != selectedProjectID else { return }
        await notifier.notifyCommandFinished(projectName: project.name, summary: summary, succeeded: succeeded)
    }

    /// Records a per-project result + bounded history. `expandsOutput` mirrors the old
    /// `requestsOutputExpansion` default of `true` for mutations.
    private func recordResult(_ result: CommandResult, for id: DDEVProject.ID, expandsOutput: Bool = true) {
        var state = commandStates[id] ?? .init()
        state.lastResult = result
        state.history.append(CommandHistoryEntry(result: Self.bounded(result)))
        if state.history.count > Self.commandHistoryLimit {
            state.history.removeFirst(state.history.count - Self.commandHistoryLimit)
        }
        if expandsOutput { state.outputExpansionRequest += 1 }
        commandStates[id] = state
    }

    /// Pipeline for operations with no single owning project (new-project creation).
    /// Always full-list refreshes afterward.
    private func runGlobalMutation(_ operation: @escaping () async throws -> CommandResult) async {
        isRunningGlobalCommand = true
        globalErrorMessage = nil
        defer { isRunningGlobalCommand = false }
        do {
            _ = try await operation()
            try await refreshProjectsFromDDEV()
        } catch CommandRunnerError.nonZeroExit(let result) {
            globalErrorMessage = "Command failed with exit code \(result.exitCode)."
        } catch {
            globalErrorMessage = error.presentableMessage
        }
    }

    /// Pipeline for a *read* on the selected project: sets `isReadingData`, records the
    /// result into per-project state, never blocks lifecycle, never notifies, never caps.
    private func runSelectedProjectRead(
        recordOutput: Bool = false,
        _ operation: @escaping () async throws -> CommandResult?
    ) async {
        guard let id = selectedProjectID else { return }
        commandStates[id, default: .init()].isReadingData = true
        commandStates[id, default: .init()].lastErrorMessage = nil
        defer { commandStates[id, default: .init()].isReadingData = false }
        do {
            if let result = try await operation(), recordOutput {
                recordResult(result, for: id, expandsOutput: false)
            }
        } catch CommandRunnerError.nonZeroExit(let result) {
            recordResult(result, for: id, expandsOutput: false)
            commandStates[id, default: .init()].lastErrorMessage = "Command failed with exit code \(result.exitCode)."
        } catch {
            commandStates[id, default: .init()].lastErrorMessage = error.presentableMessage
        }
    }

    private func runDiagnostics(_ operation: @escaping () async throws -> [DDEVDiagnosticEntry]) async {
        isRunningGlobalCommand = true
        diagnosticsErrorMessage = nil
        defer { isRunningGlobalCommand = false }

        do {
            let entries = try await operation()
            diagnosticReport = DDEVDiagnosticReport(entries: entries)
        } catch let failure as DiagnosticFailure {
            if let result = failure.result {
                diagnosticReport = DDEVDiagnosticReport(entries: [
                    DDEVDiagnosticEntry(check: failure.check, result: result)
                ])
                diagnosticsErrorMessage = "Command failed with exit code \(result.exitCode)."
            } else {
                diagnosticsErrorMessage = failure.underlying.presentableMessage
            }
        } catch {
            diagnosticsErrorMessage = error.presentableMessage
        }
    }

    private func diagnosticEntry(
        _ check: DDEVDiagnosticCheck,
        operation: () async throws -> CommandResult
    ) async throws -> DDEVDiagnosticEntry {
        do {
            return DDEVDiagnosticEntry(check: check, result: try await operation())
        } catch CommandRunnerError.nonZeroExit(let result) {
            throw DiagnosticFailure(check: check, result: result, underlying: CommandRunnerError.nonZeroExit(result))
        } catch {
            throw DiagnosticFailure(check: check, result: nil, underlying: error)
        }
    }

    private static let commandHistoryLimit = 50
    private static let commandHistoryOutputLimit = 32 * 1024

    private static func bounded(_ result: CommandResult) -> CommandResult {
        let stdoutBounded = bound(result.stdout)
        let stderrBounded = bound(result.stderr)
        guard stdoutBounded.count != result.stdout.count || stderrBounded.count != result.stderr.count else {
            return result
        }
        return CommandResult(
            executable: result.executable,
            arguments: result.arguments,
            workingDirectory: result.workingDirectory,
            exitCode: result.exitCode,
            stdout: stdoutBounded,
            stderr: stderrBounded,
            startedAt: result.startedAt,
            finishedAt: result.finishedAt,
            wasCancelled: result.wasCancelled
        )
    }

    private static func bound(_ text: String) -> String {
        guard text.count > commandHistoryOutputLimit else { return text }
        let prefix = text.prefix(commandHistoryOutputLimit)
        return prefix + "\n…[truncated \(text.count - commandHistoryOutputLimit) chars]"
    }

    private func refreshSnapshots(in appRoot: String) async {
        do {
            let result = try await ddevService.listSnapshots(in: appRoot)
            snapshots = DDEVSnapshot.parseListOutput(result.stdout)
            snapshotErrorMessage = nil
        } catch {
            // Snapshot-scoped surface, not the list-level global banner (audit M10).
            snapshotErrorMessage = error.presentableMessage
        }
    }

    private func refreshInstalledAddOns(in appRoot: String, projectName: String) async {
        do {
            let result = try await ddevService.listInstalledAddOns(projectName: projectName, in: appRoot)
            installedAddOns = try DDEVAddon.parseListOutput(result.stdout)
            addonRawOutput = installedAddOns.isEmpty ? result.stdout.nilIfBlank : nil
        } catch {
            addonErrorMessage = error.presentableMessage
        }
    }

    private func refreshProjectsFromDDEV() async throws {
        // Single in-flight guard so overlapping refreshes (e.g. the cache-warm background
        // refresh racing a mutation-triggered full refresh) don't stack two listProjects +
        // N-project describe fan-outs at once (audit M4).
        guard !isRefreshInFlight else { return }
        isRefreshInFlight = true
        defer { isRefreshInFlight = false }

        let loadedProjects = try await ddevService.listProjects()
        let enrichedProjects = await enrichProjectsWithDetails(loadedProjects)
        applyProjects(enrichedProjects)
        try? await projectCache.saveProjects(enrichedProjects)
    }

    private func refreshProjectsFromDDEVInBackground() async {
        do {
            try await refreshProjectsFromDDEV()
        } catch {
            return
        }
    }

    private func loadCachedProjects() async -> Bool {
        guard projects.isEmpty else { return false }
        guard let cachedProjects = try? await projectCache.loadProjects(), !cachedProjects.isEmpty else { return false }

        applyProjects(cachedProjects)
        return true
    }

    private func applyProjects(_ projects: [DDEVProject]) {
        self.projects = projects

        // Drop per-project command state for projects that have vanished from the list so the
        // dictionary can't grow unbounded over a long session with project churn (audit M2).
        // Busy entries are kept so an in-flight command that briefly drops from the list isn't lost.
        let liveIDs = Set(projects.map(\.id))
        commandStates = commandStates.filter { liveIDs.contains($0.key) || $0.value.isBusy }

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
        // Each describe is an independent subprocess; running them in parallel turns an
        // O(N × describe-latency) freeze into roughly O(slowest-describe). Bounded to
        // maxConcurrentDescribes so a large workspace can't put N blocking describes in
        // flight at once and pressure the global dispatch pool (audit M1).
        let ddevService = self.ddevService
        return await concurrentMap(projects, limit: Self.maxConcurrentDescribes) { project in
            do {
                let details = try await ddevService.describe(projectName: project.name)
                return project.applying(details: details)
            } catch {
                return project
            }
        }
    }

    /// Cap on concurrent `describe` subprocesses during a refresh fan-out (audit M1).
    private static let maxConcurrentDescribes = 4
}

private struct DiagnosticFailure: Error {
    let check: DDEVDiagnosticCheck
    let result: CommandResult?
    let underlying: Error
}
