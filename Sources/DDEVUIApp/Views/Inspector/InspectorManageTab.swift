import AppKit
import SwiftUI

// MARK: - Manage tab

/// Run card — framework + custom command dropdowns plus one unified runner (tools + exec).
struct RunCard: View {
    let project: DDEVProject
    var viewModel: ProjectDashboardViewModel

    var body: some View {
        InspectorCard("Run", systemImage: "play.fill") {
            VStack(alignment: .leading, spacing: 12) {
                Text("Commands and tools run inside the project's containers. Output appears in the Logs tab.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                FrameworkCommandLauncherView(project: project, viewModel: viewModel)

                if !viewModel.customCommands.isEmpty {
                    Menu {
                        ForEach(viewModel.customCommands) { command in
                            Button {
                                Task { await viewModel.runCustomCommandForSelectedProject(command) }
                            } label: {
                                Label(command.name, systemImage: "terminal")
                            }
                            .help(command.description ?? "ddev \(command.name) (\(command.scope.rawValue))")
                        }
                    } label: {
                        Label("Custom", systemImage: "star")
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                    .disabled(viewModel.isSelectedProjectBusy)
                }

                RunCommandRow(project: project, viewModel: viewModel)

                if project.status != .running {
                    Text("Start the project to run commands.")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }
}

/// The unified runner: a target picker (tools + exec services) + an arguments field + Run.
private struct RunCommandRow: View {
    let project: DDEVProject
    var viewModel: ProjectDashboardViewModel

    @State private var target: RunTarget
    @State private var args = ""

    init(project: DDEVProject, viewModel: ProjectDashboardViewModel) {
        self.project = project
        self.viewModel = viewModel
        _target = State(initialValue: RunTarget.available(for: project.projectType).first ?? .exec(.web))
    }

    private var targets: [RunTarget] { RunTarget.available(for: project.projectType) }

    private var canRun: Bool {
        project.status == .running
            && !viewModel.isSelectedProjectBusy
            && !args.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        HStack(spacing: 8) {
            Picker("Target", selection: $target) {
                ForEach(targets) { t in
                    Text(t.label).tag(t)
                }
            }
            .labelsHidden()
            .fixedSize()

            TextField(target.placeholder, text: $args)
                .textFieldStyle(.roundedBorder)
                .font(.system(.body, design: .monospaced))
                .onSubmit(run)

            Button("Run", action: run)
                .buttonStyle(.borderedProminent)
                .disabled(!canRun)
        }
        // If the project's type changes in place (e.g. a config edit), the available targets shift —
        // clamp the selection so a stale target can't fire the wrong tool.
        .onChange(of: targets) { _, newTargets in
            if !newTargets.contains(target) {
                target = newTargets.first ?? .exec(.web)
            }
        }
    }

    private func run() {
        guard canRun else { return }
        let toRun = args
        let chosen = target
        Task {
            switch chosen {
            case .tool(let tool):
                await viewModel.runToolForSelectedProject(tool, argumentString: toRun)
            case .exec(let service):
                await viewModel.runExecForSelectedProject(command: toRun, service: service)
            }
        }
    }
}

/// A8 — expose the project on a temporary public URL via `ddev share`. Shows the parsed tunnel URL
/// with open/copy, and a prominent Stop control. The tunnel is a long-running process owned by the
/// view model.
struct ShareView: View {
    let project: DDEVProject
    var viewModel: ProjectDashboardViewModel
    private let workspaceOpener = MacWorkspaceOpener()

    var body: some View {
        InspectorSection("Share") {
            VStack(alignment: .leading, spacing: 10) {
                Text("Expose this project on a temporary public URL (ddev share). Anyone with the link can reach your local site — stop sharing when you're done.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                content

                if project.status != .running {
                    Text("Start the project to share it.")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.shareState {
        case .idle, .stopped, .failed:
            Button {
                viewModel.startSharing()
            } label: {
                Label("Start Sharing", systemImage: "antenna.radiowaves.left.and.right")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .disabled(project.status != .running)

            if case .failed(let message) = viewModel.shareState {
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

        case .starting:
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Starting tunnel…").foregroundStyle(.secondary)
                Spacer()
                Button("Stop", role: .destructive) { viewModel.stopSharing() }
                    .controlSize(.small)
            }

        case .running(let url):
            HStack(spacing: 8) {
                Image(systemName: "antenna.radiowaves.left.and.right")
                    .foregroundStyle(.green)
                if let url {
                    Text(url)
                        .font(.system(.callout, design: .monospaced))
                        .textSelection(.enabled)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Button {
                        if let parsed = URL(string: url) { workspaceOpener.openURL(parsed) }
                    } label: { Image(systemName: "safari") }
                        .buttonStyle(.borderless)
                        .help("Open the public URL")
                    Button { Pasteboard.copy(url) } label: { Image(systemName: "doc.on.doc") }
                        .buttonStyle(.borderless)
                        .help("Copy the public URL")
                } else {
                    Text("Tunnel running…").foregroundStyle(.secondary)
                }
                Spacer()
                Button("Stop Sharing", role: .destructive) { viewModel.stopSharing() }
                    .controlSize(.small)
            }
        }
    }
}

struct ManageTabContent: View {
    let project: DDEVProject
    var viewModel: ProjectDashboardViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                RunCard(project: project, viewModel: viewModel)

                Grid(alignment: .topLeading, horizontalSpacing: 12, verticalSpacing: 12) {
                    GridRow {
                        InspectorCard("Database", systemImage: "cylinder.split.1x2") {
                            VStack(alignment: .leading, spacing: 12) {
                                DatabaseOperationsView(project: project, viewModel: viewModel)
                                SnapshotManagerView(project: project, viewModel: viewModel)
                            }
                        }
                        InspectorCard("Project", systemImage: "gearshape") {
                            VStack(alignment: .leading, spacing: 12) {
                                ShareView(project: project, viewModel: viewModel)
                                AddonManagerView(project: project, viewModel: viewModel)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollContentBackground(.hidden)
    }
}
