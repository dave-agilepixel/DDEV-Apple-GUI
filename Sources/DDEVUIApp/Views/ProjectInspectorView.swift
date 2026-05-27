import AppKit
import SwiftUI

struct ProjectInspectorView: View {
    @ObservedObject var viewModel: ProjectDashboardViewModel
    private let workspaceOpener = MacWorkspaceOpener()
    @State private var confirmUnlink = false
    @State private var confirmDeleteDDEVData = false
    @State private var showSourceDeleteSheet = false

    var body: some View {
        Group {
            if let project = viewModel.selectedProject {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        header(project)
                        environment(project)
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

    private func environment(_ project: DDEVProject) -> some View {
        actionSection("Environment") {
            LabeledContent("PHP") {
                Text(project.phpVersion ?? "Unknown")
                    .monospacedDigit()
            }

            Menu("Change PHP") {
                ForEach(viewModel.supportedPHPVersions, id: \.self) { version in
                    Button("PHP \(version)") {
                        Task { await viewModel.setPHPVersionForSelectedProject(version) }
                    }
                    .disabled(project.phpVersion == version)
                }
            }
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
                    workspaceOpener.openURL(url)
                }
            }
            .disabled(project.primaryURL == nil)

            Menu("Open In") {
                Button("Cursor") {
                    workspaceOpener.openFolder(project.appRoot, editor: .cursor)
                }
                Button("VS Code") {
                    workspaceOpener.openFolder(project.appRoot, editor: .visualStudioCode)
                }
                Button("Finder") {
                    workspaceOpener.openFolder(project.appRoot, editor: .finder)
                }
            }

            Menu("Database") {
                Button("Sequel Ace") { Task { await viewModel.launchDatabaseTool(.sequelAce) } }
                Button("TablePlus") { Task { await viewModel.launchDatabaseTool(.tablePlus) } }
                Button("Querious") { Task { await viewModel.launchDatabaseTool(.querious) } }
                Button("DBeaver") { Task { await viewModel.launchDatabaseTool(.dbeaver) } }
            }
        }
    }

    private var wordpressActions: some View {
        actionSection("WordPress") {
            Button("Update Core") {
                Task { await viewModel.updateWordPressCore() }
            }
            Button("Update Plugins") {
                Task { await viewModel.updateWordPressPlugins() }
            }
            Button("Update Themes") {
                Task { await viewModel.updateWordPressThemes() }
            }
        }
    }

    private var dangerActions: some View {
        actionSection("Danger") {
            Button("Unlink From List", role: .destructive) {
                confirmUnlink = true
            }
            Button("Delete DDEV Data", role: .destructive) {
                confirmDeleteDDEVData = true
            }
            Button("Delete Source Folder", role: .destructive) {
                showSourceDeleteSheet = true
            }
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

private struct SourceFolderDeleteSheet: View {
    let project: DDEVProject
    @ObservedObject var viewModel: ProjectDashboardViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var confirmationText = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Delete Source Folder")
                .font(.title2.bold())

            Text("This moves the source folder to Trash. It is separate from DDEV data deletion.")
                .foregroundStyle(.secondary)

            Text(project.appRoot)
                .font(.caption)
                .textSelection(.enabled)

            TextField("Type \(project.name) to confirm", text: $confirmationText)
                .textFieldStyle(.roundedBorder)

            HStack {
                Spacer()
                Button("Cancel") {
                    dismiss()
                }
                Button("Move To Trash", role: .destructive) {
                    viewModel.moveSelectedProjectFolderToTrash()
                    dismiss()
                }
                .disabled(confirmationText != project.name)
            }
        }
        .padding()
        .frame(width: 480)
    }
}
