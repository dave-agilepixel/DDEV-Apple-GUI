import SwiftUI

// MARK: - Logs tab

struct LogsTabContent: View {
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
