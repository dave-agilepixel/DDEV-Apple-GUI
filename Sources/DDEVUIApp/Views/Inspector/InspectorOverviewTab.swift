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
        VStack(alignment: .leading, spacing: 24) {
            environmentSection
            urlsSection
            servicesSection
            databaseCredentialsSection
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 20)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var environmentSection: some View {
        InspectorSection("Environment") {
            VStack(alignment: .leading, spacing: 8) {
                metaRow("PHP version", trailing: {
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
                        } label: {
                            Text("Change")
                        }
                        .menuStyle(.borderlessButton)
                        .fixedSize()
                        .disabled(viewModel.isSelectedProjectBusy)
                    }
                })

                // Bind to the *live* Xdebug state (ddev xdebug status), not describe's config value.
                // Only present for a running project (the only time the live state is meaningful).
                if let xdebugEnabled = viewModel.selectedProjectXdebugEnabled {
                    metaRow("Xdebug", trailing: {
                        Toggle("Xdebug", isOn: Binding(
                            get: { xdebugEnabled },
                            set: { newValue in Task { await viewModel.setXdebugForSelectedProject(newValue) } }
                        ))
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.small)
                        .disabled(viewModel.isSelectedProjectBusy)
                    })
                }

                // A17 — live XHGui/XHProf profiling toggle, same shape as Xdebug. XHGui is DDEV's
                // XHProf UI; live state comes from `ddev xhgui status`. (No `ddev blackfire` command
                // exists in this DDEV, so Blackfire is intentionally not surfaced.)
                if let xhguiEnabled = viewModel.selectedProjectXHGuiEnabled {
                    metaRow("XHProf (XHGui)", trailing: {
                        Toggle("XHProf", isOn: Binding(
                            get: { xhguiEnabled },
                            set: { newValue in Task { await viewModel.setXHGuiForSelectedProject(newValue) } }
                        ))
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.small)
                        .disabled(viewModel.isSelectedProjectBusy)
                    })
                }

                metaRow("Project type", trailing: {
                    Text(project.projectType.displayName)
                        .foregroundStyle(.secondary)
                })

                if !project.docroot.isEmpty {
                    metaRow("Docroot", trailing: {
                        Text(project.docroot)
                            .font(.system(.body, design: .monospaced))
                            .foregroundStyle(.secondary)
                    })
                }

                if let mutagen = project.mutagenStatus, project.mutagenEnabled {
                    metaRow("Mutagen", trailing: {
                        Text(mutagen)
                            .foregroundStyle(.secondary)
                    })
                }

                HStack(spacing: 8) {
                    // B8 — open the raw .ddev/ files in the editor instead of building fragile
                    // GUI forms for advanced config.
                    Button {
                        workspaceOpener.openFolder(project.appRoot + "/.ddev", editor: viewModel.effectiveDefaultEditor)
                    } label: {
                        Label(".ddev/", systemImage: "folder")
                    }
                    Button {
                        workspaceOpener.openFile(project.appRoot + "/.ddev/config.yaml", editor: viewModel.effectiveDefaultEditor)
                    } label: {
                        Label("config.yaml", systemImage: "doc.text")
                    }

                    Spacer()

                    Button {
                        showConfigEditor = true
                    } label: {
                        Label("Edit Config", systemImage: "slider.horizontal.3")
                    }
                    .disabled(viewModel.isSelectedProjectBusy)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
    }

    @ViewBuilder
    private var urlsSection: some View {
        // A1 — one place to open every URL the project exposes, including add-on service UIs
        // (phpMyAdmin, Adminer, …) derived from the live describe detail.
        let links = projectLaunchLinks(project, details)

        if !links.isEmpty || project.xhguiStatus == .disabled {
            InspectorSection("Open") {
                FlowHStack(spacing: 8) {
                    ForEach(links) { link in
                        Button {
                            workspaceOpener.openURL(link.url)
                        } label: {
                            Label(link.name, systemImage: link.systemImage)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }

                    if project.xhguiStatus == .disabled {
                        Button {
                            Task { await viewModel.enableXHGuiForSelectedProject() }
                        } label: {
                            Label("Enable XHGui", systemImage: "chart.bar.xaxis")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }
                .disabled(project.status != .running)
            }
        }
    }

    // A4 — per-service health + the ephemeral 127.0.0.1 ports Docker assigned, plus router and
    // ssh-agent health. Surfaces partial/unhealthy states the single status badge flattens.
    @ViewBuilder
    private var servicesSection: some View {
        if let details, !details.services.isEmpty {
            InspectorSection("Services") {
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
            }
        }
    }

    // A3 — copyable database credentials. Only shown for a running project (the dbinfo only exists
    // then), and the password is masked until revealed.
    @ViewBuilder
    private var databaseCredentialsSection: some View {
        if project.status == .running, let db = details?.databaseInfo {
            InspectorSection("Database Credentials") {
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
                }
            }
        }
    }

    private func metaRow<Trailing: View>(_ label: String, @ViewBuilder trailing: () -> Trailing) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer()
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
