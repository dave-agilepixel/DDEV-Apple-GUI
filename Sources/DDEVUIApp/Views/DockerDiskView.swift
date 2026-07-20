import SwiftUI

/// Shows what is consuming the Docker VM's disk and offers a safe-by-default reclaim.
/// Follows the `DiagnosticsView` full-pane layout.
struct DockerDiskView: View {
    var viewModel: DockerDiskViewModel
    var dashboard: ProjectDashboardViewModel

    @State private var confirmReclaim = false
    @State private var volumePendingRemoval: ClassifiedVolume?

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
                Task { await viewModel.executeReclaim() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            reclaimConfirmationMessage
        }
        .confirmationDialog(
            "Delete this volume?",
            isPresented: .isPresent($volumePendingRemoval),
            presenting: volumePendingRemoval
        ) { classified in
            Button("Delete \(classified.volume.name)", role: .destructive) {
                Task { await viewModel.removeVolume(named: classified.volume.name) }
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
                    breakdownRow("Images", usage.images)
                    breakdownRow("Containers", usage.containers)
                    breakdownRow("Volumes", usage.volumes)
                    breakdownRow("Build cache", usage.buildCache)
                }
            } else if viewModel.isLoadingInventory {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Reading Docker usage…").foregroundStyle(.secondary)
                }
            }
        }
    }

    private func breakdownRow(_ title: String, _ category: DockerUsageCategory) -> some View {
        HStack {
            Text(title).frame(width: 140, alignment: .leading)
            Text(category.sizeBytes.formattedBytes)
                .frame(width: 100, alignment: .trailing)
            Text("\(category.reclaimableBytes.formattedBytes) reclaimable")
                .foregroundStyle(.secondary)
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
        let names = plan.orphanedDatabaseItems.map(\.label).joined(separator: ", ")
        return Text(
            "This also permanently deletes the database for \(names) — the DDEV project no "
            + "longer exists, so this cannot be undone. Take a snapshot first if you might need "
            + "this data. It also removes build cache, unused images, and sync caches for "
            + "stopped projects, which rebuild automatically."
        )
    }

    private var volumesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("All volumes").sectionHeaderStyle()

            ForEach(viewModel.inventory) { classified in
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
        let state = switch classified.state {
        case .running: "running"
        case .stopped: "stopped"
        case .orphaned: "orphaned — no such DDEV project"
        }
        return "\(kind) · \(state)"
    }

    private func tint(for level: DiskAlertLevel) -> Color {
        switch level {
        case .normal: .accentColor
        case .warning: .orange
        case .critical: .red
        }
    }
}
