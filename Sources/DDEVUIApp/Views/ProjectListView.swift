import SwiftUI

struct ProjectListView: View {
    @ObservedObject var viewModel: ProjectDashboardViewModel

    var body: some View {
        VStack(spacing: 0) {
            TextField("Search projects", text: $viewModel.searchText)
                .textFieldStyle(.roundedBorder)
                .padding()

            if let errorMessage = viewModel.lastErrorMessage, viewModel.projects.isEmpty {
                ContentUnavailableView {
                    Label("DDEV Projects Unavailable", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(errorMessage)
                        .textSelection(.enabled)
                } actions: {
                    Button("Refresh") {
                        Task { await viewModel.refresh() }
                    }
                }
                .padding()
            } else if viewModel.filteredProjects.isEmpty {
                ContentUnavailableView("No Projects", systemImage: "shippingbox")
                    .padding()
            } else {
                List(selection: $viewModel.selectedProject) {
                    ForEach(viewModel.filteredProjects) { project in
                        ProjectRow(project: project)
                            .tag(project)
                    }
                }
            }
        }
        .navigationTitle("Projects")
    }
}

private struct ProjectRow: View {
    let project: DDEVProject

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(project.name)
                    .font(.headline)
                Spacer()
                Text(project.status.rawValue.capitalized)
                    .font(.caption)
                    .foregroundStyle(project.status == .running ? .green : .secondary)
            }

            HStack(spacing: 8) {
                Text(project.projectType.rawValue)
                Text(project.shortRoot)
                    .lineLimit(1)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
}
