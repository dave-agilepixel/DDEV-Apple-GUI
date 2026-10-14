import SwiftUI

struct AddonManagerView: View {
    let project: DDEVProject
    var viewModel: ProjectDashboardViewModel

    @State private var showSearchSheet = false
    @State private var pendingRemoval: DDEVAddon?

    var body: some View {
        Section {
            if viewModel.addOnRestartRecommended {
                LabeledContent {
                    Button("Restart") {
                        Task {
                            await viewModel.restartSelectedProject()
                            viewModel.clearAddOnRestartRecommendation()
                        }
                    }
                    Button {
                        viewModel.clearAddOnRestartRecommendation()
                    } label: {
                        Label("Dismiss", systemImage: "xmark")
                    }
                    .labelStyle(.iconOnly)
                    .help("Dismiss restart recommendation")
                } label: {
                    Label("Restart recommended after add-on changes.", systemImage: "arrow.clockwise.circle")
                        .foregroundStyle(.orange)
                }
            }

            if let addonErrorMessage = viewModel.addonErrorMessage {
                Label(addonErrorMessage, systemImage: "xmark.octagon.fill")
                    .foregroundStyle(.red)
            }

            if viewModel.installedAddOns.isEmpty {
                Text("No add-ons installed.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(viewModel.installedAddOns) { addon in
                    AddonRow(addon: addon) {
                        pendingRemoval = addon
                    }
                }
            }

            LabeledContent {
                Button("Browse…") { showSearchSheet = true }
            } label: {
                Text("Add an add-on")
                // The raw `ddev add-on` output for the last install/remove, when there is one.
                Text(viewModel.addonRawOutput ?? "Official and community services such as Redis or Solr.")
                    .lineLimit(2)
            }
        } header: {
            HStack {
                Text("Add-ons")
                Spacer()
                Button {
                    Task { await viewModel.loadInstalledAddOnsForSelectedProject() }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                        .labelStyle(.iconOnly)
                }
                .buttonStyle(.borderless)
                .help("Refresh installed add-ons")
            }
        }
        .disabled(viewModel.isSelectedProjectBusy)
        .task(id: project.id) {
            await viewModel.loadInstalledAddOnsForSelectedProject()
        }
        .sheet(isPresented: $showSearchSheet) {
            AddonSearchSheet(project: project, viewModel: viewModel)
        }
        .confirmationDialog(
            "Remove add-on?",
            isPresented: .isPresent($pendingRemoval),
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
}

private struct AddonSearchSheet: View {
    let project: DDEVProject
    var viewModel: ProjectDashboardViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var query = ""
    @State private var pendingInstall: DDEVAddon?

    var body: some View {
        // Build the installed-repository set once per render instead of rebuilding it three
        // times for every row in the results list (audit L1).
        let installed = installedRepositories
        return VStack(alignment: .leading, spacing: 16) {
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

                Button {
                    query = ""
                    Task { await viewModel.loadRegistryAddOns() }
                } label: {
                    if viewModel.isLoadingRegistry {
                        ProgressView().controlSize(.small)
                    } else {
                        Label("Browse All", systemImage: "square.grid.2x2")
                    }
                }
                .disabled(viewModel.isLoadingRegistry)
                .help("Load the full add-on registry (official first, by stars)")
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
                            actionTitle: installed.contains(addon.repository) ? "Installed" : "Install",
                            actionSystemImage: installed.contains(addon.repository) ? "checkmark" : "plus",
                            actionDisabled: installed.contains(addon.repository) || viewModel.isSelectedProjectBusy
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
            isPresented: .isPresent($pendingInstall),
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
                    } else {
                        Text("Community")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }

                    if let stars = addon.stars {
                        Label("\(stars)", systemImage: "star.fill")
                            .font(.caption2)
                            .foregroundStyle(.yellow)
                            .labelStyle(.titleAndIcon)
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
