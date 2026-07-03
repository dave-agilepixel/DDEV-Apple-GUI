import SwiftUI

/// Shown in the detail column when 2+ projects are multi-selected — the per-project inspector is
/// only meaningful for a single project. Surfaces the same scoped batch actions as the list's bottom
/// bar (so the two stay in lockstep), plus a way to clear the selection. Counts reflect the batch
/// scope (selection ∩ visible), matching exactly what the actions will touch.
struct MultiSelectionSummaryView: View {
    var viewModel: ProjectDashboardViewModel

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "square.stack.3d.up.fill")
                .font(.system(size: 44))
                .foregroundStyle(.tint)

            Text("\(viewModel.selectedProjectIDs.count) \(viewModel.selectedProjectIDs.count == 1 ? "Project" : "Projects") Selected")
                .font(.title2.weight(.semibold))

            Text(statusBreakdown)
                .foregroundStyle(.secondary)

            HStack(spacing: 12) {
                Button {
                    Task { await viewModel.startProjectsInCurrentView() }
                } label: {
                    Label("Start (\(viewModel.startableProjectsInCurrentView.count))", systemImage: "play.fill")
                }
                .disabled(viewModel.startableProjectsInCurrentView.isEmpty)

                Button {
                    Task { await viewModel.stopProjectsInCurrentView() }
                } label: {
                    Label("Stop (\(viewModel.stoppableProjectsInCurrentView.count))", systemImage: "stop.fill")
                }
                .disabled(viewModel.stoppableProjectsInCurrentView.isEmpty)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .labelStyle(.titleAndIcon)

            Button("Clear Selection") { viewModel.selectedProjectIDs = [] }
                .buttonStyle(.link)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Shows the real lifecycle mix over the batch scope, so paused projects never read as stopped.
    private var statusBreakdown: String {
        let scopedProjects = viewModel.batchScopeProjects
        let running = scopedProjects.filter { $0.status == .running }.count
        let paused = scopedProjects.filter { $0.status == .paused }.count
        let stopped = scopedProjects.filter { $0.status == .stopped }.count
        let unknown = scopedProjects.filter { $0.status == .unknown }.count
        var parts: [String] = []
        if running > 0 { parts.append("\(running) running") }
        if paused > 0 { parts.append("\(paused) paused") }
        if stopped > 0 { parts.append("\(stopped) stopped") }
        if unknown > 0 { parts.append("\(unknown) unknown") }
        return parts.isEmpty ? "None in the current view" : parts.joined(separator: " · ")
    }
}
