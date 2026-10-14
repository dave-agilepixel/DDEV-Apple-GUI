import SwiftUI

/// Shows what is consuming the Docker VM's disk and offers a safe-by-default reclaim.
/// Follows the `DiagnosticsView` full-pane layout.
struct DockerDiskView: View {
    var viewModel: DockerDiskViewModel
    var dashboard: ProjectDashboardViewModel

    @State private var confirmReclaim = false
    @State private var volumePendingRemoval: ClassifiedVolume?
    /// Volume names ticked in the Project databases list.
    @State private var selectedDatabases: Set<String> = []
    @State private var confirmDeleteDatabases = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header
                headroomSection

                if let message = viewModel.errorMessage {
                    Label(message, systemImage: "xmark.octagon.fill")
                        .font(.callout)
                        .foregroundStyle(.red)
                }

                if let summary = viewModel.lastReclaimSummary {
                    Label(summary, systemImage: "checkmark.circle.fill")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                breakdownSection
                reclaimSection
                volumesSection
                maintenanceSection
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationTitle("Docker Disk")
        .task { await viewModel.refreshFullInventory(projects: dashboard.projects) }
        .confirmationDialog("Reclaim disk space?", isPresented: $confirmReclaim) {
            Button("Reclaim \(viewModel.plan.totalBytes.formattedBytes)", role: .destructive) {
                Task {
                    await viewModel.executeReclaim()
                    await viewModel.refreshFullInventory(projects: dashboard.projects)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            reclaimConfirmationMessage
        }
        .confirmationDialog(
            selectedDatabaseVolumes.count == 1 ? "Delete this database?" : "Delete \(selectedDatabaseVolumes.count) databases?",
            isPresented: $confirmDeleteDatabases
        ) {
            Button("Delete \(selectedDatabaseVolumes.reduce(0) { $0 + $1.volume.sizeBytes }.formattedBytes)", role: .destructive) {
                let names = selectedDatabaseVolumes.map(\.volume.name)
                selectedDatabases = []
                Task {
                    await viewModel.removeVolumes(named: names)
                    await viewModel.refreshFullInventory(projects: dashboard.projects)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(
                "This permanently deletes the database for "
                + ListFormatter.localizedString(
                    byJoining: selectedDatabaseVolumes.map { $0.projectName ?? $0.volume.name }
                )
                + ". The projects stay registered and start with an empty database. This cannot be undone."
            )
        }
        .confirmationDialog(
            "Delete this volume?",
            isPresented: .isPresent($volumePendingRemoval),
            presenting: volumePendingRemoval
        ) { classified in
            Button("Delete \(classified.volume.name)", role: .destructive) {
                Task {
                    await viewModel.removeVolume(named: classified.volume.name)
                    await viewModel.refreshFullInventory(projects: dashboard.projects)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: { classified in
            Text(
                classified.kind == .database
                ? "This permanently deletes the database for \(classified.projectName ?? classified.volume.name). "
                  + "Take a snapshot first if you might need it."
                : "This permanently deletes \(classified.volume.name)."
            )
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("Docker Disk")
                    .font(.largeTitle.bold())
                Spacer()
                Button {
                    Task { await viewModel.refreshFullInventory(projects: dashboard.projects) }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .disabled(viewModel.isLoadingInventory)
            }
            Text("DDEV fails to start when the Docker VM runs out of space. Reclaim it here.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    private var headroomSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Headroom").sectionHeaderStyle()

            if let headroom = viewModel.headroom {
                VStack(alignment: .leading, spacing: 6) {
                    ProgressView(value: headroom.usedFraction)
                        .tint(tint(for: viewModel.alertLevel))
                    Text(
                        "\(headroom.usedBytes.formattedBytes) of \(headroom.totalBytes.formattedBytes) used "
                        + "· \(headroom.availableBytes.formattedBytes) free"
                    )
                    .font(.callout)
                    .foregroundStyle(.secondary)
                }
            } else {
                Text("Headroom unavailable — is Docker running?")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var breakdownSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Breakdown").sectionHeaderStyle()

            if let usage = viewModel.usage {
                VStack(spacing: 4) {
                    // "Reclaimable" here is what the Reclaim button below removes, not Docker's
                    // figure — Docker counts every stopped project's database as reclaimable.
                    breakdownRow("Images", usage.images, reclaimable: usage.images.reclaimableBytes)
                    breakdownRow("Containers", usage.containers, reclaimable: 0)
                    breakdownRow(
                        "Volumes", usage.volumes,
                        reclaimable: viewModel.plan.volumeBytes,
                        kept: max(0, usage.volumes.reclaimableBytes - viewModel.plan.volumeBytes)
                    )
                    breakdownRow("Build cache", usage.buildCache, reclaimable: usage.buildCache.reclaimableBytes)
                }
            } else if viewModel.isLoadingInventory {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Reading Docker usage…").foregroundStyle(.secondary)
                }
            }
        }
    }

    /// `kept` is data Docker reports as unused that Reclaim deliberately leaves alone — stopped
    /// projects' databases and unrecognised volumes.
    private func breakdownRow(
        _ title: String,
        _ category: DockerUsageCategory,
        reclaimable: Int64,
        kept: Int64 = 0
    ) -> some View {
        HStack {
            Text(title).frame(width: 140, alignment: .leading)
            Text(category.sizeBytes.formattedBytes)
                .frame(width: 100, alignment: .trailing)
            Text(reclaimable > 0 ? "\(reclaimable.formattedBytes) reclaimable" : "Nothing to reclaim")
                .foregroundStyle(.secondary)
            if kept > 0 {
                Text("· \(kept.formattedBytes) of project data kept")
                    .foregroundStyle(.tertiary)
            }
            Spacer()
        }
        .font(.callout)
    }

    private var reclaimSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Reclaim safely").sectionHeaderStyle()

            if viewModel.plan.isEmpty {
                Text("Nothing to reclaim.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(viewModel.plan.items) { item in
                        HStack {
                            if item.isDatabase {
                                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                            } else {
                                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                            }
                            Text(item.label)
                            Text(item.isDatabase ? "Database — orphaned, permanently deleted" : item.detail)
                                .foregroundStyle(item.isDatabase ? .orange : .secondary)
                                .font(.caption)
                            Spacer()
                            Text(item.estimatedBytes.formattedBytes).foregroundStyle(.secondary)
                        }
                        .font(.callout)
                    }
                }

                Button {
                    confirmReclaim = true
                } label: {
                    Label("Reclaim \(viewModel.plan.totalBytes.formattedBytes)", systemImage: "trash")
                }
                .buttonStyle(.borderedProminent)
                .disabled(viewModel.isReclaiming)

                Text(
                    "Registered projects' databases are never included here. Orphaned ones "
                    + "are — no DDEV project uses them any more."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            if viewModel.isReclaiming {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Reclaiming…").foregroundStyle(.secondary)
                }
            }
        }
    }

    /// Truthful confirmation copy for the bulk Reclaim dialog. Orphaned-project databases are
    /// deliberately bulk-eligible (see `ReclaimPlanner`), so this must say so prominently rather
    /// than reassure the user nothing database-related is at stake.
    private var reclaimConfirmationMessage: Text {
        let plan = viewModel.plan
        guard plan.hasOrphanedDatabase else {
            return Text(
                "Removes build cache, unused images, and sync caches for stopped projects. "
                + "Sync caches rebuild automatically on the next start. No project database is included."
            )
        }
        // Pluralise the noun with the list, and join with `ListFormatter` so two or more names
        // read "a and b" / "a, b, and c" rather than the bare comma-join that produced the
        // ungrammatical "the database for a, b".
        let items = plan.orphanedDatabaseItems
        let names = ListFormatter.localizedString(byJoining: items.map(\.label))
        let noun = items.count == 1 ? "the database" : "the databases"
        let projectClause = items.count == 1 ? "the DDEV project no longer exists" : "their DDEV projects no longer exist"
        return Text(
            "This also permanently deletes \(noun) for \(names) — \(projectClause), so this "
            + "cannot be undone. Take a snapshot first if you might need this data. It also "
            + "removes build cache, unused images, and sync caches for stopped projects, which "
            + "rebuild automatically."
        )
    }

    /// Databases get their own list, by project and largest first: they are the one thing here
    /// Reclaim never removes for a registered project, so this is where they are found, ticked
    /// and deleted.
    @ViewBuilder
    private var volumesSection: some View {
        let sorted = viewModel.inventory.sorted { $0.volume.sizeBytes > $1.volume.sizeBytes }
        let databases = sorted.filter { $0.kind == .database }

        if !databases.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                volumeListHeader("Project databases", volumes: databases)

                Text(
                    "Reclaim never deletes a registered project's database. Tick the ones you no "
                    + "longer need and delete them here — this cannot be undone."
                )
                .font(.caption)
                .foregroundStyle(.secondary)

                ForEach(databases) { classified in
                    HStack {
                        Toggle(isOn: selectionBinding(for: classified.volume.name)) {
                            Text(classified.projectName ?? classified.volume.name)
                        }
                        .toggleStyle(.checkbox)
                        .disabled(classified.state == .running)
                        .help(classified.state == .running ? "In use — stop the project first" : "")
                        Text(stateDescription(classified.state))
                            .font(.caption)
                            .foregroundStyle(classified.state == .orphaned ? .orange : .secondary)
                        Spacer()
                        Text(classified.volume.sizeBytes.formattedBytes)
                            .foregroundStyle(.secondary)
                    }
                    .font(.callout)
                }

                Button(role: .destructive) {
                    confirmDeleteDatabases = true
                } label: {
                    Label(deleteSelectedTitle, systemImage: "trash")
                }
                .disabled(selectedDatabaseVolumes.isEmpty || viewModel.isReclaiming)
            }
        }

        let others = sorted.filter { $0.kind != .database }
        VStack(alignment: .leading, spacing: 10) {
            volumeListHeader("Other volumes", volumes: others)

            ForEach(others) { classified in
                HStack {
                    Text(classified.volume.name)
                        .font(.system(.caption, design: .monospaced))
                    Text(stateLabel(classified))
                        .font(.caption)
                        .foregroundStyle(classified.state == .orphaned ? .orange : .secondary)
                    Spacer()
                    Text(classified.volume.sizeBytes.formattedBytes)
                        .foregroundStyle(.secondary)
                    Button(role: .destructive) {
                        volumePendingRemoval = classified
                    } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.borderless)
                    .disabled(classified.state == .running || viewModel.isReclaiming)
                    .help(classified.state == .running ? "In use — stop the project first" : "Delete this volume")
                }
            }
        }
    }

    private func volumeListHeader(_ title: String, volumes: [ClassifiedVolume]) -> some View {
        HStack {
            Text(title).sectionHeaderStyle()
            Spacer()
            Text(volumes.reduce(0) { $0 + $1.volume.sizeBytes }.formattedBytes)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    /// The ticked databases that still exist and are not in use. Derived from the live inventory
    /// so a stale tick — a volume since removed, or a project since started — is never acted on.
    private var selectedDatabaseVolumes: [ClassifiedVolume] {
        viewModel.inventory.filter {
            $0.kind == .database && $0.state != .running && selectedDatabases.contains($0.volume.name)
        }
    }

    private var deleteSelectedTitle: String {
        let selected = selectedDatabaseVolumes
        guard !selected.isEmpty else { return "Delete Selected…" }
        let size = selected.reduce(0) { $0 + $1.volume.sizeBytes }.formattedBytes
        return selected.count == 1
            ? "Delete 1 Database (\(size))…"
            : "Delete \(selected.count) Databases (\(size))…"
    }

    private func selectionBinding(for name: String) -> Binding<Bool> {
        Binding(
            get: { selectedDatabases.contains(name) },
            set: { isOn in
                if isOn { selectedDatabases.insert(name) } else { selectedDatabases.remove(name) }
            }
        )
    }

    private var maintenanceSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Maintenance").sectionHeaderStyle()
            Button {
                Task { await viewModel.prefetchImages() }
            } label: {
                Label("Prefetch Images", systemImage: "arrow.down.circle")
            }
            .disabled(viewModel.isReclaiming)
            .help("Pre-pull every image DDEV needs (ddev utility download-images)")

            Text("Uses disk space rather than reclaiming it — makes the next start faster.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func stateLabel(_ classified: ClassifiedVolume) -> String {
        let kind = switch classified.kind {
        case .mutagen: "sync cache"
        case .database: "database"
        case .other: "other"
        }
        return "\(kind) · \(stateDescription(classified.state))"
    }

    private func stateDescription(_ state: ProjectState) -> String {
        switch state {
        case .running: "running"
        case .stopped: "stopped"
        case .orphaned: "orphaned — no such DDEV project"
        }
    }

    private func tint(for level: DiskAlertLevel) -> Color {
        switch level {
        case .normal: .accentColor
        case .warning: .orange
        case .critical: .red
        }
    }
}
