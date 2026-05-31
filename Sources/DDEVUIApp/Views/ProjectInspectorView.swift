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
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        Menu {
                            Button {
                                if let url = project.primaryURL { workspaceOpener.openURL(url) }
                            } label: {
                                Label("Open Primary URL", systemImage: "safari")
                            }
                            .disabled(project.primaryURL == nil)

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
            tabPicker
        }
        .padding(.horizontal, 24)
        .padding(.top, 20)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
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
                .disabled(!isRunning || project.primaryURL == nil)

                if isRunning {
                    Button {
                        Task { await viewModel.restartSelectedProject() }
                    } label: {
                        Label("Restart", systemImage: "arrow.clockwise")
                    }
                    .controlSize(.large)

                    Button {
                        Task { await viewModel.stopSelectedProject() }
                    } label: {
                        Label("Stop", systemImage: "stop.fill")
                    }
                    .controlSize(.large)
                } else {
                    Button {
                        Task { await viewModel.startSelectedProject() }
                    } label: {
                        Label("Start", systemImage: "play.fill")
                    }
                    .controlSize(.large)
                }

                Spacer(minLength: 0)

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

// MARK: - Overview tab

private struct OverviewTabContent: View {
    let project: DDEVProject
    var viewModel: ProjectDashboardViewModel
    let workspaceOpener: MacWorkspaceOpener
    @Binding var showConfigEditor: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            environmentSection
            urlsSection
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

                HStack {
                    Spacer()
                    Button {
                        showConfigEditor = true
                    } label: {
                        Label("Edit Config", systemImage: "slider.horizontal.3")
                    }
                    .buttonStyle(.bordered)
                    .disabled(viewModel.isSelectedProjectBusy)
                }
            }
        }
    }

    @ViewBuilder
    private var urlsSection: some View {
        let links: [(String, String, URL?)] = [
            ("Primary", "safari", project.primaryURL),
            ("HTTPS", "lock.shield", project.httpsURL),
            ("HTTP", "globe", project.httpURL),
            ("Mailpit", "envelope", project.mailpitHTTPSURL ?? project.mailpitURL),
            ("XHGui", "chart.bar.xaxis", project.openableXHGuiURL)
        ]
        let available = links.compactMap { item -> (String, String, URL)? in
            guard let url = item.2 else { return nil }
            return (item.0, item.1, url)
        }

        if !available.isEmpty || project.xhguiStatus == .disabled {
            InspectorSection("URLs") {
                FlowHStack(spacing: 8) {
                    ForEach(available, id: \.0) { item in
                        Button {
                            workspaceOpener.openURL(item.2)
                        } label: {
                            Label(item.0, systemImage: item.1)
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

// MARK: - Manage tab

private struct ManageTabContent: View {
    let project: DDEVProject
    var viewModel: ProjectDashboardViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                FrameworkCommandLauncherView(project: project, viewModel: viewModel)
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
                    errorMessage: viewModel.selectedProjectState.lastErrorMessage
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
