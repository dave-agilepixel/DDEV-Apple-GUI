import SwiftUI

struct ProjectListView: View {
    @Bindable var viewModel: ProjectDashboardViewModel
    @FocusState private var searchFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            if !viewModel.projects.isEmpty {
                searchBar
                Divider()
            }
            contentBody
            if viewModel.filteredProjects.count > 1 {
                Divider()
                batchBar
            }
        }
        .navigationTitle(viewModel.currentSectionTitle)
    }

    // B3 — batch start/stop the current view (sidebar section / group / search is the selection).
    // Routed through the per-project mutations, so the CommandScheduler caps real concurrency.
    private var batchBar: some View {
        HStack(spacing: 8) {
            Button {
                Task { await viewModel.startProjectsInCurrentView() }
            } label: {
                Label("Start All (\(viewModel.startableProjectsInCurrentView.count))", systemImage: "play.fill")
            }
            .disabled(viewModel.startableProjectsInCurrentView.isEmpty)

            Button {
                Task { await viewModel.stopProjectsInCurrentView() }
            } label: {
                Label("Stop All (\(viewModel.stoppableProjectsInCurrentView.count))", systemImage: "stop.fill")
            }
            .disabled(viewModel.stoppableProjectsInCurrentView.isEmpty)

            Spacer()
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .labelStyle(.titleAndIcon)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .help("Start or stop every project in the current view")
    }

    private var searchBar: some View {
        HStack(spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Filter projects", text: $viewModel.searchText)
                    .textFieldStyle(.plain)
                    .focused($searchFocused)
                    .onSubmit { searchFocused = false }
                if !viewModel.searchText.isEmpty {
                    Button {
                        viewModel.searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Clear search")
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 8, style: .continuous))

            sortMenu
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background {
            Button("") { searchFocused = true }
                .keyboardShortcut("f", modifiers: .command)
                .hidden()
        }
    }

    // B5 — choose how the project list is ordered (persisted).
    private var sortMenu: some View {
        Menu {
            Picker("Sort by", selection: Binding(
                get: { viewModel.projectSort },
                set: { viewModel.setProjectSort($0) }
            )) {
                ForEach(ProjectSort.allCases) { sort in
                    Label(sort.displayName, systemImage: sort.systemImage).tag(sort)
                }
            }
        } label: {
            Image(systemName: "arrow.up.arrow.down")
                .foregroundStyle(.secondary)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Sort projects (currently: \(viewModel.projectSort.displayName))")
    }

    private var contentBody: some View {
        Group {
            if let errorMessage = viewModel.globalErrorMessage, viewModel.projects.isEmpty {
                ContentUnavailableView {
                    Label("DDEV Projects Unavailable", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(errorMessage)
                        .textSelection(.enabled)
                } actions: {
                    Button {
                        Task { await viewModel.refresh() }
                    } label: {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.borderedProminent)
                }
            } else if viewModel.filteredProjects.isEmpty {
                ContentUnavailableView(
                    emptyTitle,
                    systemImage: "shippingbox",
                    description: Text(emptyDescription)
                )
            } else {
                List(selection: projectSelection) {
                    Section {
                        ForEach(viewModel.filteredProjects) { project in
                            ProjectRow(project: project, viewModel: viewModel)
                                .tag(project.id)
                                .listRowSeparator(.visible)
                                .draggable(project.id)
                                .contextMenu { moveToGroupMenu(project) }
                        }
                    } header: {
                        HStack {
                            Text(viewModel.currentSectionTitle)
                                .font(.headline)
                            Spacer()
                            Text("\(viewModel.filteredProjects.count)")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
                .listStyle(.inset)
            }
        }
    }

    private var projectSelection: Binding<DDEVProject.ID?> {
        Binding {
            viewModel.selectedProjectID
        } set: { newSelection in
            guard viewModel.selectedProjectID != newSelection else { return }
            viewModel.selectedProjectID = newSelection
        }
    }

    private var emptyTitle: String {
        if !viewModel.searchText.isEmpty { return "No Matches" }
        if case .group = viewModel.selection { return "No Projects in This Group" }
        switch viewModel.selectedSidebarItem {
        case .running: return "Nothing Running"
        case .wordpress: return "No WordPress Projects"
        default: return "No Projects"
        }
    }

    private var emptyDescription: String {
        if !viewModel.searchText.isEmpty {
            return "Try a different search term."
        }
        if case .group = viewModel.selection {
            return "Drag a project here, or use Move to Group on a project."
        }
        switch viewModel.selectedSidebarItem {
        case .running: return "Start a project to see it here."
        case .wordpress: return "Configure a WordPress site to populate this list."
        default: return "Use Add Folder to register a DDEV project."
        }
    }

    @ViewBuilder
    private func moveToGroupMenu(_ project: DDEVProject) -> some View {
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
    }
}

private struct ProjectRow: View {
    let project: DDEVProject
    var viewModel: ProjectDashboardViewModel

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: project.projectType.symbol)
                .font(.title3)
                .foregroundStyle(.tint)
                .frame(width: 28, alignment: .center)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(statusColor)
                        .frame(width: 8, height: 8)
                    Text(project.name)
                        .font(.headline)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }

                HStack(spacing: 8) {
                    Text(project.projectType.displayName)
                    if let php = project.phpVersion {
                        Text("·")
                            .foregroundStyle(.tertiary)
                        Text("PHP \(php)")
                            .monospacedDigit()
                    }
                    if let group = viewModel.group(for: project.id) {
                        groupTag(group)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                Text(project.shortRoot)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            actionControls
                .frame(minWidth: 52, alignment: .trailing)
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var actionControls: some View {
        if viewModel.isBusy(project) {
            ProgressDonut(progress: viewModel.state(for: project.id).startProgress)
                .frame(width: 18, height: 18)
                .help(viewModel.isQueued(project) ? "Queued" : "Running")
                .opacity(viewModel.isQueued(project) ? 0.5 : 1)
        } else {
            HStack(spacing: 4) {
                if project.status == .running {
                    actionButton("Restart", systemImage: "arrow.clockwise") {
                        await viewModel.restart(project)
                    }
                    actionButton("Stop", systemImage: "stop.fill", tint: .red) {
                        await viewModel.stop(project)
                    }
                } else {
                    actionButton("Start", systemImage: "play.fill", tint: .green) {
                        await viewModel.start(project)
                    }
                }
            }
        }
    }

    private func actionButton(
        _ title: String,
        systemImage: String,
        tint: Color? = nil,
        action: @escaping () async -> Void
    ) -> some View {
        Button {
            Task { await action() }
        } label: {
            Image(systemName: systemImage)
                .frame(width: 14, height: 14)
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .tint(tint)
        .help(title)
        .disabled(viewModel.isBusy(project))
    }

    private var statusColor: Color {
        switch project.status {
        case .running: .green
        case .paused: .orange
        case .stopped: .secondary
        case .unknown: .yellow
        }
    }

    /// A small coloured pill showing the project's group, so membership is visible at a glance in
    /// the main listing (the dot carries the group colour; the label stays legible in secondary).
    @ViewBuilder
    private func groupTag(_ group: ProjectGroup) -> some View {
        HStack(spacing: 3) {
            Circle()
                .fill(group.colorID.color)
                .frame(width: 6, height: 6)
            Text(group.name)
                .lineLimit(1)
        }
        .font(.caption2)
        .padding(.horizontal, 6)
        .padding(.vertical, 1)
        .background(Capsule().fill(group.colorID.color.opacity(0.16)))
    }
}

/// A small ring indicator. When `progress` is non-nil it fills the ring (0…1); when nil it spins
/// an indeterminate arc. Used for start/restart where determinate progress may be unavailable.
private struct ProgressDonut: View {
    let progress: Double?
    @State private var spin = false

    var body: some View {
        ZStack {
            Circle().stroke(.quaternary, lineWidth: 2.5)
            if let progress {
                Circle()
                    .trim(from: 0, to: max(0.02, min(1, progress)))
                    .stroke(.tint, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.easeInOut(duration: 0.25), value: progress)
            } else {
                Circle()
                    .trim(from: 0, to: 0.25)
                    .stroke(.tint, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                    .rotationEffect(.degrees(spin ? 360 : 0))
                    .animation(.linear(duration: 0.9).repeatForever(autoreverses: false), value: spin)
                    .onAppear { spin = true }
            }
        }
    }
}
