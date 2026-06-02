import AppKit
import SwiftUI

/// B1 — the menu-bar dropdown: every project with inline start/stop/restart/launch, plus refresh
/// and a way back to the main window. Shares the App's view model, so it reflects the same live
/// data (kept fresh by B2's status poll + the Refresh item here).
struct MenuBarContentView: View {
    var viewModel: ProjectDashboardViewModel
    @Environment(\.openWindow) private var openWindow
    private let workspaceOpener = MacWorkspaceOpener()

    private var sortedProjects: [DDEVProject] {
        viewModel.projects.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    var body: some View {
        if sortedProjects.isEmpty {
            Text("No DDEV projects")
        } else {
            let runningCount = viewModel.projects.filter { $0.status == .running }.count
            Text("\(viewModel.projects.count) projects · \(runningCount) running")

            ForEach(sortedProjects) { project in
                projectMenu(project)
            }
        }

        Divider()

        Button("Refresh") {
            Task { await viewModel.refresh() }
        }

        Button("Open DDEVUI Window") {
            openWindow(id: DDEVUIApp.mainWindowID)
            NSApp.activate(ignoringOtherApps: true)
        }

        Divider()

        Button("Quit DDEVUI") {
            NSApp.terminate(nil)
        }
        .keyboardShortcut("q")
    }

    @ViewBuilder
    private func projectMenu(_ project: DDEVProject) -> some View {
        Menu("\(project.status == .running ? "🟢" : "⚪︎") \(project.name)") {
            if project.status == .running {
                if let url = project.primaryURL {
                    Button("Open Site") { workspaceOpener.openURL(url) }
                }
                Button("Restart") { Task { await viewModel.restart(project) } }
                Button("Stop") { Task { await viewModel.stop(project) } }
            } else {
                Button("Start") { Task { await viewModel.start(project) } }
            }
        }
        .disabled(viewModel.isBusy(project))
    }
}
