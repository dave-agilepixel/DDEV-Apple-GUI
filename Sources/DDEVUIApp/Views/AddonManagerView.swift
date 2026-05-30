import SwiftUI

struct AddonManagerView: View {
    let project: DDEVProject
    @ObservedObject var viewModel: ProjectDashboardViewModel

    @State private var showSearchSheet = false
    @State private var pendingRemoval: DDEVAddon?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Add-ons")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                    .kerning(0.5)
                Spacer()
                Button {
                    Task { await viewModel.loadInstalledAddOnsForSelectedProject() }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .labelStyle(.iconOnly)
                .help("Refresh installed add-ons")
                .disabled(viewModel.isSelectedProjectBusy)
            }

            if viewModel.addOnRestartRecommended {
                HStack(spacing: 10) {
                    Label("Restart recommended after add-on changes.", systemImage: "arrow.clockwise.circle")
                        .foregroundStyle(.orange)
                    Spacer()
                    Button {
                        Task {
                            await viewModel.restartSelectedProject()
                            viewModel.clearAddOnRestartRecommendation()
                        }
                    } label: {
                        Label("Restart", systemImage: "arrow.clockwise")
                    }
                    Button {
                        viewModel.clearAddOnRestartRecommendation()
                    } label: {
                        Label("Dismiss", systemImage: "xmark")
                    }
                    .labelStyle(.iconOnly)
                    .help("Dismiss restart recommendation")
                }
                .font(.callout)
                .buttonStyle(.bordered)
            }

            HStack(spacing: 8) {
                Button {
                    showSearchSheet = true
                } label: {
                    Label("Browse", systemImage: "shippingbox.and.arrow.backward")
                }
                .buttonStyle(.borderedProminent)

                if let addonRawOutput = viewModel.addonRawOutput {
                    Text(addonRawOutput)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .textSelection(.enabled)
                }

                Spacer(minLength: 0)
            }
            .buttonStyle(.bordered)
            .disabled(viewModel.isSelectedProjectBusy)

            if let addonErrorMessage = viewModel.addonErrorMessage {
                Label(addonErrorMessage, systemImage: "xmark.octagon.fill")
                    .font(.callout)
                    .foregroundStyle(.red)
            }

            if viewModel.installedAddOns.isEmpty {
                ContentUnavailableView(
                    "No Add-ons Installed",
                    systemImage: "shippingbox",
                    description: Text("Browse official or community add-ons to extend this DDEV project.")
                )
                .frame(maxWidth: .infinity, minHeight: 120)
            } else {
                installedList
            }
        }
        .task(id: project.id) {
            await viewModel.loadInstalledAddOnsForSelectedProject()
        }
        .sheet(isPresented: $showSearchSheet) {
            AddonSearchSheet(project: project, viewModel: viewModel)
        }
        .confirmationDialog(
            "Remove add-on?",
            isPresented: Binding(
                get: { pendingRemoval != nil },
                set: { isPresented in
                    if !isPresented {
                        pendingRemoval = nil
                    }
                }
            ),
            presenting: pendingRemoval
        ) { addon in
            Button("Remove \(addon.repository)", role: .destructive) {
                Task { await viewModel.removeAddOnForSelectedProject(named: addon.installName) }
            }
            Button("Cancel", role: .cancel) {}
        } message: { addon in
            Text("This removes \(addon.repository) from \(project.name)'s DDEV configuration.")
        }
    }

    private var installedList: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(viewModel.installedAddOns) { addon in
                AddonRow(addon: addon) {
                    pendingRemoval = addon
                }
                .disabled(viewModel.isSelectedProjectBusy)
            }
        }
    }
}

private struct AddonSearchSheet: View {
    let project: DDEVProject
    @ObservedObject var viewModel: ProjectDashboardViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var query = ""
    @State private var pendingInstall: DDEVAddon?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Image(systemName: "shippingbox.circle.fill")
                    .font(.largeTitle)
                    .foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Browse Add-ons")
                        .font(.title3.weight(.semibold))
                    Text(project.name)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }

            HStack(spacing: 8) {
                TextField("Search add-ons", text: $query, prompt: Text("redis, solr, adminer..."))
                    .textFieldStyle(.roundedBorder)
                    .onSubmit {
                        Task { await viewModel.searchAddOnsForSelectedProject(query: query) }
                    }

                Button {
                    Task { await viewModel.searchAddOnsForSelectedProject(query: query) }
                } label: {
                    Label("Search", systemImage: "magnifyingglass")
                }
                .disabled(viewModel.isSelectedProjectBusy)
            }

            if let addonErrorMessage = viewModel.addonErrorMessage {
                Label(addonErrorMessage, systemImage: "xmark.octagon.fill")
                    .font(.callout)
                    .foregroundStyle(.red)
            }

            Text(query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Recommended" : "Results")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .kerning(0.5)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    ForEach(viewModel.addonSearchResults) { addon in
                        AddonRow(
                            addon: addon,
                            actionTitle: installedRepositories.contains(addon.repository) ? "Installed" : "Install",
                            actionSystemImage: installedRepositories.contains(addon.repository) ? "checkmark" : "plus",
                            actionDisabled: installedRepositories.contains(addon.repository) || viewModel.isSelectedProjectBusy
                        ) {
                            pendingInstall = addon
                        }
                    }
                }
            }
            .frame(minHeight: 280)

            HStack {
                Spacer()
                Button("Close") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
        }
        .padding(24)
        .frame(width: 640, height: 560)
        .confirmationDialog(
            "Install add-on?",
            isPresented: Binding(
                get: { pendingInstall != nil },
                set: { isPresented in
                    if !isPresented {
                        pendingInstall = nil
                    }
                }
            ),
            presenting: pendingInstall
        ) { addon in
            Button("Install \(addon.repository)") {
                Task { await viewModel.installAddOnForSelectedProject(addon.repository) }
            }
            Button("Cancel", role: .cancel) {}
        } message: { addon in
            Text("This installs \(addon.repository) into \(project.name) and may update files in the project's .ddev directory.")
        }
    }

    private var installedRepositories: Set<String> {
        Set(viewModel.installedAddOns.map(\.repository))
    }
}

private struct AddonRow: View {
    let addon: DDEVAddon
    var actionTitle = "Remove"
    var actionSystemImage = "trash"
    var actionDisabled = false
    let action: () -> Void

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(addon.repository)
                        .font(.callout.weight(.medium))
                        .textSelection(.enabled)

                    if addon.isOfficial {
                        Text("Official")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.green)
                    }

                    if let version = addon.version {
                        Text(version)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if !addon.description.isEmpty {
                    Text(addon.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                if !addon.dependencies.isEmpty {
                    Text("Depends on \(addon.dependencies.joined(separator: ", "))")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 0)

            Button(role: actionTitle == "Remove" ? .destructive : nil) {
                action()
            } label: {
                Label(actionTitle, systemImage: actionSystemImage)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(actionDisabled)
        }
        .padding(.vertical, 6)
    }
}
