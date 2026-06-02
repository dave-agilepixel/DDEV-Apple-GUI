import Foundation
import Observation

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
    func applyConfigChange(_ change: DDEVConfigChange, in appRoot: String) async throws -> CommandResult
    func runProjectCommand(arguments: [String], in appRoot: String) async throws -> CommandResult
    func version() async throws -> CommandResult
    func utilityDiagnose(in appRoot: String?) async throws -> CommandResult
    func utilityConfigYAML(omitKeys: [String], in appRoot: String) async throws -> CommandResult
    func utilityCheckCustomConfig(in appRoot: String) async throws -> CommandResult
    func utilityCheckDBMatch(in appRoot: String) async throws -> CommandResult
    func mutagen(_ command: DDEVMutagenCommand, in appRoot: String) async throws -> CommandResult
    func xhgui(_ command: DDEVXHGuiCommand, in appRoot: String) async throws -> CommandResult
    func xdebug(_ command: DDEVXdebugCommand, in appRoot: String) async throws -> CommandResult
    func updateWordPressCore(in appRoot: String) async throws -> CommandResult
    func updateWordPressPlugins(in appRoot: String) async throws -> CommandResult
    func updateWordPressThemes(in appRoot: String) async throws -> CommandResult
    func start(projectName: String, onOutputLine: (@Sendable (String) -> Void)?) async throws -> CommandResult
    func restart(projectName: String, onOutputLine: (@Sendable (String) -> Void)?) async throws -> CommandResult
}

public extension DDEVServicing {
    func start(projectName: String, onOutputLine: (@Sendable (String) -> Void)?) async throws -> CommandResult {
        try await start(projectName: projectName)
    }
    func restart(projectName: String, onOutputLine: (@Sendable (String) -> Void)?) async throws -> CommandResult {
        try await restart(projectName: projectName)
    }
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

public enum SidebarSelection: Hashable, Sendable {
    case library(ProjectSidebarItem)
    case group(ProjectGroup.ID)
}

@MainActor
@Observable
public final class ProjectDashboardViewModel {
    public var projects: [DDEVProject] = []
    /// User-authored project groups (folders). Sidebar display order == array order.
    public var groups: [ProjectGroup] = []
    /// Selected group, when a group (not a Library item) is the active sidebar selection.
    public var selectedGroupID: ProjectGroup.ID?
    public var selectedProjectID: DDEVProject.ID?
    public var selectedSidebarItem: ProjectSidebarItem = .projects
    public var searchText = ""

    /// Per-project command state, keyed by project id (the project name). The single source
    /// of truth for busy/queued lifecycle, last result, error, history, and output expansion.
    public var commandStates: [DDEVProject.ID: ProjectCommandState] = [:]

    /// Live `ddev describe -j` detail for the *selected* project — Xdebug state, DB credentials,
    /// per-service health/ports. Deliberately not merged into the cached `DDEVProject` (it carries
    /// the DB password and ephemeral ports), so it lives here, refetched per selection.
    public var selectedProjectDetails: DDEVProjectDetails?

    /// Set when `ddev utility check-db-match` reports the on-disk DB volume disagrees with the
    /// configured type/version, so the inspector can surface an ambient drift warning (A5).
    public var dbMatchWarning: String?

    /// Live Xdebug on/off state for the selected running project, sourced from `ddev xdebug status`.
    /// NOTE: `describe -j`'s `xdebug_enabled` reflects the *configured* value (config.yaml), not the
    /// runtime state toggled by `ddev xdebug on/off`, so the live toggle must not bind to it.
    /// `nil` when unknown (project not running, or status not yet loaded).
    public var selectedProjectXdebugEnabled: Bool?

    /// Busy/error for genuinely project-less operations: global list refresh, global
    /// diagnostics, and new-project creation (which has no project id yet).
    public var isRunningGlobalCommand = false
    public var globalErrorMessage: String?
    public var snapshots: [DDEVSnapshot] = []
    public var snapshotErrorMessage: String?
    public var projectLogsResult: CommandResult?
    public var projectLogsErrorMessage: String?
    public var projectConfig: DDEVConfig?
    public var projectConfigErrorMessage: String?
    public var projectConfigRestartRecommended = false
    public var installedAddOns: [DDEVAddon] = []
    public var addonSearchResults: [DDEVAddon] = DDEVAddon.recommendedOfficial
    public var addonErrorMessage: String?
    public var addOnRestartRecommended = false
    public var addonRawOutput: String?
    public var diagnosticReport = DDEVDiagnosticReport()
    public var diagnosticsErrorMessage: String?

    /// Preferences + installed-app concern, extracted to its own model (audit M9). The public
    /// API below forwards to it so views/tests are unchanged; both are `@Observable`, so views
    /// reading the forwarders still track the underlying changes.
    @ObservationIgnored private let preferencesModel: PreferencesModel

    public let supportedPHPVersions = ["8.4", "8.3", "8.2", "8.1", "8.0", "7.4"]

    private let ddevService: DDEVServicing
    private let projectCache: ProjectCacheStoring
    private let groupStore: ProjectGroupStoring
    private let scheduler: CommandScheduler
    private let notifier: NotificationScheduling
    private var selectedProjectFallback: DDEVProject?
    /// Guards `refreshProjectsFromDDEV` against overlapping runs (audit M4). Internal
    /// serialization only — `isRunningGlobalCommand` is what drives the UI spinner.
    private var isRefreshInFlight = false

    public init(
        ddevService: DDEVServicing = DDEVCommandService(),
        projectCache: ProjectCacheStoring = FileProjectCacheStore(),
        preferencesStore: AppPreferencesStoring = UserDefaultsAppPreferencesStore(),
        appAvailability: AppAvailabilityChecking = WorkspaceAppAvailabilityService(),
        scheduler: CommandScheduler = CommandScheduler(maxConcurrent: 3),
        notifier: NotificationScheduling = NoopNotificationScheduler(),
        groupStore: ProjectGroupStoring = UserDefaultsProjectGroupStore()
    ) {
        self.ddevService = ddevService
        self.projectCache = projectCache
        self.scheduler = scheduler
        self.notifier = notifier
        self.preferencesModel = PreferencesModel(preferencesStore: preferencesStore, appAvailability: appAvailability)
        self.groupStore = groupStore
        self.groups = groupStore.loadGroups()
    }

    // MARK: - Preferences (forwarded to PreferencesModel)

    public var preferences: AppPreferences { preferencesModel.preferences }
    public var installedEditors: [EditorChoice] { preferencesModel.installedEditors }
    public var installedDatabaseTools: [DDEVDatabaseTool] { preferencesModel.installedDatabaseTools }

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

    /// Unified sidebar selection. `.group` wins when a still-existing group is selected, else the
    /// Library item. Setting `.library` clears the group selection.
    public var selection: SidebarSelection {
        get {
            if let selectedGroupID, groups.contains(where: { $0.id == selectedGroupID }) {
                return .group(selectedGroupID)
            }
            return .library(selectedSidebarItem)
        }
        set {
            switch newValue {
            case .library(let item):
                selectedSidebarItem = item
                selectedGroupID = nil
            case .group(let id):
                selectedGroupID = id
            }
        }
    }

    /// Title for the middle column / nav bar: the selected group's name when a group is active,
    /// otherwise the Library item's title.
    public var currentSectionTitle: String {
        if case .group(let id) = selection, let group = groups.first(where: { $0.id == id }) {
            return group.name
        }
        return selectedSidebarItem.title
    }

    public var filteredProjects: [DDEVProject] {
        filteredProjects(in: projects)
    }

    /// Projects whose name or path matches `query` (case-insensitive), across *all* sections — backs
    /// the ⌘K quick switcher (B6). An empty query returns everything, name-sorted.
    public func projectsMatching(_ query: String) -> [DDEVProject] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let pool = projects.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        guard !trimmed.isEmpty else { return pool }
        return pool.filter {
            $0.name.localizedCaseInsensitiveContains(trimmed)
                || $0.shortRoot.localizedCaseInsensitiveContains(trimmed)
        }
    }

    /// Jumps to the Projects section and selects `id` — used by the quick switcher so the picked
    /// project is both selected and visible regardless of the current section/group filter (B6).
    public func revealAndSelectProject(_ id: DDEVProject.ID) {
        selectedGroupID = nil
        selectedSidebarItem = .projects
        selectedProjectID = id
    }

    public var availableEditors: [EditorChoice] { preferencesModel.availableEditors }
    public var availableDatabaseTools: [DDEVDatabaseTool] { preferencesModel.availableDatabaseTools }
    public var effectiveDefaultEditor: EditorChoice { preferencesModel.effectiveDefaultEditor }
    public var effectiveDefaultDatabaseTool: DDEVDatabaseTool? { preferencesModel.effectiveDefaultDatabaseTool }

    public var copyableDiagnosticOutput: String {
        diagnosticReport.copyableOutput
    }

    private func filteredProjects(in sourceProjects: [DDEVProject]) -> [DDEVProject] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let sectionProjects: [DDEVProject]
        if let selectedGroupID, let group = groups.first(where: { $0.id == selectedGroupID }) {
            let memberSet = Set(group.memberIDs)
            sectionProjects = sourceProjects.filter { memberSet.contains($0.id) }
        } else {
            sectionProjects = sourceProjects.filter { project in
                switch selectedSidebarItem {
                case .projects: true
                case .running: project.status == .running
                case .wordpress: project.isWordPress
                case .diagnostics: false
                case .settings: false
                }
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
        preferencesModel.setDefaultEditor(editor)
    }

    public func setDefaultDatabaseTool(_ databaseTool: DDEVDatabaseTool?) {
        preferencesModel.setDefaultDatabaseTool(databaseTool)
    }

    public func refreshInstalledApps() {
        preferencesModel.refreshInstalledApps()
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
        do {
            try await scheduler.acquire()
        } catch {
            setActivity(.idle, for: id) // cancelled while queued (audit L4)
            return
        }
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
        await runProgressMutation(project) { onLine in
            try await self.ddevService.start(projectName: project.name, onOutputLine: onLine)
        }
    }

    public func stop(_ project: DDEVProject) async {
        await runProjectMutation(project) {
            try await self.ddevService.stop(projectName: project.name)
        }
    }

    public func restart(_ project: DDEVProject) async {
        await runProgressMutation(project) { onLine in
            try await self.ddevService.restart(projectName: project.name, onOutputLine: onLine)
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
        isRunningGlobalCommand = true
        globalErrorMessage = nil
        defer { isRunningGlobalCommand = false }

        // 1. Configure. A failure here means nothing was registered — surface it and stop.
        do {
            _ = try await ddevService.configureProject(in: folder, name: name, type: type, docroot: docroot)
        } catch CommandRunnerError.nonZeroExit(let result) {
            let detail = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            globalErrorMessage = detail.isEmpty
                ? "Command failed with exit code \(result.exitCode)."
                : "Configuration failed: \(detail)"
            return
        } catch {
            globalErrorMessage = error.presentableMessage
            return
        }

        // 2. Auto-start the freshly-configured project. A start failure must NOT roll back the
        //    registration (the project is legitimately configured), so we record the error but
        //    still fall through to the refresh below.
        do {
            _ = try await ddevService.startProject(in: folder)
        } catch CommandRunnerError.nonZeroExit(let result) {
            let detail = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            globalErrorMessage = detail.isEmpty
                ? "Project configured, but start failed (exit code \(result.exitCode))."
                : "Project configured, but start failed: \(detail)"
        } catch {
            globalErrorMessage = "Project configured, but start failed: \(error.presentableMessage)"
        }

        // 3. Refresh regardless of start outcome so the new project always appears in the list.
        do { try await refreshProjectsFromDDEV() } catch { /* keep any start-failure message */ }
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

    /// Fetches the rich describe detail for the selected project (Xdebug state, DB info, services).
    /// Best-effort and quiet: a describe failure just leaves the panels empty rather than surfacing
    /// an error, matching how list-refresh enrichment tolerates per-project describe failures.
    public func loadDetailsForSelectedProject() async {
        guard let selectedProject else { return }
        // Clear stale detail from the previously-selected project so panels don't show wrong data
        // during the fetch.
        selectedProjectDetails = nil
        await refreshDetails(for: selectedProject)
    }

    /// Reads the *live* Xdebug state for the selected running project via `ddev xdebug status`
    /// (the authoritative runtime source — describe's `xdebug_enabled` is only the config default).
    public func loadXdebugStatusForSelectedProject() async {
        guard let selectedProject, selectedProject.status == .running else {
            selectedProjectXdebugEnabled = nil
            return
        }
        let targetID = selectedProject.id
        selectedProjectXdebugEnabled = nil
        guard let result = try? await ddevService.xdebug(.status, in: selectedProject.appRoot) else { return }
        guard selectedProjectID == targetID else { return } // selection moved on
        selectedProjectXdebugEnabled = Self.parseXdebugEnabled(result.stdout)
    }

    /// Live Xdebug on/off toggle (A2). Flips Xdebug on the running web container without a restart.
    /// Optimistically reflects the requested state, then reconciles against `ddev xdebug status`
    /// — NOT describe, whose `xdebug_enabled` reports the config default and would snap the toggle back.
    public func setXdebugForSelectedProject(_ enabled: Bool) async {
        guard let selectedProject else { return }
        selectedProjectXdebugEnabled = enabled // optimistic; reconciled below
        await runProjectMutation(selectedProject, refresh: .none) {
            let result = try await self.ddevService.xdebug(enabled ? .on : .off, in: selectedProject.appRoot)
            if let status = try? await self.ddevService.xdebug(.status, in: selectedProject.appRoot),
               self.selectedProjectID == selectedProject.id {
                self.selectedProjectXdebugEnabled = Self.parseXdebugEnabled(status.stdout) ?? enabled
            }
            return result
        }
    }

    /// Parses `ddev xdebug status` output ("xdebug enabled" / "xdebug disabled") into a Bool.
    /// `disabled` is checked first because it must not match the `enabled` branch.
    private static func parseXdebugEnabled(_ output: String) -> Bool? {
        let lower = output.lowercased()
        if lower.contains("disabled") { return false }
        if lower.contains("enabled") { return true }
        return nil
    }

    /// Runs `ddev utility check-db-match` for the selected project and, on a mismatch, populates
    /// `dbMatchWarning` so the inspector can show an ambient drift banner (A5). Only runs for a
    /// running project — a stopped DB can't be inspected, and we'd rather stay silent than cry wolf.
    public func checkDBMatchForSelectedProject() async {
        guard let selectedProject, selectedProject.status == .running else {
            dbMatchWarning = nil
            return
        }
        let targetID = selectedProject.id
        dbMatchWarning = nil
        do {
            _ = try await ddevService.utilityCheckDBMatch(in: selectedProject.appRoot)
            // Exit 0 → the volume matches the configured database; nothing to warn about.
        } catch CommandRunnerError.nonZeroExit(let result) {
            guard selectedProjectID == targetID else { return } // selection moved on mid-check
            dbMatchWarning = Self.dbMatchMessage(from: result)
        } catch {
            // Couldn't run the check (e.g. DB container not up yet). Don't show a scary banner for
            // a non-drift failure.
        }
    }

    /// Distils a concise, user-facing line from a failed check-db-match result.
    private static func dbMatchMessage(from result: CommandResult) -> String {
        let firstMeaningfulLine: (String) -> String? = { text in
            text.split(separator: "\n", omittingEmptySubsequences: true)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .first { !$0.isEmpty }
        }
        return firstMeaningfulLine(result.stderr)
            ?? firstMeaningfulLine(result.stdout)
            ?? "The database volume does not match the configured database type/version."
    }

    public func moveSelectedProjectFolderToTrash() {
        guard let selectedProject else { return }

        // The appRoot can originate from the on-disk cache, so don't trust it as the authority
        // for a destructive op (audit S1). Refuse anything that doesn't resolve to a strict
        // subpath of the user's home directory before handing it to the Trash.
        let resolvedPath = URL(fileURLWithPath: selectedProject.appRoot).standardizedFileURL.path
        let home = URL(fileURLWithPath: NSHomeDirectory()).standardizedFileURL.path
        guard resolvedPath.hasPrefix(home + "/") else {
            globalErrorMessage = "Refusing to move \"\(resolvedPath)\" to the Trash: it is outside your home directory."
            return
        }

        do {
            try FileManager.default.trashItem(
                at: URL(fileURLWithPath: resolvedPath),
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
        do {
            try await scheduler.acquire()      // resumes on MainActor
        } catch {
            setActivity(.idle, for: id)        // cancelled while queued (audit L4)
            return
        }
        setActivity(.running, for: id)

        let outcome = await execute(operation)
        await scheduler.release()              // free the slot before the read-y describe
        setActivity(.idle, for: id)

        await finish(outcome, for: project, refresh: refresh)
    }

    /// Like `runProjectMutation`, but streams the command's output lines through a
    /// `StartProgressParser` to publish a determinate `startProgress` for the row donut. Lines are
    /// marshalled onto the main actor via an `AsyncStream`, so `commandStates` is only mutated here.
    /// Progress clears back to `nil` when the command finishes (success or failure).
    private func runProgressMutation(
        _ project: DDEVProject,
        refresh: RefreshScope = .project,
        _ operation: @escaping (_ onLine: @escaping @Sendable (String) -> Void) async throws -> CommandResult
    ) async {
        let id = project.id
        guard !isBusy(project) else { return }

        setActivity(.queued, for: id)
        do { try await scheduler.acquire() } catch { setActivity(.idle, for: id); return }
        setActivity(.running, for: id)

        let (stream, continuation) = AsyncStream<String>.makeStream()
        let consumer = Task { @MainActor in
            var parser = StartProgressParser()
            for await line in stream {
                if let fraction = parser.consume(line) {
                    commandStates[id, default: .init()].startProgress = fraction
                }
            }
        }

        let outcome = await execute { try await operation { line in continuation.yield(line) } }
        continuation.finish()
        await consumer.value

        commandStates[id, default: .init()].startProgress = nil  // clear the donut
        await scheduler.release()
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

    /// Re-fetch the live describe detail for `project` and publish it as `selectedProjectDetails`,
    /// unless the selection moved on while the describe was in flight.
    private func refreshDetails(for project: DDEVProject) async {
        guard let details = try? await ddevService.describe(projectName: project.name) else { return }
        guard selectedProjectID == project.id else { return }
        selectedProjectDetails = details
    }

    /// Re-describe a single project and patch it into `projects` in place.
    private func reDescribe(_ project: DDEVProject) async {
        guard let refreshed = try? await ddevService.describe(projectName: project.name) else { return }
        guard let index = projects.firstIndex(where: { $0.id == project.id }) else { return }
        projects[index] = projects[index].applying(details: refreshed)
        if selectedProjectFallback?.id == project.id {
            selectedProjectFallback = projects[index]
        }
        // Refresh the inspector's live overview (services/DB) for the selected project from the
        // SAME describe — no second subprocess. Guarded so a stale describe can't overwrite a
        // newer selection's detail.
        if selectedProjectID == project.id {
            selectedProjectDetails = refreshed
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

        // Drop group memberships for projects that no longer exist so counts/filters stay honest.
        var didPruneGroups = false
        for index in groups.indices {
            let kept = groups[index].memberIDs.filter { liveIDs.contains($0) }
            if kept.count != groups[index].memberIDs.count {
                groups[index].memberIDs = kept
                didPruneGroups = true
            }
        }
        if didPruneGroups { persistGroups() }

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

    // MARK: - Groups

    @discardableResult
    public func createGroup(name: String, color: GroupColor) -> ProjectGroup.ID? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let group = ProjectGroup(name: trimmed, colorID: color)
        groups.append(group)
        persistGroups()
        return group.id
    }

    public func renameGroup(_ id: ProjectGroup.ID, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let index = groups.firstIndex(where: { $0.id == id }) else { return }
        groups[index].name = trimmed
        persistGroups()
    }

    public func setColor(_ color: GroupColor, for id: ProjectGroup.ID) {
        guard let index = groups.firstIndex(where: { $0.id == id }) else { return }
        groups[index].colorID = color
        persistGroups()
    }

    public func deleteGroup(_ id: ProjectGroup.ID) {
        groups.removeAll { $0.id == id }
        if selectedGroupID == id { selectedGroupID = nil }
        persistGroups()
    }

    public func assignProject(_ projectID: DDEVProject.ID, toGroup groupID: ProjectGroup.ID) {
        // Single-membership: remove from every group first, then add to the target.
        for index in groups.indices {
            groups[index].memberIDs.removeAll { $0 == projectID }
        }
        guard let target = groups.firstIndex(where: { $0.id == groupID }) else { persistGroups(); return }
        groups[target].memberIDs.append(projectID)
        persistGroups()
    }

    public func removeProjectFromGroup(_ projectID: DDEVProject.ID) {
        for index in groups.indices {
            groups[index].memberIDs.removeAll { $0 == projectID }
        }
        persistGroups()
    }

    public func group(for projectID: DDEVProject.ID) -> ProjectGroup? {
        groups.first { $0.memberIDs.contains(projectID) }
    }

    public func memberCount(of groupID: ProjectGroup.ID) -> Int {
        guard let group = groups.first(where: { $0.id == groupID }) else { return 0 }
        let liveIDs = Set(projects.map(\.id))
        return group.memberIDs.filter { liveIDs.contains($0) }.count
    }

    public func moveGroups(fromOffsets source: IndexSet, toOffset destination: Int) {
        groups.move(fromOffsets: source, toOffset: destination)
        persistGroups()
    }

    private func persistGroups() {
        groupStore.saveGroups(groups)
    }
}

private struct DiagnosticFailure: Error {
    let check: DDEVDiagnosticCheck
    let result: CommandResult?
    let underlying: Error
}
