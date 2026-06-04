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
        VStack(alignment: .leading, spacing: 10) {
            ProjectThumbnailView(
                thumbnail: viewModel.thumbnails[project.id],
                fallbackSymbol: project.projectType.symbol,
                cornerRadius: 10
            )
            .frame(maxWidth: 360)
            .frame(height: 200)
            .accessibilityLabel("Homepage preview for \(project.name)")

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

                shellSplitButton(project, isRunning: isRunning)
                editorSplitButton(project)
                databaseSplitButton(isRunning: isRunning)
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

    /// A11 — hands a shell session off to Terminal.app. Primary action opens `ddev ssh` in the web
    /// container; the menu offers the db shell and the MySQL client. Mirrors the editor/database
    /// split-button idiom for visual consistency.
    private func shellSplitButton(_ project: DDEVProject, isRunning: Bool) -> some View {
        HStack(spacing: 0) {
            Button {
                workspaceOpener.openShell(in: project.appRoot, target: .webShell)
            } label: {
                Label("Shell", systemImage: "terminal")
            }
            .help("Open a shell in the web container in Terminal")

            Menu {
                ForEach(DDEVShellTarget.allCases) { target in
                    Button {
                        workspaceOpener.openShell(in: project.appRoot, target: target)
                    } label: {
                        Label(target.displayName, systemImage: target.systemImage)
                    }
                }
            } label: {
                EmptyView()
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.visible)
            .fixedSize()
        }
        .controlSize(.large)
        .fixedSize()
        .disabled(!isRunning)
    }

    private func editorSplitButton(_ project: DDEVProject) -> some View {
        HStack(spacing: 0) {
            Button {
                workspaceOpener.openFolder(project.appRoot, editor: viewModel.effectiveDefaultEditor)
            } label: {
                Label("Open", systemImage: "square.and.pencil")
            }

            Menu {
                ForEach(viewModel.availableEditors) { editor in
                    Button(editor.displayName) {
                        workspaceOpener.openFolder(project.appRoot, editor: editor)
                    }
                }
            } label: {
                EmptyView()
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.visible)
            .fixedSize()
        }
        .controlSize(.large)
        .fixedSize()
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


// MARK: - Overview tab

private struct OverviewTabContent: View {
    let project: DDEVProject
    var viewModel: ProjectDashboardViewModel
    let workspaceOpener: MacWorkspaceOpener
    @Binding var showConfigEditor: Bool

    private var details: DDEVProjectDetails? { viewModel.selectedProjectDetails }

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            environmentSection
            urlsSection
            servicesSection
            databaseCredentialsSection
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 20)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var environmentSection: some View {
        InspectorSection("Environment") {
            VStack(alignment: .leading, spacing: 8) {
                metaRow("PHP version", trailing: {
                    HStack(spacing: 6) {
                        Text(project.phpVersion ?? "Unknown")
                            .font(.system(.body, design: .monospaced))
                        Menu {
                            ForEach(viewModel.supportedPHPVersions, id: \.self) { version in
                                Button("PHP \(version)") {
                                    Task { await viewModel.setPHPVersionForSelectedProject(version) }
                                }
                                .disabled(project.phpVersion == version)
                            }
                        } label: {
                            Text("Change")
                        }
                        .menuStyle(.borderlessButton)
                        .fixedSize()
                        .disabled(viewModel.isSelectedProjectBusy)
                    }
                })

                // Bind to the *live* Xdebug state (ddev xdebug status), not describe's config value.
                // Only present for a running project (the only time the live state is meaningful).
                if let xdebugEnabled = viewModel.selectedProjectXdebugEnabled {
                    metaRow("Xdebug", trailing: {
                        Toggle("Xdebug", isOn: Binding(
                            get: { xdebugEnabled },
                            set: { newValue in Task { await viewModel.setXdebugForSelectedProject(newValue) } }
                        ))
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.small)
                        .disabled(viewModel.isSelectedProjectBusy)
                    })
                }

                // A17 — live XHGui/XHProf profiling toggle, same shape as Xdebug. XHGui is DDEV's
                // XHProf UI; live state comes from `ddev xhgui status`. (No `ddev blackfire` command
                // exists in this DDEV, so Blackfire is intentionally not surfaced.)
                if let xhguiEnabled = viewModel.selectedProjectXHGuiEnabled {
                    metaRow("XHProf (XHGui)", trailing: {
                        Toggle("XHProf", isOn: Binding(
                            get: { xhguiEnabled },
                            set: { newValue in Task { await viewModel.setXHGuiForSelectedProject(newValue) } }
                        ))
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.small)
                        .disabled(viewModel.isSelectedProjectBusy)
                    })
                }

                metaRow("Project type", trailing: {
                    Text(project.projectType.displayName)
                        .foregroundStyle(.secondary)
                })

                if !project.docroot.isEmpty {
                    metaRow("Docroot", trailing: {
                        Text(project.docroot)
                            .font(.system(.body, design: .monospaced))
                            .foregroundStyle(.secondary)
                    })
                }

                if let mutagen = project.mutagenStatus, project.mutagenEnabled {
                    metaRow("Mutagen", trailing: {
                        Text(mutagen)
                            .foregroundStyle(.secondary)
                    })
                }

                HStack(spacing: 8) {
                    // B8 — open the raw .ddev/ files in the editor instead of building fragile
                    // GUI forms for advanced config.
                    Button {
                        workspaceOpener.openFolder(project.appRoot + "/.ddev", editor: viewModel.effectiveDefaultEditor)
                    } label: {
                        Label(".ddev/", systemImage: "folder")
                    }
                    Button {
                        workspaceOpener.openFile(project.appRoot + "/.ddev/config.yaml", editor: viewModel.effectiveDefaultEditor)
                    } label: {
                        Label("config.yaml", systemImage: "doc.text")
                    }

                    Spacer()

                    Button {
                        showConfigEditor = true
                    } label: {
                        Label("Edit Config", systemImage: "slider.horizontal.3")
                    }
                    .disabled(viewModel.isSelectedProjectBusy)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
    }

    @ViewBuilder
    private var urlsSection: some View {
        // A1 — one place to open every URL the project exposes, including add-on service UIs
        // (phpMyAdmin, Adminer, …) derived from the live describe detail.
        let links = projectLaunchLinks(project, details)

        if !links.isEmpty || project.xhguiStatus == .disabled {
            InspectorSection("Open") {
                FlowHStack(spacing: 8) {
                    ForEach(links) { link in
                        Button {
                            workspaceOpener.openURL(link.url)
                        } label: {
                            Label(link.name, systemImage: link.systemImage)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }

                    if project.xhguiStatus == .disabled {
                        Button {
                            Task { await viewModel.enableXHGuiForSelectedProject() }
                        } label: {
                            Label("Enable XHGui", systemImage: "chart.bar.xaxis")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }
                .disabled(project.status != .running)
            }
        }
    }

    // A4 — per-service health + the ephemeral 127.0.0.1 ports Docker assigned, plus router and
    // ssh-agent health. Surfaces partial/unhealthy states the single status badge flattens.
    @ViewBuilder
    private var servicesSection: some View {
        if let details, !details.services.isEmpty {
            InspectorSection("Services") {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(details.services) { service in
                        ServiceRow(service: service, workspaceOpener: workspaceOpener)
                    }
                    if let router = details.routerStatus {
                        ServiceHealthRow(label: "Router", status: router)
                    }
                    if let ssh = details.sshAgentStatus {
                        ServiceHealthRow(label: "SSH agent", status: ssh)
                    }
                }
            }
        }
    }

    // A3 — copyable database credentials. Only shown for a running project (the dbinfo only exists
    // then), and the password is masked until revealed.
    @ViewBuilder
    private var databaseCredentialsSection: some View {
        if project.status == .running, let db = details?.databaseInfo {
            InspectorSection("Database Credentials") {
                VStack(alignment: .leading, spacing: 6) {
                    CopyableRow(label: "Database", value: db.name)
                    CopyableRow(label: "Username", value: db.username)
                    CopyableRow(label: "Password", value: db.password, isSecret: true)
                    if let hostPort = details?.databaseHostPort {
                        CopyableRow(label: "Host", value: "127.0.0.1")
                        CopyableRow(label: "Port", value: hostPort)
                    } else {
                        Label(
                            "Database port is not published to the host. Use the Database button to open a client.",
                            systemImage: "info.circle"
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private func metaRow<Trailing: View>(_ label: String, @ViewBuilder trailing: () -> Trailing) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer()
            trailing()
        }
        .font(.callout)
    }
}

// MARK: - Service rows (A4)

private struct ServiceRow: View {
    let service: DDEVServiceInfo
    let workspaceOpener: MacWorkspaceOpener

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(service.isRunning ? Color.green : Color.orange)
                .frame(width: 7, height: 7)
            Text(service.shortName)
                .font(.callout.weight(.medium))
                .frame(width: 76, alignment: .leading)
            Text(service.status)
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer(minLength: 6)

            if !service.hostPorts.isEmpty {
                Text(service.hostPorts.map { "\($0.exposedPort)→\($0.hostPort)" }.joined(separator: "  "))
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .textSelection(.enabled)
            }

            if let url = service.hostHTTPSURL ?? service.hostHTTPURL ?? service.httpsURL ?? service.httpURL {
                Button {
                    workspaceOpener.openURL(url)
                } label: {
                    Image(systemName: "arrow.up.forward.app")
                }
                .buttonStyle(.borderless)
                .help("Open \(service.shortName)")
            }
        }
        .help(service.image)
    }
}

private struct ServiceHealthRow: View {
    let label: String
    let status: String

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(status == "healthy" ? Color.green : Color.orange)
                .frame(width: 7, height: 7)
            Text(label)
                .font(.callout)
                .frame(width: 76, alignment: .leading)
            Text(status)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
        }
    }
}

// MARK: - Manage tab

/// A10 — tool passthrough: run `ddev composer/npm/drush/wp` with free-text arguments. The available
/// tools are derived from the project type. Output flows into the Logs-tab command output.
private struct ToolRunnerView: View {
    let project: DDEVProject
    var viewModel: ProjectDashboardViewModel

    private var tools: [DDEVTool] { DDEVTool.tools(for: project.projectType) }

    var body: some View {
        InspectorSection("Tools") {
            VStack(alignment: .leading, spacing: 10) {
                Text("Run a tool inside the web container with your own arguments (ddev <tool> …). Output appears under the Logs tab.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                ForEach(tools) { tool in
                    ToolRow(tool: tool, project: project, viewModel: viewModel)
                }

                if project.status != .running {
                    Text("Start the project to run tools.")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }
}

private struct ToolRow: View {
    let tool: DDEVTool
    let project: DDEVProject
    var viewModel: ProjectDashboardViewModel

    @State private var args = ""

    var body: some View {
        HStack(spacing: 8) {
            Text(tool.displayName)
                .font(.callout.weight(.medium))
                .frame(width: 84, alignment: .leading)

            TextField(tool.placeholder, text: $args)
                .textFieldStyle(.roundedBorder)
                .font(.system(.body, design: .monospaced))
                .onSubmit(run)

            Button("Run", action: run)
                .disabled(!canRun)
        }
    }

    private var canRun: Bool {
        project.status == .running
            && !viewModel.isSelectedProjectBusy
            && !args.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func run() {
        guard canRun else { return }
        let toRun = args
        Task { await viewModel.runToolForSelectedProject(tool, argumentString: toRun) }
    }
}

/// A9 — run an arbitrary one-shot command inside a service container (`ddev exec`). Output flows
/// into the normal command-output channel (Logs tab). The command is run via `bash -c`, so pipes
/// and shell features work.
private struct ExecConsoleView: View {
    let project: DDEVProject
    var viewModel: ProjectDashboardViewModel

    @State private var command = ""
    @State private var service: DDEVExecService = .web

    var body: some View {
        InspectorSection("Run Command") {
            VStack(alignment: .leading, spacing: 10) {
                Text("Run a one-shot shell command inside a container (ddev exec). Output appears under the Logs tab.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack(spacing: 8) {
                    Picker("Service", selection: $service) {
                        ForEach(DDEVExecService.allCases) { service in
                            Text(service.displayName).tag(service)
                        }
                    }
                    .labelsHidden()
                    .fixedSize()

                    TextField("e.g. composer install", text: $command)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))
                        .onSubmit(run)

                    Button("Run", action: run)
                        .buttonStyle(.borderedProminent)
                        .disabled(!canRun)
                }

                if project.status != .running {
                    Text("Start the project to run commands in its containers.")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }

    private var canRun: Bool {
        project.status == .running
            && !viewModel.isSelectedProjectBusy
            && !command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func run() {
        guard canRun else { return }
        let toRun = command
        Task { await viewModel.runExecForSelectedProject(command: toRun, service: service) }
    }
}

/// A13 — surfaces user-defined custom commands (`.ddev/commands/…`) discovered at runtime as
/// buttons. Hidden entirely when the project defines none.
private struct CustomCommandsView: View {
    let project: DDEVProject
    var viewModel: ProjectDashboardViewModel

    var body: some View {
        if !viewModel.customCommands.isEmpty {
            InspectorSection("Custom Commands") {
                FlowHStack(spacing: 8) {
                    ForEach(viewModel.customCommands) { command in
                        Button {
                            Task { await viewModel.runCustomCommandForSelectedProject(command) }
                        } label: {
                            Label(command.name, systemImage: "terminal")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .help(command.description ?? "ddev \(command.name) (\(command.scope.rawValue))")
                    }
                }
                .disabled(viewModel.isSelectedProjectBusy)
            }
        }
    }
}

/// A8 — expose the project on a temporary public URL via `ddev share`. Shows the parsed tunnel URL
/// with open/copy, and a prominent Stop control. The tunnel is a long-running process owned by the
/// view model.
private struct ShareView: View {
    let project: DDEVProject
    var viewModel: ProjectDashboardViewModel
    private let workspaceOpener = MacWorkspaceOpener()

    var body: some View {
        InspectorSection("Share") {
            VStack(alignment: .leading, spacing: 10) {
                Text("Expose this project on a temporary public URL (ddev share). Anyone with the link can reach your local site — stop sharing when you're done.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                content

                if project.status != .running {
                    Text("Start the project to share it.")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.shareState {
        case .idle, .stopped, .failed:
            Button {
                viewModel.startSharing()
            } label: {
                Label("Start Sharing", systemImage: "antenna.radiowaves.left.and.right")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .disabled(project.status != .running)

            if case .failed(let message) = viewModel.shareState {
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

        case .starting:
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Starting tunnel…").foregroundStyle(.secondary)
                Spacer()
                Button("Stop", role: .destructive) { viewModel.stopSharing() }
                    .controlSize(.small)
            }

        case .running(let url):
            HStack(spacing: 8) {
                Image(systemName: "antenna.radiowaves.left.and.right")
                    .foregroundStyle(.green)
                if let url {
                    Text(url)
                        .font(.system(.callout, design: .monospaced))
                        .textSelection(.enabled)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Button {
                        if let parsed = URL(string: url) { workspaceOpener.openURL(parsed) }
                    } label: { Image(systemName: "safari") }
                        .buttonStyle(.borderless)
                        .help("Open the public URL")
                    Button { Pasteboard.copy(url) } label: { Image(systemName: "doc.on.doc") }
                        .buttonStyle(.borderless)
                        .help("Copy the public URL")
                } else {
                    Text("Tunnel running…").foregroundStyle(.secondary)
                }
                Spacer()
                Button("Stop Sharing", role: .destructive) { viewModel.stopSharing() }
                    .controlSize(.small)
            }
        }
    }
}

private struct ManageTabContent: View {
    let project: DDEVProject
    var viewModel: ProjectDashboardViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                FrameworkCommandLauncherView(project: project, viewModel: viewModel)
                CustomCommandsView(project: project, viewModel: viewModel)
                ToolRunnerView(project: project, viewModel: viewModel)
                ExecConsoleView(project: project, viewModel: viewModel)
                DatabaseOperationsView(project: project, viewModel: viewModel)
                ShareView(project: project, viewModel: viewModel)
                SnapshotManagerView(project: project, viewModel: viewModel)
                AddonManagerView(project: project, viewModel: viewModel)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollContentBackground(.hidden)
    }
}

// MARK: - Logs tab

private struct LogsTabContent: View {
    let project: DDEVProject
    var viewModel: ProjectDashboardViewModel

    var body: some View {
        let hasAnyActivity =
            viewModel.selectedProjectState.lastResult != nil ||
            viewModel.selectedProjectState.lastErrorMessage != nil ||
            viewModel.isSelectedProjectBusy ||
            !viewModel.selectedProjectState.history.isEmpty

        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                LogsViewerView(project: project, viewModel: viewModel)

                if hasAnyActivity {
                    commandHistorySection
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollContentBackground(.hidden)
    }

    private var commandHistorySection: some View {
        InspectorSection(viewModel.selectedProjectState.history.count > 1 ? "Command History" : "Last Command") {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    if viewModel.isSelectedProjectBusy {
                        ProgressView()
                            .controlSize(.small)
                    } else if viewModel.selectedProjectState.lastErrorMessage != nil {
                        Image(systemName: "xmark.octagon.fill")
                            .foregroundStyle(.red)
                    } else if let result = viewModel.selectedProjectState.lastResult {
                        Image(systemName: result.succeeded ? "checkmark.circle.fill" : "xmark.octagon.fill")
                            .foregroundStyle(result.succeeded ? .green : .red)
                    }
                    Spacer()
                }

                CommandOutputView(
                    result: viewModel.selectedProjectState.lastResult,
                    history: viewModel.selectedProjectState.history,
                    errorMessage: viewModel.selectedProjectState.lastErrorMessage,
                    onRerun: { result in
                        Task { await viewModel.rerunCommandForSelectedProject(result) }
                    }
                )
            }
        }
    }
}

