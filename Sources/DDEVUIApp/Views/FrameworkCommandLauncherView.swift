import SwiftUI

struct FrameworkCommandLauncherView: View {
    let project: DDEVProject
    @ObservedObject var viewModel: ProjectDashboardViewModel
    @State private var pendingCommand: DDEVFrameworkCommand?

    private var commands: [DDEVFrameworkCommand] {
        viewModel.frameworkCommands(for: project)
    }

    private var groups: [FrameworkCommandGroup] {
        commands.reduce(into: []) { groups, command in
            if let index = groups.firstIndex(where: { $0.title == command.groupTitle }) {
                groups[index].commands.append(command)
            } else {
                groups.append(FrameworkCommandGroup(title: command.groupTitle, commands: [command]))
            }
        }
    }

    var body: some View {
        if !commands.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Commands")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                        .kerning(0.5)
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
                isPresented: Binding(
                    get: { pendingCommand != nil },
                    set: { isPresented in
                        if !isPresented {
                            pendingCommand = nil
                        }
                    }
                ),
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
