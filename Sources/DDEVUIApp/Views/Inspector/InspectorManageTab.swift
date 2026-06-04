import AppKit
import SwiftUI

// MARK: - Manage tab

/// A10 — tool passthrough: run `ddev composer/npm/drush/wp` with free-text arguments. The available
/// tools are derived from the project type. Output flows into the Logs-tab command output.
struct ToolRunnerView: View {
    let project: DDEVProject
    var viewModel: ProjectDashboardViewModel

    private var tools: [DDEVTool] { DDEVTool.tools(for: project.projectType) }

    var body: some View {
        InspectorSection("Tools") {
            VStack(alignment: .leading, spacing: 10) {
                Text("Run a tool inside the web container with your own arguments (ddev <tool> …). Output appears under the Logs tab.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                ForEach(tools) { tool in
                    ToolRow(tool: tool, project: project, viewModel: viewModel)
                }

                if project.status != .running {
                    Text("Start the project to run tools.")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }
}

struct ToolRow: View {
    let tool: DDEVTool
    let project: DDEVProject
    var viewModel: ProjectDashboardViewModel

    @State private var args = ""

    var body: some View {
        HStack(spacing: 8) {
            Text(tool.displayName)
                .font(.callout.weight(.medium))
                .frame(width: 84, alignment: .leading)

            TextField(tool.placeholder, text: $args)
                .textFieldStyle(.roundedBorder)
                .font(.system(.body, design: .monospaced))
                .onSubmit(run)

            Button("Run", action: run)
                .disabled(!canRun)
        }
    }

    private var canRun: Bool {
        project.status == .running
            && !viewModel.isSelectedProjectBusy
            && !args.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func run() {
        guard canRun else { return }
        let toRun = args
        Task { await viewModel.runToolForSelectedProject(tool, argumentString: toRun) }
    }
}

/// A9 — run an arbitrary one-shot command inside a service container (`ddev exec`). Output flows
/// into the normal command-output channel (Logs tab). The command is run via `bash -c`, so pipes
/// and shell features work.
struct ExecConsoleView: View {
    let project: DDEVProject
    var viewModel: ProjectDashboardViewModel

    @State private var command = ""
    @State private var service: DDEVExecService = .web

    var body: some View {
        InspectorSection("Run Command") {
            VStack(alignment: .leading, spacing: 10) {
                Text("Run a one-shot shell command inside a container (ddev exec). Output appears under the Logs tab.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack(spacing: 8) {
                    Picker("Service", selection: $service) {
                        ForEach(DDEVExecService.allCases) { service in
                            Text(service.displayName).tag(service)
                        }
                    }
                    .labelsHidden()
                    .fixedSize()

                    TextField("e.g. composer install", text: $command)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))
                        .onSubmit(run)

                    Button("Run", action: run)
                        .buttonStyle(.borderedProminent)
                        .disabled(!canRun)
                }

                if project.status != .running {
                    Text("Start the project to run commands in its containers.")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }

    private var canRun: Bool {
        project.status == .running
            && !viewModel.isSelectedProjectBusy
            && !command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func run() {
        guard canRun else { return }
        let toRun = command
        Task { await viewModel.runExecForSelectedProject(command: toRun, service: service) }
    }
}

/// A13 — surfaces user-defined custom commands (`.ddev/commands/…`) discovered at runtime as
/// buttons. Hidden entirely when the project defines none.
struct CustomCommandsView: View {
    let project: DDEVProject
    var viewModel: ProjectDashboardViewModel

    var body: some View {
        if !viewModel.customCommands.isEmpty {
            InspectorSection("Custom Commands") {
                FlowHStack(spacing: 8) {
                    ForEach(viewModel.customCommands) { command in
                        Button {
                            Task { await viewModel.runCustomCommandForSelectedProject(command) }
                        } label: {
                            Label(command.name, systemImage: "terminal")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .help(command.description ?? "ddev \(command.name) (\(command.scope.rawValue))")
                    }
                }
                .disabled(viewModel.isSelectedProjectBusy)
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
            VStack(alignment: .leading, spacing: 24) {
                FrameworkCommandLauncherView(project: project, viewModel: viewModel)
                CustomCommandsView(project: project, viewModel: viewModel)
                ToolRunnerView(project: project, viewModel: viewModel)
                ExecConsoleView(project: project, viewModel: viewModel)
                DatabaseOperationsView(project: project, viewModel: viewModel)
                ShareView(project: project, viewModel: viewModel)
                SnapshotManagerView(project: project, viewModel: viewModel)
                AddonManagerView(project: project, viewModel: viewModel)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollContentBackground(.hidden)
    }
}
