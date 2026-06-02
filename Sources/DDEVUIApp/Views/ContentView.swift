import SwiftUI

struct ContentView: View {
    @State private var viewModel: ProjectDashboardViewModel
    @State private var prerequisites: PrerequisiteMonitor
    @State private var folderToConfigure: FolderToConfigure?
    @State private var showNewGroupEditor = false
    @State private var groupToRename: ProjectGroup?
    /// The group row a project is currently being dragged over, for drop-target highlighting.
    @State private var dropTargetGroupID: ProjectGroup.ID?
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
                                .dropDestination(for: ProjectTransfer.self) { items, _ in
                                    for item in items { viewModel.assignProject(item.projectID, toGroup: group.id) }
                                    return !items.isEmpty
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
            }
        }
        .sheet(item: $folderToConfigure) { folder in
            AddProjectSheet(folder: folder.url, viewModel: viewModel)
        }
        .sheet(item: $groupToRename) { group in
            RenameGroupSheet(viewModel: viewModel, group: group)
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
        }
        .onChange(of: scenePhase) { _, phase in
            // Pause the prerequisite poll while backgrounded; re-arm (and re-validate) on return.
            if phase == .active {
                prerequisites.start()
            } else {
                prerequisites.stop()
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
        Button("Rename…") { groupToRename = group }
        Menu("Change Colour") {
            ForEach(GroupColor.allCases, id: \.self) { swatch in
                Button {
                    viewModel.setColor(swatch, for: group.id)
                } label: {
                    Label(swatch.rawValue.capitalized, systemImage: group.colorID == swatch ? "checkmark" : "circle.fill")
                }
            }
        }
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
        }
        .formStyle(.grouped)
        .navigationTitle("Settings")
        .onAppear {
            viewModel.refreshInstalledApps()
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
