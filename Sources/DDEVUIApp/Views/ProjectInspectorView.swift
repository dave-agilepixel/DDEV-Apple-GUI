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
    @ObservedObject var viewModel: ProjectDashboardViewModel
    private let workspaceOpener = MacWorkspaceOpener()
    @State private var confirmUnlink = false
    @State private var confirmDeleteDDEVData = false
    @State private var showSourceDeleteSheet = false
    @State private var showConfigEditor = false
    @State private var outputExpanded = false

    var body: some View {
        Group {
            if let project = viewModel.selectedProject {
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        header(project)
                        primaryActionBar(project)
                        environment(project)
                        FrameworkCommandLauncherView(project: project, viewModel: viewModel)
                        AddonManagerView(project: project, viewModel: viewModel)
                        DatabaseOperationsView(project: project, viewModel: viewModel)
                        SnapshotManagerView(project: project, viewModel: viewModel)
                        LogsViewerView(project: project, viewModel: viewModel)
                        quickLinks(project)
                        commandOutputSection
                    }
                    .padding(.horizontal, 24)
                    .padding(.vertical, 20)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .scrollContentBackground(.hidden)
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
                        .disabled(viewModel.isRunningCommand)
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
        .onChange(of: viewModel.commandOutputExpansionRequest) { _, requestCount in
            if requestCount > 0 {
                outputExpanded = true
            }
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

    // MARK: - Primary action bar (single glass element, not a card)

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
        .disabled(viewModel.isRunningCommand)
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
                Image(systemName: "chevron.down")
                    .imageScale(.small)
                    .frame(width: 18)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .disabled(!isRunning || viewModel.availableDatabaseTools.isEmpty)
        }
        .controlSize(.large)
        .fixedSize()
    }

    // MARK: - Environment

    private func environment(_ project: DDEVProject) -> some View {
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
                        .disabled(viewModel.isRunningCommand)
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
                    .disabled(viewModel.isRunningCommand)
                }
            }
        }
    }

    // MARK: - Quick links

    @ViewBuilder
    private func quickLinks(_ project: DDEVProject) -> some View {
        let links: [(String, String, URL?)] = [
            ("Primary", "safari", project.primaryURL),
            ("HTTPS", "lock.shield", project.httpsURL),
            ("HTTP", "globe", project.httpURL),
            ("Mailpit", "envelope", project.mailpitHTTPSURL ?? project.mailpitURL),
            ("XHGui", "chart.bar.xaxis", project.xhguiHTTPSURL ?? project.xhguiURL)
        ]
        let available = links.compactMap { item -> (String, String, URL)? in
            guard let url = item.2 else { return nil }
            return (item.0, item.1, url)
        }

        if !available.isEmpty {
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
                }
                .disabled(project.status != .running)
            }
        }
    }

    // MARK: - Command output (disclosure)

    @ViewBuilder
    private var commandOutputSection: some View {
        if viewModel.lastCommandResult != nil || viewModel.lastErrorMessage != nil || viewModel.isRunningCommand {
            DisclosureGroup(isExpanded: $outputExpanded) {
                CommandOutputView(
                    result: viewModel.lastCommandResult,
                    history: viewModel.commandHistory,
                    errorMessage: viewModel.lastErrorMessage
                )
                .padding(.top, 8)
            } label: {
                HStack(spacing: 10) {
                    Text(viewModel.commandHistory.count > 1 ? "Command History" : "Last Command")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                        .kerning(0.5)

                    if viewModel.isRunningCommand {
                        ProgressView()
                            .controlSize(.small)
                    } else if viewModel.lastErrorMessage != nil {
                        Image(systemName: "xmark.octagon.fill")
                            .foregroundStyle(.red)
                    } else if let result = viewModel.lastCommandResult {
                        Image(systemName: result.succeeded ? "checkmark.circle.fill" : "xmark.octagon.fill")
                            .foregroundStyle(result.succeeded ? .green : .red)
                    }

                    Spacer()
                }
            }
        }
    }

    // MARK: - Small helpers

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
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                    .kerning(0.5)
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
    @ObservedObject var viewModel: ProjectDashboardViewModel
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
