import SwiftUI

extension GroupColor {
    var color: Color {
        switch self {
        case .blue: .blue
        case .teal: .teal
        case .green: .green
        case .yellow: .yellow
        case .orange: .orange
        case .red: .red
        case .purple: .purple
        case .gray: .gray
        }
    }
}

/// Drag payload for assigning a project (a list row) onto a sidebar group.
///
/// Uses a plain-text proxy of the project id so it relies only on the always-registered text
/// UTType. A custom `UTType(exportedAs:)` would require an `Info.plist` `UTExportedTypeDeclarations`
/// entry — absent here (`GENERATE_INFOPLIST_FILE = YES`, no Info.plist) — and without that
/// declaration the system doesn't recognise the type identifier, so the drop silently no-ops.
struct ProjectTransfer: Transferable {
    let projectID: String
    static var transferRepresentation: some TransferRepresentation {
        ProxyRepresentation(exporting: \.projectID)
    }
}

/// A sidebar row for one group: colour dot + name + member-count badge.
struct GroupSidebarRow: View {
    let group: ProjectGroup
    let count: Int

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(group.colorID.color)
                .frame(width: 9, height: 9)
            Text(group.name)
                .lineLimit(1)
            Spacer(minLength: 0)
            if count > 0 {
                Text("\(count)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .background(Capsule().fill(.quaternary.opacity(0.6)))
            }
        }
    }
}

/// Inline "new group" editor: a name field + the 8-swatch colour picker.
struct NewGroupEditor: View {
    @Bindable var viewModel: ProjectDashboardViewModel
    @State private var name = ""
    @State private var color: GroupColor = .blue
    @FocusState private var nameFocused: Bool
    var onDone: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            TextField("Group name", text: $name)
                .textFieldStyle(.roundedBorder)
                .focused($nameFocused)
                .onSubmit(create)
            HStack(spacing: 6) {
                ForEach(GroupColor.allCases, id: \.self) { swatch in
                    Circle()
                        .fill(swatch.color)
                        .frame(width: 18, height: 18)
                        .overlay(Circle().strokeBorder(.primary, lineWidth: color == swatch ? 2 : 0))
                        .onTapGesture { color = swatch }
                        .accessibilityLabel(swatch.rawValue)
                }
            }
            HStack {
                Spacer()
                Button("Cancel", role: .cancel, action: onDone)
                Button("Create", action: create)
                    .buttonStyle(.borderedProminent)
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(12)
        .frame(width: 260)
        .onAppear { nameFocused = true }
    }

    private func create() {
        guard viewModel.createGroup(name: name, color: color) != nil else { return }
        onDone()
    }
}

/// Edit a group's name and colour. Colour selection lives here (a normal view) rather than in the
/// sidebar context menu, because macOS renders menu-item SF Symbols as monochrome templates — so
/// coloured swatches can't show their colour inside a `Menu`.
struct EditGroupSheet: View {
    @Bindable var viewModel: ProjectDashboardViewModel
    let group: ProjectGroup
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var color: GroupColor

    init(viewModel: ProjectDashboardViewModel, group: ProjectGroup) {
        self.viewModel = viewModel
        self.group = group
        _name = State(initialValue: group.name)
        _color = State(initialValue: group.colorID)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Edit Group").font(.headline)
            TextField("Group name", text: $name)
                .textFieldStyle(.roundedBorder)
                .onSubmit(commit)
            HStack(spacing: 6) {
                ForEach(GroupColor.allCases, id: \.self) { swatch in
                    Circle()
                        .fill(swatch.color)
                        .frame(width: 18, height: 18)
                        .overlay(Circle().strokeBorder(.primary, lineWidth: color == swatch ? 2 : 0))
                        .onTapGesture { color = swatch }
                        .accessibilityLabel(swatch.rawValue)
                }
            }
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                Button("Save", action: commit)
                    .buttonStyle(.borderedProminent)
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 320)
    }

    private func commit() {
        viewModel.renameGroup(group.id, to: name)
        viewModel.setColor(color, for: group.id)
        dismiss()
    }
}
