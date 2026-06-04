import AppKit
import SwiftUI

enum InspectorTab: Hashable, CaseIterable {
    case overview
    case manage
    case logs

    var displayName: String {
        switch self {
        case .overview: "Overview"
        case .manage: "Manage"
        case .logs: "Logs"
        }
    }

    var systemImage: String {
        switch self {
        case .overview: "info.circle"
        case .manage: "slider.horizontal.3"
        case .logs: "text.alignleft"
        }
    }
}

struct ProjectInspectorView: View {
    var viewModel: ProjectDashboardViewModel
    private let workspaceOpener = MacWorkspaceOpener()
    @State private var confirmUnlink = false
    @State private var confirmDeleteDDEVData = false
    @State private var showSourceDeleteSheet = false
    @State private var showConfigEditor = false
    @State private var selectedTab: InspectorTab = .overview
    @State private var hasUnseenLogActivity = false

    var body: some View {
        Group {
            if let project = viewModel.selectedProject {
                VStack(alignment: .leading, spacing: 0) {
                    pinnedRegion(project)

                    Divider()

                    tabContent(project)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .task(id: project.id) {
                    // Pull the live describe detail (DB info, services), the live Xdebug status, and
                    // run the DB-drift check once per selection, independent of which tab is showing.
                    // They're independent subprocesses, so run them concurrently to keep selection snappy.
                    async let details: Void = viewModel.loadDetailsForSelectedProject()
                    async let xdebug: Void = viewModel.loadXdebugStatusForSelectedProject()
                    async let xhgui: Void = viewModel.loadXHGuiStatusForSelectedProject()
                    async let driftCheck: Void = viewModel.checkDBMatchForSelectedProject()
                    async let customCommands: Void = viewModel.loadCustomCommandsForSelectedProject()
                    _ = await (details, xdebug, xhgui, driftCheck, customCommands)
                }
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        Menu {
                            ForEach(projectLaunchLinks(project, viewModel.selectedProjectDetails)) { link in
                                Button {
                                    workspaceOpener.openURL(link.url)
                                } label: {
                                    Label("Open \(link.name)", systemImage: link.systemImage)
                                }
                            }

                            Divider()

                            Menu("Move to Group") {
                                ForEach(viewModel.groups) { group in
                                    Button {
                                        viewModel.assignProject(project.id, toGroup: group.id)
                                    } label: {
                                        Label(group.name,
                                              systemImage: viewModel.group(for: project.id)?.id == group.id ? "checkmark" : "folder")
                                    }
                                }
                                Divider()
                                Button("New Group…") {
                                    if let id = viewModel.createGroup(name: "New Group", color: .blue) {
                                        viewModel.assignProject(project.id, toGroup: id)
                                    }
                                }
                                if viewModel.group(for: project.id) != nil {
                                    Button("Remove from Group", role: .destructive) {
                                        viewModel.removeProjectFromGroup(project.id)
                                    }
                                }
                            }

                            Divider()

                            Button(role: .destructive) {
                                confirmUnlink = true
                            } label: {
                                Label("Unlink From DDEV…", systemImage: "link.badge.plus")
                            }
                            Button(role: .destructive) {
                                confirmDeleteDDEVData = true
                            } label: {
                                Label("Delete DDEV Data…", systemImage: "internaldrive")
                            }
                            Button(role: .destructive) {
                                showSourceDeleteSheet = true
                            } label: {
                                Label("Move Source To Trash…", systemImage: "trash")
                            }
                        } label: {
                            Label("More", systemImage: "ellipsis.circle")
                        }
                        .disabled(viewModel.isSelectedProjectBusy)
                    }
                }
            } else {
                ContentUnavailableView(
                    "No Project Selected",
                    systemImage: "shippingbox",
                    description: Text("Pick a project from the list to manage it.")
                )
            }
        }
        .confirmationDialog("Unlink this project from DDEV?", isPresented: $confirmUnlink) {
            Button("Unlink", role: .destructive) {
                Task { await viewModel.unlinkSelectedProject() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes the project from the DDEV list but leaves files and database data alone.")
        }
        .confirmationDialog("Delete DDEV data?", isPresented: $confirmDeleteDDEVData) {
            Button("Delete DDEV Data", role: .destructive) {
                Task { await viewModel.deleteSelectedDDEVData() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes DDEV project data including database data. It does not delete the source folder.")
        }
        .sheet(isPresented: $showSourceDeleteSheet) {
            if let project = viewModel.selectedProject {
                SourceFolderDeleteSheet(project: project, viewModel: viewModel)
            }
        }
        .sheet(isPresented: $showConfigEditor) {
            if let project = viewModel.selectedProject {
                ProjectConfigEditorView(project: project, viewModel: viewModel)
            }
        }
        .onChange(of: viewModel.selectedProjectState.outputExpansionRequest) { _, requestCount in
            // New command output arrived. Flag it on the Logs tab unless the user is
            // already there (in which case there's nothing unseen to announce).
            if requestCount > 0, selectedTab != .logs {
                hasUnseenLogActivity = true
            }
        }
        .onChange(of: selectedTab) { _, newTab in
            if newTab == .logs {
                hasUnseenLogActivity = false
            }
        }
        .onChange(of: viewModel.selectedProject?.id) { _, _ in
            selectedTab = .overview
            hasUnseenLogActivity = false
        }
    }

    // MARK: - Pinned region

    @ViewBuilder
    private func pinnedRegion(_ project: DDEVProject) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            header(project)
            primaryActionBar(project)
            if let warning = viewModel.dbMatchWarning {
                DBDriftBanner(message: warning) { showConfigEditor = true }
            }
            tabPicker
        }
        .padding(.horizontal, 24)
        .padding(.top, 20)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(.snappy, value: viewModel.dbMatchWarning)
    }

    private var tabPicker: some View {
        Picker("Section", selection: $selectedTab) {
            ForEach(InspectorTab.allCases, id: \.self) { tab in
                Text(tab.displayName).tag(tab)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        // Logs is the rightmost segment, so a dot at the top-trailing corner sits over it.
        .overlay(alignment: .topTrailing) {
            if hasUnseenLogActivity {
                Circle()
                    .fill(.red)
                    .frame(width: 8, height: 8)
                    .offset(x: 3, y: -3)
                    .transition(.scale.combined(with: .opacity))
                    .accessibilityLabel("New log activity")
            }
        }
        .animation(.snappy, value: hasUnseenLogActivity)
    }

    @ViewBuilder
    private func tabContent(_ project: DDEVProject) -> some View {
        switch selectedTab {
        case .overview:
            ScrollView {
                OverviewTabContent(
                    project: project,
                    viewModel: viewModel,
                    workspaceOpener: workspaceOpener,
                    showConfigEditor: $showConfigEditor
                )
            }
            .scrollContentBackground(.hidden)
        case .manage:
            ManageTabContent(project: project, viewModel: viewModel)
        case .logs:
            LogsTabContent(project: project, viewModel: viewModel)
        }
    }

    // MARK: - Header

    private func header(_ project: DDEVProject) -> some View {
        HStack(alignment: .top, spacing: 16) {
            ProjectThumbnailView(
                thumbnail: viewModel.thumbnails[project.id],
                fallbackSymbol: project.projectType.symbol,
                cornerRadius: 9
            )
            .frame(width: 168, height: 96)
            .accessibilityLabel("Homepage preview for \(project.name)")

            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text(project.name)
                        .font(.largeTitle.bold())
                        .lineLimit(1)
                    ProjectStatusBadge(status: project.status)
                }

                HStack(spacing: 14) {
                    Label(project.projectType.displayName, systemImage: project.projectType.symbol)
                    if let php = project.phpVersion {
                        Label("PHP \(php)", systemImage: "swift")
                            .labelStyle(.titleAndIcon)
                    }
                    if project.mutagenEnabled {
                        Label("Mutagen", systemImage: "arrow.triangle.2.circlepath")
                    }
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .labelStyle(InspectorChipLabelStyle())

                HStack(spacing: 6) {
                    Image(systemName: "folder")
                        .foregroundStyle(.tertiary)
                    Text(project.appRoot)
                        .font(.system(.callout, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            Spacer(minLength: 0)
        }
    }

    // MARK: - Primary action bar

    private func primaryActionBar(_ project: DDEVProject) -> some View {
        let isRunning = project.status == .running

        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Button {
                    if let url = project.primaryURL { workspaceOpener.openURL(url) }
                } label: {
                    Label("Open Site", systemImage: "safari")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .keyboardShortcut("o", modifiers: .command)
                .disabled(!isRunning || project.primaryURL == nil)

                if isRunning {
                    // B6 — ⌘R is the primary lifecycle action (Restart when running, Start when stopped).
                    Button {
                        Task { await viewModel.restartSelectedProject() }
                    } label: {
                        Label("Restart", systemImage: "arrow.clockwise")
                    }
                    .controlSize(.large)
                    .keyboardShortcut("r", modifiers: .command)

                    Button {
                        Task { await viewModel.stopSelectedProject() }
                    } label: {
                        Label("Stop", systemImage: "stop.fill")
                    }
                    .controlSize(.large)
                    .keyboardShortcut(".", modifiers: .command)
                } else {
                    Button {
                        Task { await viewModel.startSelectedProject() }
                    } label: {
                        Label("Start", systemImage: "play.fill")
                    }
                    .controlSize(.large)
                    .keyboardShortcut("r", modifiers: .command)
                }

                Spacer(minLength: 0)

                databaseSplitButton(isRunning: isRunning)
                openMenu(project, isRunning: isRunning)
            }

            if viewModel.effectiveDefaultDatabaseTool == nil {
                Label("Install TablePlus, Sequel Ace, Querious, or DBeaver to open databases here.", systemImage: "info.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .labelStyle(.titleAndIcon)
        .buttonStyle(.bordered)
        .disabled(viewModel.isSelectedProjectBusy)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .glassEffect(in: .rect(cornerRadius: 14))
    }

    /// Demoted launchers (shell + editor) — daily-but-not-primary, folded into one menu so they
    /// don't eat the action bar.
    private func openMenu(_ project: DDEVProject, isRunning: Bool) -> some View {
        Menu {
            Section("Shell") {
                ForEach(DDEVShellTarget.allCases) { target in
                    Button {
                        workspaceOpener.openShell(in: project.appRoot, target: target)
                    } label: {
                        Label(target.displayName, systemImage: target.systemImage)
                    }
                    .disabled(!isRunning)
                }
            }
            Section("Editor") {
                ForEach(viewModel.availableEditors) { editor in
                    Button(editor.displayName) {
                        workspaceOpener.openFolder(project.appRoot, editor: editor)
                    }
                }
            }
        } label: {
            Label("Open", systemImage: "arrow.up.forward.app")
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .controlSize(.large)
    }

    private func databaseSplitButton(isRunning: Bool) -> some View {
        HStack(spacing: 0) {
            Button {
                Task { await viewModel.launchDefaultDatabaseTool() }
            } label: {
                Label("Database", systemImage: "cylinder.split.1x2")
            }
            .disabled(!isRunning || viewModel.effectiveDefaultDatabaseTool == nil)

            Menu {
                ForEach(viewModel.availableDatabaseTools) { tool in
                    Button(tool.displayName) {
                        Task { await viewModel.launchDatabaseTool(tool) }
                    }
                }
            } label: {
                EmptyView()
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.visible)
            .fixedSize()
            .disabled(!isRunning || viewModel.availableDatabaseTools.isEmpty)
        }
        .controlSize(.large)
        .fixedSize()
    }
}


