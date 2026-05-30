import SwiftUI

struct SnapshotManagerView: View {
    let project: DDEVProject
    @ObservedObject var viewModel: ProjectDashboardViewModel

    @State private var snapshotName = ""
    @State private var lastSuggestedSnapshotName = ""
    @State private var selectedSnapshotID: DDEVSnapshot.ID?
    @State private var pendingConfirmation: SnapshotConfirmation?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Snapshots")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                    .kerning(0.5)
                Spacer()
                Button {
                    Task { await viewModel.loadSnapshotsForSelectedProject() }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .labelStyle(.iconOnly)
                .help("Refresh snapshots")
                .disabled(viewModel.isSelectedProjectBusy)
            }

            HStack(spacing: 8) {
                TextField("Snapshot name", text: $snapshotName)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 260)

                Button {
                    Task {
                        await viewModel.createSnapshotForSelectedProject(name: snapshotName)
                        updateSuggestedSnapshotName(force: true)
                    }
                } label: {
                    Label("Create", systemImage: "plus")
                }
                .disabled(viewModel.isSelectedProjectBusy || snapshotName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                Button {
                    pendingConfirmation = .restoreLatest
                } label: {
                    Label("Restore Latest", systemImage: "clock.arrow.circlepath")
                }
                .disabled(viewModel.isSelectedProjectBusy)

                Button(role: .destructive) {
                    pendingConfirmation = .cleanupAll
                } label: {
                    Label("Clean Up All", systemImage: "trash")
                }
                .disabled(viewModel.isSelectedProjectBusy || viewModel.snapshots.isEmpty)

                Spacer(minLength: 0)
            }
            .buttonStyle(.bordered)
            .controlSize(.regular)
            .labelStyle(.titleAndIcon)

            if viewModel.snapshots.isEmpty {
                ContentUnavailableView(
                    "No Snapshots",
                    systemImage: "camera.metering.none",
                    description: Text("Create a named snapshot or refresh the list.")
                )
                .frame(maxWidth: .infinity, minHeight: 120)
            } else {
                snapshotList
            }
        }
        .task(id: project.id) {
            updateSuggestedSnapshotName()
            await viewModel.loadSnapshotsForSelectedProject()
        }
        .confirmationDialog(confirmationTitle, isPresented: confirmationBinding, presenting: pendingConfirmation) { confirmation in
            switch confirmation {
            case .restore(let snapshot):
                Button("Restore \(snapshot.name)", role: .destructive) {
                    Task { await viewModel.restoreSnapshotForSelectedProject(named: snapshot.name) }
                }
            case .restoreLatest:
                Button("Restore Latest Snapshot", role: .destructive) {
                    Task { await viewModel.restoreLatestSnapshotForSelectedProject() }
                }
            case .cleanupAll:
                Button("Clean Up All Snapshots", role: .destructive) {
                    Task { await viewModel.cleanupSnapshotsForSelectedProject() }
                }
            case .cleanup(let snapshot):
                Button("Delete \(snapshot.name)", role: .destructive) {
                    Task { await viewModel.cleanupSnapshotForSelectedProject(named: snapshot.name) }
                }
            }

            Button("Cancel", role: .cancel) {}
        } message: { confirmation in
            Text(confirmation.message(for: project))
        }
        .onChange(of: viewModel.snapshots) { _, snapshots in
            if let selectedSnapshotID, !snapshots.contains(where: { $0.id == selectedSnapshotID }) {
                self.selectedSnapshotID = snapshots.first?.id
            } else if selectedSnapshotID == nil {
                selectedSnapshotID = snapshots.first?.id
            }
        }
    }

    private var snapshotList: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(viewModel.snapshots) { snapshot in
                HStack(spacing: 10) {
                    Button {
                        selectedSnapshotID = snapshot.id
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: selectedSnapshotID == snapshot.id ? "largecircle.fill.circle" : "circle")

                            VStack(alignment: .leading, spacing: 2) {
                                Text(snapshot.name)
                                    .font(.callout.weight(.medium))
                                if let databaseSuffix = snapshot.databaseSuffix {
                                    Text(databaseSuffix)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.primary)
                    .help("Select snapshot")
                    .accessibilityLabel("Select \(snapshot.name)")

                    Spacer(minLength: 0)

                    Button {
                        pendingConfirmation = .restore(snapshot)
                    } label: {
                        Label("Restore", systemImage: "arrow.counterclockwise")
                    }

                    Button(role: .destructive) {
                        pendingConfirmation = .cleanup(snapshot)
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
                .padding(.vertical, 6)
            }
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .disabled(viewModel.isSelectedProjectBusy)
    }

    private var confirmationBinding: Binding<Bool> {
        Binding(
            get: { pendingConfirmation != nil },
            set: { isPresented in
                if !isPresented {
                    pendingConfirmation = nil
                }
            }
        )
    }

    private var confirmationTitle: String {
        pendingConfirmation?.title ?? "Confirm Snapshot Action"
    }

    private func updateSuggestedSnapshotName(force: Bool = false) {
        let shouldUseSuggestion = force
            || snapshotName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || snapshotName == lastSuggestedSnapshotName

        guard shouldUseSuggestion else { return }

        let suggestedName = DDEVSnapshot.suggestedName(projectName: project.name)
        snapshotName = suggestedName
        lastSuggestedSnapshotName = suggestedName
    }
}

private enum SnapshotConfirmation: Identifiable {
    case restore(DDEVSnapshot)
    case restoreLatest
    case cleanupAll
    case cleanup(DDEVSnapshot)

    var id: String {
        switch self {
        case .restore(let snapshot):
            "restore-\(snapshot.id)"
        case .restoreLatest:
            "restore-latest"
        case .cleanupAll:
            "cleanup-all"
        case .cleanup(let snapshot):
            "cleanup-\(snapshot.id)"
        }
    }

    var title: String {
        switch self {
        case .restore:
            "Restore this snapshot?"
        case .restoreLatest:
            "Restore the latest snapshot?"
        case .cleanupAll:
            "Clean up all snapshots?"
        case .cleanup:
            "Delete this snapshot?"
        }
    }

    func message(for project: DDEVProject) -> String {
        switch self {
        case .restore(let snapshot):
            "This restores \(snapshot.name) into \(project.name)'s local database."
        case .restoreLatest:
            "This restores the newest available snapshot into \(project.name)'s local database."
        case .cleanupAll:
            "This deletes every snapshot for \(project.name)."
        case .cleanup(let snapshot):
            "This deletes \(snapshot.name) from \(project.name)'s local snapshots."
        }
    }
}
