import SwiftUI

struct SnapshotManagerView: View {
    let project: DDEVProject
    var viewModel: ProjectDashboardViewModel

    @State private var snapshotName = ""
    @State private var lastSuggestedSnapshotName = ""
    @State private var pendingConfirmation: SnapshotConfirmation?

    var body: some View {
        Section {
            HStack(spacing: 8) {
                TextField("New snapshot", text: $snapshotName, prompt: Text("Snapshot name"))

                Button("Create") {
                    Task {
                        await viewModel.createSnapshotForSelectedProject(name: snapshotName)
                        updateSuggestedSnapshotName(force: true)
                    }
                }
                .disabled(snapshotName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            if let snapshotErrorMessage = viewModel.snapshotErrorMessage {
                Label(snapshotErrorMessage, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
            }

            if viewModel.snapshots.isEmpty {
                Text("No snapshots yet.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(viewModel.snapshots) { snapshot in
                    LabeledContent {
                        Button("Restore") { pendingConfirmation = .restore(snapshot) }

                        Button(role: .destructive) {
                            pendingConfirmation = .cleanup(snapshot)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                        .labelStyle(.iconOnly)
                        .help("Delete this snapshot")
                    } label: {
                        Text(snapshot.name)
                        if let databaseSuffix = snapshot.databaseSuffix {
                            Text(databaseSuffix)
                        }
                    }
                }
            }
        } header: {
            HStack {
                Text("Snapshots")
                Spacer()
                Menu {
                    Button("Refresh") {
                        Task { await viewModel.loadSnapshotsForSelectedProject() }
                    }
                    Button("Restore Latest…") { pendingConfirmation = .restoreLatest }
                    Divider()
                    Button("Clean Up All…", role: .destructive) { pendingConfirmation = .cleanupAll }
                        .disabled(viewModel.snapshots.isEmpty)
                } label: {
                    Label("Snapshot actions", systemImage: "ellipsis.circle")
                        .labelStyle(.iconOnly)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
            }
        }
        .disabled(viewModel.isSelectedProjectBusy)
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
    }

    private var confirmationBinding: Binding<Bool> {
        .isPresent($pendingConfirmation)
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
