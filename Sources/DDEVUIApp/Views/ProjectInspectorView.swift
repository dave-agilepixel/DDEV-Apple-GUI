import AppKit
import SwiftUI

struct ProjectInspectorView: View {
    @ObservedObject var viewModel: ProjectDashboardViewModel

    var body: some View {
        Group {
            if let project = viewModel.selectedProject {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        header(project)
                        lifecycleActions
                        dailyTools(project)
                        if viewModel.canRunWordPressActions(for: project) {
                            wordpressActions
                        }
                        dangerActions
                        CommandOutputView(result: viewModel.lastCommandResult, errorMessage: viewModel.lastErrorMessage)
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                ContentUnavailableView("No Project Selected", systemImage: "shippingbox")
            }
        }
    }

    private func header(_ project: DDEVProject) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(project.name)
                .font(.largeTitle.bold())
            Text(project.appRoot)
                .font(.callout)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
        }
    }

    private var lifecycleActions: some View {
        actionSection("Lifecycle") {
            Button("Start") { Task { await viewModel.startSelectedProject() } }
            Button("Stop") { Task { await viewModel.stopSelectedProject() } }
            Button("Restart") { Task { await viewModel.restartSelectedProject() } }
        }
    }

    private func dailyTools(_ project: DDEVProject) -> some View {
        actionSection("Daily Tools") {
            Button("Open Site") {
                if let url = project.primaryURL {
                    NSWorkspace.shared.open(url)
                }
            }
            .disabled(project.primaryURL == nil)

            Button("Open Folder") {
                NSWorkspace.shared.open(URL(fileURLWithPath: project.appRoot))
            }
        }
    }

    private var wordpressActions: some View {
        actionSection("WordPress") {
            Button("Update Core") {}
            Button("Update Plugins") {}
            Button("Update Themes") {}
        }
    }

    private var dangerActions: some View {
        actionSection("Danger") {
            Button("Unlink From List", role: .destructive) {
                Task { await viewModel.unlinkSelectedProject() }
            }
            Button("Delete DDEV Data", role: .destructive) {}
            Button("Delete Source Folder", role: .destructive) {}
        }
    }

    private func actionSection<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline)
            HStack {
                content()
            }
            .buttonStyle(.bordered)
            .disabled(viewModel.isRunningCommand)
        }
    }
}
