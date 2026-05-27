import SwiftUI

struct ContentView: View {
    @StateObject private var viewModel = ProjectDashboardViewModel()
    @State private var folderToConfigure: FolderToConfigure?

    var body: some View {
        NavigationSplitView {
            List(selection: $viewModel.selectedSidebarItem) {
                ForEach(ProjectSidebarItem.allCases) { item in
                    Label(item.title, systemImage: item.systemImage)
                        .tag(item)
                }
            }
            .navigationTitle("DDEVUI")
        } content: {
            if viewModel.selectedSidebarItem == .settings {
                SettingsView(viewModel: viewModel)
            } else {
                ProjectListView(viewModel: viewModel)
            }
        } detail: {
            ProjectInspectorView(viewModel: viewModel)
        }
        .task {
            await viewModel.refresh()
        }
        .toolbar {
            Button {
                addFolder()
            } label: {
                Label("Add Folder", systemImage: "folder.badge.plus")
            }

            Button {
                Task { await viewModel.refresh() }
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
        }
        .sheet(item: $folderToConfigure) { folder in
            AddProjectSheet(folder: folder.url, viewModel: viewModel)
        }
    }

    private func addFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false

        guard panel.runModal() == .OK, let folder = panel.url else { return }

        let configPath = folder
            .appendingPathComponent(".ddev")
            .appendingPathComponent("config.yaml")
            .path

        if FileManager.default.fileExists(atPath: configPath) {
            Task { await viewModel.startProject(atFolder: folder.path) }
        } else {
            folderToConfigure = FolderToConfigure(url: folder)
        }
    }
}

private struct FolderToConfigure: Identifiable {
    let url: URL
    var id: String { url.path }
}

#Preview {
    ContentView()
}

private struct SettingsView: View {
    @ObservedObject var viewModel: ProjectDashboardViewModel

    var body: some View {
        Form {
            Section("DDEV") {
                LabeledContent("Projects") {
                    Text("\(viewModel.projects.count)")
                }
                LabeledContent("Running") {
                    Text("\(viewModel.projects.filter { $0.status == .running }.count)")
                }
                LabeledContent("WordPress") {
                    Text("\(viewModel.projects.filter { $0.isWordPress }.count)")
                }
                LabeledContent("PHP presets") {
                    Text(viewModel.supportedPHPVersions.joined(separator: ", "))
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Settings")
    }
}

private struct AddProjectSheet: View {
    let folder: URL
    @ObservedObject var viewModel: ProjectDashboardViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var projectName: String
    @State private var projectType: DDEVProjectType = .wordpress
    @State private var docroot = ""

    init(folder: URL, viewModel: ProjectDashboardViewModel) {
        self.folder = folder
        self.viewModel = viewModel
        _projectName = State(initialValue: folder.lastPathComponent)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Configure DDEV Project")
                .font(.title2.bold())

            Text(folder.path)
                .font(.caption)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)

            Form {
                TextField("Project name", text: $projectName)

                Picker("Project type", selection: $projectType) {
                    Text("WordPress").tag(DDEVProjectType.wordpress)
                    Text("WP Bedrock").tag(DDEVProjectType.wpBedrock)
                    Text("Laravel").tag(DDEVProjectType.laravel)
                    Text("Generic").tag(DDEVProjectType.generic)
                }

                TextField("Docroot", text: $docroot, prompt: Text("Leave blank for project root"))
            }

            HStack {
                Spacer()
                Button("Cancel") {
                    dismiss()
                }
                Button("Configure") {
                    Task {
                        await viewModel.configureProject(
                            folder: folder.path,
                            name: projectName,
                            type: projectType,
                            docroot: docroot
                        )
                        dismiss()
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(projectName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding()
        .frame(width: 460)
    }
}
