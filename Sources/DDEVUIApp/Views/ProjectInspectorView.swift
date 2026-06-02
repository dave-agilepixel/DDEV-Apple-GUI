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

// MARK: - Section wrapper (header + dividing rule, NOT a card)

private struct InspectorSection<Content: View>: View {
    let title: String
    let content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(title)
                    .sectionHeaderStyle()
                Spacer()
            }
            content
        }
    }
}

// MARK: - Status badge (dot + label, single inline element)

struct ProjectStatusBadge: View {
    let status: DDEVProjectStatus

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
                .overlay(
                    Circle()
                        .stroke(color.opacity(0.35), lineWidth: 4)
                        .blur(radius: 2)
                        .opacity(status == .running ? 1 : 0)
                )
            Text(label)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
        }
    }

    private var color: Color {
        switch status {
        case .running: .green
        case .paused: .orange
        case .stopped: .secondary
        case .unknown: .yellow
        }
    }

    private var label: String {
        switch status {
        case .running: "Running"
        case .paused: "Paused"
        case .stopped: "Stopped"
        case .unknown: "Unknown"
        }
    }
}

// MARK: - Chip-style label (icon + text, no background)

private struct InspectorChipLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 5) {
            configuration.icon
                .foregroundStyle(.tertiary)
            configuration.title
        }
    }
}

// MARK: - Launch hub (A1)

/// One openable destination for the Open/Launch hub: the primary site, Mailpit, XHGui, and any
/// add-on service UI surfaced from `ddev describe -j`.
struct LaunchLink: Identifiable {
    var id: String { name }
    let name: String
    let systemImage: String
    let url: URL
}

/// Every browser-openable URL the project exposes — the project's own URLs plus add-on service UIs
/// (phpMyAdmin, Adminer, …) derived from the live describe detail. Shared by the toolbar "Open"
/// menu and the Overview URL chips so they can't drift apart.
func projectLaunchLinks(_ project: DDEVProject, _ details: DDEVProjectDetails?) -> [LaunchLink] {
    var links: [LaunchLink] = []
    if let url = project.primaryURL { links.append(LaunchLink(name: "Primary", systemImage: "safari", url: url)) }
    if let url = project.httpsURL { links.append(LaunchLink(name: "HTTPS", systemImage: "lock.shield", url: url)) }
    if let url = project.httpURL { links.append(LaunchLink(name: "HTTP", systemImage: "globe", url: url)) }
    if let url = project.mailpitHTTPSURL ?? project.mailpitURL {
        links.append(LaunchLink(name: "Mailpit", systemImage: "envelope", url: url))
    }
    if let url = project.openableXHGuiURL {
        links.append(LaunchLink(name: "XHGui", systemImage: "chart.bar.xaxis", url: url))
    }
    for service in details?.addonServiceLinks ?? [] {
        links.append(LaunchLink(name: service.name.capitalized, systemImage: "puzzlepiece.extension", url: service.url))
    }
    return links
}

// MARK: - DB drift banner (A5)

/// Ambient warning shown when the on-disk database volume disagrees with the configured DB
/// type/version — promotes a buried `check-db-match` diagnostic into something the user can't miss.
private struct DBDriftBanner: View {
    let message: String
    let onEditConfig: () -> Void

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.yellow)
            VStack(alignment: .leading, spacing: 2) {
                Text("Database version mismatch")
                    .font(.callout.weight(.semibold))
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            Button("Edit Config", action: onEditConfig)
                .buttonStyle(.bordered)
                .controlSize(.small)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.yellow.opacity(0.10), in: .rect(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(Color.yellow.opacity(0.35), lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Copyable value row (A3)

/// A label + value row with a one-click copy button, optionally masking the value (passwords).
private struct CopyableRow: View {
    let label: String
    let value: String
    var isSecret: Bool = false
    @State private var revealed = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(label)
                .foregroundStyle(.secondary)
                .frame(width: 96, alignment: .leading)
            Text(displayValue)
                .font(.system(.callout, design: .monospaced))
                .textSelection(.enabled)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 4)
            if isSecret {
                Button {
                    revealed.toggle()
                } label: {
                    Image(systemName: revealed ? "eye.slash" : "eye")
                }
                .buttonStyle(.borderless)
                .help(revealed ? "Hide" : "Reveal")
            }
            Button {
                Pasteboard.copy(value)
            } label: {
                Image(systemName: "doc.on.doc")
            }
            .buttonStyle(.borderless)
            .help("Copy \(label.lowercased())")
        }
        .font(.callout)
    }

    private var displayValue: String {
        guard isSecret, !revealed else { return value }
        return String(repeating: "•", count: max(8, min(value.count, 16)))
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

// MARK: - FlowHStack (wraps items to new lines on overflow)

private struct FlowHStack<Content: View>: View {
    let spacing: CGFloat
    @ViewBuilder let content: () -> Content

    init(spacing: CGFloat = 8, @ViewBuilder content: @escaping () -> Content) {
        self.spacing = spacing
        self.content = content
    }

    var body: some View {
        // Simple horizontal scroll-free wrap using HStack with .layoutPriority.
        // For short URL chip rows this works visually; a more elaborate flow layout
        // isn't worth the complexity here.
        WrappingHStack(spacing: spacing, content: content)
    }
}

private struct WrappingHStack<Content: View>: View {
    let spacing: CGFloat
    @ViewBuilder let content: () -> Content

    var body: some View {
        FlowLayout(spacing: spacing) {
            content()
        }
    }
}

private struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var lineHeight: CGFloat = 0
        var totalWidth: CGFloat = 0

        for sub in subviews {
            let size = sub.sizeThatFits(.unspecified)
            if x + size.width > maxWidth, x > 0 {
                y += lineHeight + spacing
                x = 0
                lineHeight = 0
            }
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
            totalWidth = max(totalWidth, x - spacing)
        }
        return CGSize(width: totalWidth, height: y + lineHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let maxWidth = bounds.width
        var x: CGFloat = bounds.minX
        var y: CGFloat = bounds.minY
        var lineHeight: CGFloat = 0

        for sub in subviews {
            let size = sub.sizeThatFits(.unspecified)
            if x + size.width > bounds.minX + maxWidth, x > bounds.minX {
                y += lineHeight + spacing
                x = bounds.minX
                lineHeight = 0
            }
            sub.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
    }
}

// MARK: - Source folder delete sheet

private struct SourceFolderDeleteSheet: View {
    let project: DDEVProject
    var viewModel: ProjectDashboardViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var confirmationText = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                Image(systemName: "trash.circle.fill")
                    .font(.largeTitle)
                    .foregroundStyle(.red)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Move Source Folder To Trash")
                        .font(.title3.weight(.semibold))
                    Text("Independent of DDEV data deletion.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Folder")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                    .kerning(0.5)
                Text(project.appRoot)
                    .font(.system(.callout, design: .monospaced))
                    .textSelection(.enabled)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Type **\(project.name)** to confirm")
                    .font(.callout)
                TextField("", text: $confirmationText, prompt: Text(project.name))
                    .textFieldStyle(.roundedBorder)
            }

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(role: .destructive) {
                    viewModel.moveSelectedProjectFolderToTrash()
                    dismiss()
                } label: {
                    Label("Move To Trash", systemImage: "trash")
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .disabled(confirmationText != project.name)
            }
        }
        .padding(24)
        .frame(width: 500)
    }
}
