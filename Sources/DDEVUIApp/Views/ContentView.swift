import SwiftUI

struct ContentView: View {
    @State private var viewModel: ProjectDashboardViewModel
    @State private var prerequisites: PrerequisiteMonitor
    @State private var folderToConfigure: FolderToConfigure?
    @State private var showNewGroupEditor = false
    @State private var groupToEdit: ProjectGroup?
    /// The group row a project is currently being dragged over, for drop-target highlighting.
    @State private var dropTargetGroupID: ProjectGroup.ID?
    @State private var showQuickSwitcher = false
    @Environment(\.scenePhase) private var scenePhase

    init() {
        _viewModel = State(initialValue: ProjectDashboardViewModel(notifier: ContentView.makeNotifier()))
        _prerequisites = State(initialValue: PrerequisiteMonitor())
    }

    /// Injecting initializer for previews/tests, so they can pass stub services instead of the
    /// real ones that spawn ddev/docker subprocesses and start the poll loop (audit L12).
    init(viewModel: ProjectDashboardViewModel, prerequisites: PrerequisiteMonitor) {
        _viewModel = State(initialValue: viewModel)
        _prerequisites = State(initialValue: prerequisites)
    }

    private static func makeNotifier() -> NotificationScheduling {
        let scheduler = UserNotificationScheduler()
        scheduler.activateForegroundPresentation()
        return scheduler
    }

    var body: some View {
        NavigationSplitView {
            List(selection: sidebarSelection) {
                Section("Library") {
                    ForEach(ProjectSidebarItem.allCases) { item in
                        SidebarRow(item: item, count: count(for: item))
                            .tag(SidebarSelection.library(item))
                    }
                }
                if !viewModel.groups.isEmpty {
                    Section("Groups") {
                        ForEach(viewModel.groups) { group in
                            GroupSidebarRow(group: group, count: viewModel.memberCount(of: group.id))
                                .tag(SidebarSelection.group(group.id))
                                .contextMenu { groupContextMenu(group) }
                                .listRowBackground(
                                    dropTargetGroupID == group.id
                                        ? RoundedRectangle(cornerRadius: 6).fill(.tint.opacity(0.25))
                                        : nil
                                )
                                .dropDestination(for: String.self) { droppedIDs, _ in
                                    // Drag payload is a project id (a plain String). Filter to ids we
                                    // actually know so a stray text drag can't create a phantom member.
                                    let knownIDs = droppedIDs.filter { id in
                                        viewModel.projects.contains { $0.id == id }
                                    }
                                    for id in knownIDs { viewModel.assignProject(id, toGroup: group.id) }
                                    return !knownIDs.isEmpty
                                } isTargeted: { targeted in
                                    dropTargetGroupID = targeted ? group.id : (dropTargetGroupID == group.id ? nil : dropTargetGroupID)
                                }
                        }
                        .onMove { viewModel.moveGroups(fromOffsets: $0, toOffset: $1) }
                    }
                }
                Section {
                    Button {
                        showNewGroupEditor = true
                    } label: {
                        Label("New Group", systemImage: "plus")
                    }
                    .buttonStyle(.plain)
                    .popover(isPresented: $showNewGroupEditor, arrowEdge: .trailing) {
                        NewGroupEditor(viewModel: viewModel) { showNewGroupEditor = false }
                    }
                }
            }
            .listStyle(.sidebar)
            .navigationTitle("DDEVUI")
            .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 240)
        } content: {
            switch viewModel.selection {
            case .library(.settings):
                SettingsView(viewModel: viewModel)
            case .library(.diagnostics):
                DiagnosticsView(viewModel: viewModel)
                    .navigationSplitViewColumnWidth(min: 480, ideal: 680)
            default:
                ProjectListView(viewModel: viewModel)
                    .navigationSplitViewColumnWidth(min: 280, ideal: 320, max: 420)
            }
        } detail: {
            if case .library(.diagnostics) = viewModel.selection {
                ContentUnavailableView(
                    "Diagnostics",
                    systemImage: "stethoscope",
                    description: Text("Run global checks or select a project before opening Diagnostics for project-specific checks.")
                )
                .navigationSplitViewColumnWidth(min: 360, ideal: 420)
            } else {
                ProjectInspectorView(viewModel: viewModel)
                    .navigationSplitViewColumnWidth(min: 540, ideal: 720)
            }
        }
        .task {
            await viewModel.requestNotificationAuthorization()
            await viewModel.loadCachedProjectsThenRefresh()
        }
        .toolbar {
            ToolbarItemGroup {
                Button {
                    addFolder()
                } label: {
                    Label("Add Folder", systemImage: "folder.badge.plus")
                }
                .help("Register an existing folder as a DDEV project")

                Button {
                    Task { await viewModel.refresh() }
                } label: {
                    if viewModel.isRunningGlobalCommand {
                        ProgressView().controlSize(.small)
                    } else {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                }
                .help("Reload DDEV project list")
                .disabled(viewModel.isRunningGlobalCommand)

                Button {
                    showQuickSwitcher = true
                } label: {
                    Label("Quick Switcher", systemImage: "command")
                }
                .help("Jump to a project (⌘K)")
                .keyboardShortcut("k", modifiers: .command)
                .disabled(viewModel.projects.isEmpty)
            }
        }
        .sheet(isPresented: $showQuickSwitcher) {
            QuickSwitcherView(viewModel: viewModel)
        }
        .sheet(item: $folderToConfigure) { folder in
            AddProjectSheet(folder: folder.url, viewModel: viewModel)
        }
        .sheet(item: $groupToEdit) { group in
            EditGroupSheet(viewModel: viewModel, group: group)
        }
        .sheet(isPresented: Binding(
            get: { prerequisites.shouldBlockUI },
            set: { _ in }
        )) {
            PrerequisiteSheet(monitor: prerequisites)
                .interactiveDismissDisabled()
        }
        .task {
            prerequisites.start()
            viewModel.startStatusPolling()
        }
        .onChange(of: scenePhase) { _, phase in
            // Pause the prerequisite + status polls while backgrounded; re-arm on return (B2 — the
            // poll loops have a clean off-switch, so they never run unattended in the background).
            if phase == .active {
                prerequisites.start()
                viewModel.startStatusPolling()
            } else {
                prerequisites.stop()
                viewModel.stopStatusPolling()
            }
        }
    }

    private func count(for item: ProjectSidebarItem) -> Int? {
        switch item {
        case .projects: viewModel.projects.count
        case .running: viewModel.projects.filter { $0.status == .running }.count
        case .wordpress: viewModel.projects.filter { $0.isWordPress }.count
        case .diagnostics: nil
        case .settings: nil
        }
    }

    private var sidebarSelection: Binding<SidebarSelection?> {
        Binding {
            viewModel.selection
        } set: { newSelection in
            guard let newSelection, viewModel.selection != newSelection else { return }
            viewModel.selection = newSelection
        }
    }

    @ViewBuilder
    private func groupContextMenu(_ group: ProjectGroup) -> some View {
        Button("Edit Group…") { groupToEdit = group }
        Divider()
        Button("Delete Group", role: .destructive) { viewModel.deleteGroup(group.id) }
    }

    private func addFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false

        // Non-blocking begin{} (completion on the main queue) rather than runModal(), which
        // blocks the run loop and mixes AppKit modality into the view (audit L14b).
        panel.begin { response in
            guard response == .OK, let folder = panel.url else { return }

            let configPath = folder
                .appendingPathComponent(".ddev")
                .appendingPathComponent("config.yaml")
                .path

            if FileManager.default.fileExists(atPath: configPath) {
                Task { await viewModel.startProject(atFolder: folder.path) }
            } else {
                folderToConfigure = FolderToConfigure(url: folder)
            }
        }
    }
}

private struct SidebarRow: View {
    let item: ProjectSidebarItem
    let count: Int?

    var body: some View {
        HStack {
            Label(item.title, systemImage: item.systemImage)
            Spacer()
            if let count, count > 0 {
                Text("\(count)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .background(
                        Capsule().fill(.quaternary.opacity(0.6))
                    )
            }
        }
    }
}

private struct FolderToConfigure: Identifiable {
    let url: URL
    var id: String { url.path }
}

#Preview {
    ContentView(
        viewModel: ProjectDashboardViewModel(
            ddevService: DDEVCommandService(commandRunner: PreviewCommandRunner())
        ),
        prerequisites: PrerequisiteMonitor(
            service: StaticPrerequisiteService(
                state: PrerequisiteState(docker: .ok, ddev: .ok(version: "v1.24.0"))
            )
        )
    )
}

/// Returns an empty project list and never shells out, so previews don't spawn real
/// ddev/docker subprocesses (audit L12).
private struct PreviewCommandRunner: CommandRunning {
    func run(_ spec: CommandSpec) async throws -> CommandResult {
        .success(stdout: "[]")
    }
}

private struct SettingsView: View {
    var viewModel: ProjectDashboardViewModel
    @State private var confirmPowerOff = false
    @State private var confirmDeleteImages = false

    var body: some View {
        Form {
            Section("Overview") {
                LabeledContent("Projects") {
                    Text("\(viewModel.projects.count)").monospacedDigit()
                }
                LabeledContent("Running") {
                    Text("\(viewModel.projects.filter { $0.status == .running }.count)")
                        .monospacedDigit()
                        .foregroundStyle(.green)
                }
                LabeledContent("WordPress") {
                    Text("\(viewModel.projects.filter { $0.isWordPress }.count)").monospacedDigit()
                }
            }

            Section("Defaults") {
                Picker("Open projects in", selection: Binding(
                    get: { viewModel.effectiveDefaultEditor },
                    set: { viewModel.setDefaultEditor($0) }
                )) {
                    ForEach(viewModel.availableEditors) { editor in
                        Text(editor.displayName).tag(editor)
                    }
                }

                if viewModel.effectiveDefaultDatabaseTool != nil {
                    Picker("Open databases in", selection: Binding<DDEVDatabaseTool?>(
                        get: { viewModel.effectiveDefaultDatabaseTool },
                        set: { viewModel.setDefaultDatabaseTool($0) }
                    )) {
                        ForEach(viewModel.availableDatabaseTools) { tool in
                            Text(tool.displayName).tag(Optional(tool))
                        }
                    }
                } else {
                    LabeledContent("Open databases in") {
                        Text("No supported database apps installed")
                            .foregroundStyle(.secondary)
                    }
                }
            }

            // A15 — global housekeeping that isn't tied to a single project.
            Section("Maintenance") {
                Button {
                    Task { await viewModel.downloadDDEVImages() }
                } label: {
                    Label("Download Images", systemImage: "arrow.down.circle")
                }
                .help("Pre-pull every image DDEV needs (ddev utility download-images)")

                Button {
                    confirmPowerOff = true
                } label: {
                    Label("Power Off All Projects", systemImage: "power")
                }
                .help("Stop all running projects and shared containers (ddev poweroff)")

                Button(role: .destructive) {
                    confirmDeleteImages = true
                } label: {
                    Label("Delete DDEV Images", systemImage: "trash")
                }
                .help("Remove DDEV Docker images to reclaim disk (ddev delete images)")

                if viewModel.isRunningGlobalCommand {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("Running…").foregroundStyle(.secondary)
                    }
                }

                if let message = viewModel.globalErrorMessage {
                    Label(message, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .font(.callout)
                }
            }
            .disabled(viewModel.isRunningGlobalCommand)

            GlobalConfigSection(viewModel: viewModel)
        }
        .formStyle(.grouped)
        .navigationTitle("Settings")
        .onAppear {
            viewModel.refreshInstalledApps()
        }
        .confirmationDialog("Power off all projects?", isPresented: $confirmPowerOff) {
            Button("Power Off All", role: .destructive) {
                Task { await viewModel.powerOffAllProjects() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Stops every running DDEV project and the shared containers (ddev poweroff).")
        }
        .confirmationDialog("Delete DDEV images?", isPresented: $confirmDeleteImages) {
            Button("Delete Images", role: .destructive) {
                Task { await viewModel.deleteDDEVImages() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Removes DDEV's Docker images to reclaim disk. They're re-downloaded on next start — no project data is lost.")
        }
    }
}

/// A14 — editable global DDEV configuration, surfaced as a Settings section. A curated set of the
/// most common `ddev config global` flags as controls; the long tail stays in global_config.yaml,
/// openable in the editor (B8-style). Loads on appear, seeds local edit state, applies on Save.
private struct GlobalConfigSection: View {
    var viewModel: ProjectDashboardViewModel

    @State private var instrumentationOptIn = true
    @State private var performanceMode = "mutagen"
    @State private var xhprofMode = "xhgui"
    @State private var routerHTTPPort = ""
    @State private var routerHTTPSPort = ""
    @State private var mailpitHTTPPort = ""
    @State private var mailpitHTTPSPort = ""
    @State private var projectTLD = ""
    @State private var seeded = false

    private let workspaceOpener = MacWorkspaceOpener()

    var body: some View {
        Section("Global DDEV Configuration") {
            if viewModel.globalConfig == nil {
                if let message = viewModel.globalConfigErrorMessage {
                    Label(message, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .font(.callout)
                } else {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("Loading…").foregroundStyle(.secondary)
                    }
                }
            } else {
                Toggle("Send anonymous usage data", isOn: $instrumentationOptIn)
                Picker("Performance mode", selection: $performanceMode) {
                    Text("Mutagen").tag("mutagen")
                    Text("None").tag("none")
                }
                Picker("XHProf mode", selection: $xhprofMode) {
                    Text("XHGui").tag("xhgui")
                    Text("Prepend").tag("prepend")
                }
                TextField("Router HTTP port", text: $routerHTTPPort)
                TextField("Router HTTPS port", text: $routerHTTPSPort)
                TextField("Mailpit HTTP port", text: $mailpitHTTPPort)
                TextField("Mailpit HTTPS port", text: $mailpitHTTPSPort)
                TextField("Project TLD", text: $projectTLD)

                if let message = viewModel.globalConfigErrorMessage {
                    Label(message, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .font(.callout)
                }

                HStack {
                    Button("Open global_config.yaml") {
                        workspaceOpener.openFile(globalConfigPath, editor: viewModel.effectiveDefaultEditor)
                    }
                    Spacer()
                    Button("Save Global Config") { save() }
                        .buttonStyle(.borderedProminent)
                        .disabled(viewModel.isRunningGlobalCommand)
                }
            }
        }
        .task {
            await viewModel.loadGlobalConfig()
            seedFromConfig()
        }
        .onChange(of: viewModel.globalConfig) { _, _ in seedFromConfig() }
    }

    private var globalConfigPath: String {
        (NSHomeDirectory() as NSString).appendingPathComponent(".ddev/global_config.yaml")
    }

    private func seedFromConfig() {
        guard let config = viewModel.globalConfig, !seeded else { return }
        instrumentationOptIn = config.instrumentationOptIn
        performanceMode = config.performanceMode
        xhprofMode = config.xhprofMode
        routerHTTPPort = config.routerHTTPPort
        routerHTTPSPort = config.routerHTTPSPort
        mailpitHTTPPort = config.mailpitHTTPPort
        mailpitHTTPSPort = config.mailpitHTTPSPort
        projectTLD = config.projectTLD
        seeded = true
    }

    private func save() {
        let changes: [DDEVGlobalConfigChange] = [
            .instrumentationOptIn(instrumentationOptIn),
            .performanceMode(performanceMode),
            .xhprofMode(xhprofMode),
            .routerHTTPPort(routerHTTPPort),
            .routerHTTPSPort(routerHTTPSPort),
            .mailpitHTTPPort(mailpitHTTPPort),
            .mailpitHTTPSPort(mailpitHTTPSPort),
            .projectTLD(projectTLD)
        ]
        Task {
            seeded = false // re-seed from the reloaded (normalized) values
            await viewModel.applyGlobalConfig(changes)
            seedFromConfig()
        }
    }
}

private struct AddProjectSheet: View {
    let folder: URL
    var viewModel: ProjectDashboardViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var projectName: String
    @State private var projectType: DDEVProjectType = .wordpress
    @State private var docroot = ""
    @State private var showAdvancedProjectTypes = false

    init(folder: URL, viewModel: ProjectDashboardViewModel) {
        self.folder = folder
        self.viewModel = viewModel
        _projectName = State(initialValue: folder.lastPathComponent)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                Image(systemName: "folder.badge.plus")
                    .font(.largeTitle)
                    .foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Configure DDEV Project")
                        .font(.title3.weight(.semibold))
                    Text(folder.path)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }

            Form {
                Section {
                    TextField("Project name", text: $projectName)

                    VStack(alignment: .leading, spacing: 8) {
                        Picker("Project type", selection: $projectType) {
                            ForEach(DDEVProjectType.commonProjectTypes, id: \.self) { type in
                                Label(type.displayName, systemImage: type.symbol).tag(type)
                            }
                        }

                        DisclosureGroup("More project types", isExpanded: $showAdvancedProjectTypes) {
                            Picker("Advanced type", selection: $projectType) {
                                ForEach(DDEVProjectType.advancedProjectTypes, id: \.self) { type in
                                    Label(type.displayName, systemImage: type.symbol).tag(type)
                                }
                            }
                            .labelsHidden()
                        }
                    }

                    TextField("Docroot", text: $docroot, prompt: Text("Leave blank for project root"))
                }
            }
            .formStyle(.grouped)
            .frame(maxHeight: showAdvancedProjectTypes ? 270 : 220)

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button {
                    Task {
                        await viewModel.configureProject(
                            folder: folder.path,
                            name: projectName,
                            type: projectType,
                            docroot: docroot
                        )
                        dismiss()
                    }
                } label: {
                    Label("Configure", systemImage: "checkmark")
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(projectName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(24)
        .frame(width: 520)
    }
}
