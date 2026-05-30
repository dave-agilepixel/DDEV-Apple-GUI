import SwiftUI

struct ProjectListView: View {
    @ObservedObject var viewModel: ProjectDashboardViewModel
    @FocusState private var searchFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            if !viewModel.projects.isEmpty {
                searchBar
                Divider()
            }
            contentBody
        }
        .navigationTitle(viewModel.selectedSidebarItem.title)
    }

    private var searchBar: some View {
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
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background {
            Button("") { searchFocused = true }
                .keyboardShortcut("f", modifiers: .command)
                .hidden()
        }
    }

    private var contentBody: some View {
        Group {
            if let errorMessage = viewModel.lastErrorMessage, viewModel.projects.isEmpty {
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
                            ProjectRow(project: project)
                                .tag(project.id)
                                .listRowSeparator(.visible)
                        }
                    } header: {
                        HStack {
                            Text(viewModel.selectedSidebarItem.title)
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
        switch viewModel.selectedSidebarItem {
        case .running: return "Start a project to see it here."
        case .wordpress: return "Configure a WordPress site to populate this list."
        default: return "Use Add Folder to register a DDEV project."
        }
    }
}

private struct ProjectRow: View {
    let project: DDEVProject

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: project.projectType.symbol)
                .font(.title3)
                .foregroundStyle(.tint)
                .frame(width: 28, alignment: .center)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(project.name)
                        .font(.headline)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    Circle()
                        .fill(statusColor)
                        .frame(width: 8, height: 8)
                }

                HStack(spacing: 8) {
                    Text(project.projectType.displayName)
                    if let php = project.phpVersion {
                        Text("·")
                            .foregroundStyle(.tertiary)
                        Text("PHP \(php)")
                            .monospacedDigit()
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
        }
        .padding(.vertical, 4)
    }

    private var statusColor: Color {
        switch project.status {
        case .running: .green
        case .paused: .orange
        case .stopped: .secondary
        case .unknown: .yellow
        }
    }
}
