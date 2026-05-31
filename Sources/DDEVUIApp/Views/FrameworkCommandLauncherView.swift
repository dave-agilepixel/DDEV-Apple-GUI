import SwiftUI

struct FrameworkCommandLauncherView: View {
    let project: DDEVProject
    var viewModel: ProjectDashboardViewModel
    @State private var pendingCommand: DDEVFrameworkCommand?

    private var commands: [DDEVFrameworkCommand] {
        viewModel.frameworkCommands(for: project)
    }

    private var groups: [FrameworkCommandGroup] {
        // O(n) grouping that preserves first-seen group order, instead of the previous
        // O(n²) reduce + firstIndex per command (audit L1).
        var order: [String] = []
        var commandsByTitle: [String: [DDEVFrameworkCommand]] = [:]
        for command in commands {
            if commandsByTitle[command.groupTitle] == nil {
                order.append(command.groupTitle)
            }
            commandsByTitle[command.groupTitle, default: []].append(command)
        }
        return order.map { FrameworkCommandGroup(title: $0, commands: commandsByTitle[$0] ?? []) }
    }

    var body: some View {
        if !commands.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Commands")
                        .sectionHeaderStyle()
                    Spacer()
                }

                HStack(spacing: 8) {
                    ForEach(groups) { group in
                        Menu {
                            ForEach(group.commands) { command in
                                Button {
                                    run(command)
                                } label: {
                                    Label(command.title, systemImage: command.systemImage)
                                }
                            }
                        } label: {
                            Label(group.title, systemImage: "terminal")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .disabled(viewModel.isSelectedProjectBusy)
                    }
                    Spacer(minLength: 0)
                }
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
    }

    private func run(_ command: DDEVFrameworkCommand) {
        if command.requiresConfirmation {
            pendingCommand = command
        } else {
            Task { await viewModel.runFrameworkCommandForSelectedProject(command) }
        }
    }
}

private struct FrameworkCommandGroup: Identifiable {
    let title: String
    var commands: [DDEVFrameworkCommand]

    var id: String { title }
}
