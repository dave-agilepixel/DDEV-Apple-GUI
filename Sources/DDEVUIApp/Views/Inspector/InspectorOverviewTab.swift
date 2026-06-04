import AppKit
import SwiftUI

// MARK: - Overview tab

struct OverviewTabContent: View {
    let project: DDEVProject
    var viewModel: ProjectDashboardViewModel
    let workspaceOpener: MacWorkspaceOpener
    @Binding var showConfigEditor: Bool

    private var details: DDEVProjectDetails? { viewModel.selectedProjectDetails }

    var body: some View {
        Grid(alignment: .topLeading, horizontalSpacing: 12, verticalSpacing: 12) {
            GridRow {
                servicesCard
                databaseCard
            }
            GridRow {
                environmentCard
                    .gridCellColumns(2)
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 20)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Services

    @ViewBuilder
    private var servicesCard: some View {
        InspectorCard("Services") {
            if let details, !details.services.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(details.services) { service in
                        ServiceRow(service: service, workspaceOpener: workspaceOpener)
                    }
                    if let router = details.routerStatus {
                        ServiceHealthRow(label: "Router", status: router)
                    }
                    if let ssh = details.sshAgentStatus {
                        ServiceHealthRow(label: "SSH agent", status: ssh)
                    }
                }
            } else {
                Text(project.status == .running ? "Loading services…" : "Start the project to see its services.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: Database credentials

    @ViewBuilder
    private var databaseCard: some View {
        let databaseTool = viewModel.effectiveDefaultDatabaseTool
        let canOpenTool = project.status == .running && databaseTool != nil
        InspectorCard(
            "Database",
            headerActionTitle: canOpenTool ? "Open in \(databaseTool!.displayName)" : nil,
            headerAction: canOpenTool ? { Task { await viewModel.launchDefaultDatabaseTool() } } : nil
        ) {
            if project.status == .running, let db = details?.databaseInfo {
                VStack(alignment: .leading, spacing: 6) {
                    CopyableRow(label: "Database", value: db.name)
                    CopyableRow(label: "Username", value: db.username)
                    CopyableRow(label: "Password", value: db.password, isSecret: true)
                    if let hostPort = details?.databaseHostPort {
                        CopyableRow(label: "Host", value: "127.0.0.1")
                        CopyableRow(label: "Port", value: hostPort)
                    } else {
                        Label(
                            "Database port is not published to the host. Use the Database button to open a client.",
                            systemImage: "info.circle"
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                    if viewModel.effectiveDefaultDatabaseTool == nil {
                        Label("Install TablePlus, Sequel Ace, Querious, or DBeaver to open databases here.", systemImage: "info.circle")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            } else {
                Text("Start the project to see database credentials.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: Environment

    private var environmentCard: some View {
        InspectorCard("Environment") {
            VStack(alignment: .leading, spacing: 10) {
                Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 8) {
                    GridRow {
                        envRow("PHP version") {
                            HStack(spacing: 6) {
                                Text(project.phpVersion ?? "Unknown")
                                    .font(.system(.body, design: .monospaced))
                                Menu {
                                    ForEach(viewModel.supportedPHPVersions, id: \.self) { version in
                                        Button("PHP \(version)") {
                                            Task { await viewModel.setPHPVersionForSelectedProject(version) }
                                        }
                                        .disabled(project.phpVersion == version)
                                    }
                                } label: { Text("Change") }
                                .menuStyle(.borderlessButton)
                                .fixedSize()
                                .disabled(viewModel.isSelectedProjectBusy)
                            }
                        }
                        envRow("Project type") {
                            Text(project.projectType.displayName).foregroundStyle(.secondary)
                        }
                    }
                    if !project.docroot.isEmpty || (project.mutagenEnabled && project.mutagenStatus != nil) {
                        GridRow {
                            if !project.docroot.isEmpty {
                                envRow("Docroot") {
                                    Text(project.docroot)
                                        .font(.system(.body, design: .monospaced))
                                        .foregroundStyle(.secondary)
                                }
                            } else {
                                Color.clear.gridCellUnsizedAxes([.horizontal, .vertical])
                            }
                            if let mutagen = project.mutagenStatus, project.mutagenEnabled {
                                envRow("Mutagen") { Text(mutagen).foregroundStyle(.secondary) }
                            } else {
                                Color.clear.gridCellUnsizedAxes([.horizontal, .vertical])
                            }
                        }
                    }
                    if viewModel.selectedProjectXdebugEnabled != nil || viewModel.selectedProjectXHGuiEnabled != nil {
                        GridRow {
                            if let xdebugEnabled = viewModel.selectedProjectXdebugEnabled {
                                envRow("Xdebug") {
                                    Toggle("Xdebug", isOn: Binding(
                                        get: { xdebugEnabled },
                                        set: { newValue in Task { await viewModel.setXdebugForSelectedProject(newValue) } }
                                    ))
                                    .labelsHidden().toggleStyle(.switch).controlSize(.small)
                                    .disabled(viewModel.isSelectedProjectBusy)
                                }
                            } else {
                                Color.clear.gridCellUnsizedAxes([.horizontal, .vertical])
                            }
                            if let xhguiEnabled = viewModel.selectedProjectXHGuiEnabled {
                                envRow("XHProf (XHGui)") {
                                    Toggle("XHProf", isOn: Binding(
                                        get: { xhguiEnabled },
                                        set: { newValue in Task { await viewModel.setXHGuiForSelectedProject(newValue) } }
                                    ))
                                    .labelsHidden().toggleStyle(.switch).controlSize(.small)
                                    .disabled(viewModel.isSelectedProjectBusy)
                                }
                            } else {
                                Color.clear.gridCellUnsizedAxes([.horizontal, .vertical])
                            }
                        }
                    }
                }

                if project.xhguiStatus == .disabled {
                    Button {
                        Task { await viewModel.enableXHGuiForSelectedProject() }
                    } label: {
                        Label("Enable XHGui", systemImage: "chart.bar.xaxis")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(project.status != .running || viewModel.isSelectedProjectBusy)
                }

                HStack(spacing: 8) {
                    Button {
                        workspaceOpener.openFolder(project.appRoot + "/.ddev", editor: viewModel.effectiveDefaultEditor)
                    } label: { Label(".ddev/", systemImage: "folder") }
                    Button {
                        workspaceOpener.openFile(project.appRoot + "/.ddev/config.yaml", editor: viewModel.effectiveDefaultEditor)
                    } label: { Label("config.yaml", systemImage: "doc.text") }
                    Spacer()
                    Button {
                        showConfigEditor = true
                    } label: { Label("Edit Config", systemImage: "slider.horizontal.3") }
                    .disabled(viewModel.isSelectedProjectBusy)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
    }

    private func envRow<Trailing: View>(_ label: String, @ViewBuilder trailing: () -> Trailing) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(label).foregroundStyle(.secondary)
            Spacer(minLength: 8)
            trailing()
        }
        .font(.callout)
    }
}

// MARK: - Service rows (A4)

struct ServiceRow: View {
    let service: DDEVServiceInfo
    let workspaceOpener: MacWorkspaceOpener

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(service.isRunning ? Color.green : Color.orange)
                .frame(width: 7, height: 7)
            Text(service.shortName)
                .font(.callout.weight(.medium))
                .frame(width: 76, alignment: .leading)
            Text(service.status)
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer(minLength: 6)

            if !service.hostPorts.isEmpty {
                Text(service.hostPorts.map { "\($0.exposedPort)→\($0.hostPort)" }.joined(separator: "  "))
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .textSelection(.enabled)
            }

            if let url = service.hostHTTPSURL ?? service.hostHTTPURL ?? service.httpsURL ?? service.httpURL {
                Button {
                    workspaceOpener.openURL(url)
                } label: {
                    Image(systemName: "arrow.up.forward.app")
                }
                .buttonStyle(.borderless)
                .help("Open \(service.shortName)")
            }
        }
        .help(service.image)
    }
}

struct ServiceHealthRow: View {
    let label: String
    let status: String

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(status == "healthy" ? Color.green : Color.orange)
                .frame(width: 7, height: 7)
            Text(label)
                .font(.callout)
                .frame(width: 76, alignment: .leading)
            Text(status)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
        }
    }
}
