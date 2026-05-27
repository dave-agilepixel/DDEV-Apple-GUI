import SwiftUI

struct ProjectListView: View {
    @ObservedObject var viewModel: ProjectDashboardViewModel

    var body: some View {
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
                List(selection: $viewModel.selectedProjectID) {
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
        .navigationTitle(viewModel.selectedSidebarItem.title)
        .searchable(text: $viewModel.searchText, placement: .toolbar, prompt: "Filter projects")
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
