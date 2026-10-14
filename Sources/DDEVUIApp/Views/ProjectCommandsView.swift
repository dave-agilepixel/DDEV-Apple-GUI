import SwiftUI

/// The Manage tab's single Commands section: one free-form runner (`ddev exec` and the tool
/// passthroughs — A9/A10) above one searchable list of the framework presets and the project's
/// custom commands (A13). Output flows into the Logs tab.
struct ProjectCommandsView: View {
    let project: DDEVProject
    var viewModel: ProjectDashboardViewModel

    @State private var runner: Runner = .exec(.web)
    @State private var input = ""
    @State private var query = ""
    @State private var showsAll = false
    @State private var pendingCommand: DDEVFrameworkCommand?

    var body: some View {
        Section {
            runnerRow

            if hasCustomCommands {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("Search commands", text: $query, prompt: Text("Search \(entries.count) commands"))
                        .labelsHidden()
                }
            }

            ForEach(visibleEntries) { entry in
                LabeledContent {
                    Button("Run") { run(entry) }
                        .disabled(viewModel.isSelectedProjectBusy)
                } label: {
                    Text(entry.title)
                    Text(entry.subtitle)
                }
            }

            if isSearching, visibleEntries.isEmpty {
                Text("No commands match “\(trimmedQuery)”.")
                    .foregroundStyle(.secondary)
            }

            if !isSearching, hasCustomCommands {
                Button(showsAll ? "Show Fewer" : "Show All \(entries.count) Commands") {
                    showsAll.toggle()
                }
                .buttonStyle(.link)
            }
        } header: {
            Text("Commands")
        } footer: {
            Text("Output appears in the Logs tab.")
        }
        .confirmationDialog(
            pendingCommand?.title ?? "Run Command?",
            isPresented: .isPresent($pendingCommand),
            presenting: pendingCommand
        ) { command in
            Button("Run", role: command.risk == .destructive ? .destructive : nil) {
                Task { await viewModel.runFrameworkCommandForSelectedProject(command) }
            }
            Button("Cancel", role: .cancel) {}
        } message: { command in
            Text(command.confirmationMessage ?? "Run this command for \(project.name)?")
        }
    }

    // MARK: - Free-form runner

    private var runnerRow: some View {
        HStack(spacing: 8) {
            Picker("Run with", selection: $runner) {
                ForEach(DDEVExecService.allCases) { service in
                    Text("Shell — \(service.displayName)").tag(Runner.exec(service))
                }
                Divider()
                ForEach(DDEVTool.tools(for: project.projectType)) { tool in
                    Text(tool.displayName).tag(Runner.tool(tool))
                }
            }
            .labelsHidden()
            .fixedSize()

            TextField("Command", text: $input, prompt: Text(runner.placeholder))
                .labelsHidden()
                .font(.system(.body, design: .monospaced))
                .onSubmit(runInput)

            Button("Run", action: runInput)
                .buttonStyle(.borderedProminent)
                .disabled(!canRunInput)
        }
    }

    private var canRunInput: Bool {
        project.status == .running
            && !viewModel.isSelectedProjectBusy
            && !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func runInput() {
        guard canRunInput else { return }
        let toRun = input
        Task {
            switch runner {
            case .exec(let service):
                await viewModel.runExecForSelectedProject(command: toRun, service: service)
            case .tool(let tool):
                await viewModel.runToolForSelectedProject(tool, argumentString: toRun)
            }
        }
    }

    // MARK: - Saved commands

    private var presets: [Entry] {
        viewModel.frameworkCommands(for: project).map(Entry.framework)
    }

    private var entries: [Entry] {
        presets + viewModel.customCommands.map(Entry.custom)
    }

    /// Custom commands stay behind search or "Show All": DDEV ships ~35 global ones (`artisan`,
    /// `magento`, `typo3`, …) and most are irrelevant to any one project.
    private var hasCustomCommands: Bool { !viewModel.customCommands.isEmpty }

    private var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var isSearching: Bool { !trimmedQuery.isEmpty }

    private var visibleEntries: [Entry] {
        if isSearching {
            return entries.filter {
                $0.title.localizedCaseInsensitiveContains(trimmedQuery)
                    || $0.subtitle.localizedCaseInsensitiveContains(trimmedQuery)
            }
        }
        return showsAll ? entries : presets
    }

    private func run(_ entry: Entry) {
        switch entry {
        case .framework(let command) where command.requiresConfirmation:
            pendingCommand = command
        case .framework(let command):
            Task { await viewModel.runFrameworkCommandForSelectedProject(command) }
        case .custom(let command):
            Task { await viewModel.runCustomCommandForSelectedProject(command) }
        }
    }
}

/// What the free-form field runs its text through.
private enum Runner: Hashable {
    case exec(DDEVExecService)
    case tool(DDEVTool)

    var placeholder: String {
        switch self {
        case .exec: "ls -la"
        case .tool(let tool): tool.placeholder
        }
    }
}

/// A saved command: a framework preset or a custom command discovered in `.ddev/commands`.
private enum Entry: Identifiable {
    case framework(DDEVFrameworkCommand)
    case custom(DDEVCustomCommand)

    var id: String {
        switch self {
        case .framework(let command): "framework:\(command.id)"
        case .custom(let command): "custom:\(command.id)"
        }
    }

    var title: String {
        switch self {
        case .framework(let command): command.title
        case .custom(let command): command.name
        }
    }

    var subtitle: String {
        switch self {
        case .framework(let command): "ddev \(command.arguments.joined(separator: " "))"
        case .custom(let command): command.description ?? "ddev \(command.name)"
        }
    }
}
