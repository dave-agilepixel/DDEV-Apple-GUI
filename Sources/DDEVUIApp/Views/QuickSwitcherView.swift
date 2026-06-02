import SwiftUI

/// B6 — a ⌘K command-palette-style switcher: type to filter projects across all sections, Return
/// (or click) to jump to one. Esc cancels (the sheet's default).
struct QuickSwitcherView: View {
    var viewModel: ProjectDashboardViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var query = ""
    @FocusState private var fieldFocused: Bool

    private var matches: [DDEVProject] { viewModel.projectsMatching(query) }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Jump to project…", text: $query)
                    .textFieldStyle(.plain)
                    .font(.title3)
                    .focused($fieldFocused)
                    .onSubmit(selectFirst)
            }
            .padding(14)

            Divider()

            if matches.isEmpty {
                Text("No matching projects")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(20)
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(matches) { project in
                            Button {
                                select(project)
                            } label: {
                                HStack(spacing: 10) {
                                    Circle()
                                        .fill(project.status == .running ? Color.green : Color.secondary.opacity(0.5))
                                        .frame(width: 8, height: 8)
                                    Text(project.name)
                                        .fontWeight(.medium)
                                    Spacer()
                                    Text(project.projectType.displayName)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .frame(maxHeight: 320)
            }
        }
        .frame(width: 460)
        .onAppear { fieldFocused = true }
    }

    private func selectFirst() {
        if let first = matches.first { select(first) }
    }

    private func select(_ project: DDEVProject) {
        viewModel.revealAndSelectProject(project.id)
        dismiss()
    }
}
