import SwiftUI

struct ContentView: View {
    @StateObject private var viewModel = ProjectDashboardViewModel(
        notifier: ContentView.makeNotifier()
    )
    @StateObject private var prerequisites = PrerequisiteMonitor()
    @State private var folderToConfigure: FolderToConfigure?

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
                            .tag(item)
                    }
                }
            }
            .listStyle(.sidebar)
            .navigationTitle("DDEVUI")
            .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 240)
        } content: {
            if viewModel.selectedSidebarItem == .settings {
                SettingsView(viewModel: viewModel)
            } else if viewModel.selectedSidebarItem == .diagnostics {
                DiagnosticsView(viewModel: viewModel)
                    .navigationSplitViewColumnWidth(min: 480, ideal: 680)
            } else {
                ProjectListView(viewModel: viewModel)
                    .navigationSplitViewColumnWidth(min: 280, ideal: 320, max: 420)
            }
        } detail: {
            if viewModel.selectedSidebarItem == .diagnostics {
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

    private var sidebarSelection: Binding<ProjectSidebarItem> {
        Binding {
            viewModel.selectedSidebarItem
        } set: { newSelection in
            guard viewModel.selectedSidebarItem != newSelection else { return }
            viewModel.selectedSidebarItem = newSelection
        }
    }

    private func addFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false

        guard panel.runModal() == .OK, let folder = panel.url else { return }

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
    ContentView()
}

private struct SettingsView: View {
    @ObservedObject var viewModel: ProjectDashboardViewModel

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
    @ObservedObject var viewModel: ProjectDashboardViewModel
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
