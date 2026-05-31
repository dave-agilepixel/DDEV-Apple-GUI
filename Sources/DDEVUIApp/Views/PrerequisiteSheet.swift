import AppKit
import SwiftUI

struct PrerequisiteSheet: View {
    @ObservedObject var monitor: PrerequisiteMonitor

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header

            VStack(spacing: 12) {
                DockerRow(status: monitor.state.docker, isLaunching: monitor.isLaunching) { runtime in
                    Task { await monitor.launch(runtime) }
                }
                Divider()
                DDEVRow(status: monitor.state.ddev)
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(.quaternary.opacity(0.4))
            )

            if let launchErrorMessage = monitor.launchErrorMessage {
                Label(launchErrorMessage, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                    .font(.callout)
                    .textSelection(.enabled)
            }

            HStack {
                Button("Quit DDEVUI") {
                    NSApp.terminate(nil)
                }
                .keyboardShortcut("q", modifiers: .command)

                Spacer()

                Button {
                    Task { await monitor.refresh() }
                } label: {
                    if monitor.state.isStillChecking {
                        ProgressView().controlSize(.small)
                    } else {
                        Label("Re-check", systemImage: "arrow.clockwise")
                    }
                }
                .help("Re-run all prerequisite checks")
            }
        }
        .padding(24)
        .frame(width: 560)
    }

    private var header: some View {
        HStack(spacing: 14) {
            Image(systemName: "shippingbox.and.arrow.backward")
                .font(.system(size: 34))
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 4) {
                Text("Prerequisites required")
                    .font(.title2.weight(.semibold))
                Text("DDEVUI needs Docker and DDEV available before it can manage projects.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private struct DockerRow: View {
    let status: DockerStatus
    let isLaunching: Bool
    let onLaunch: (DockerRuntime) -> Void

    var body: some View {
        PrerequisiteRowLayout(
            iconSystemName: iconSystemName,
            iconTint: iconTint,
            title: title,
            subtitle: subtitle
        ) {
            switch status {
            case .ok, .checking:
                EmptyView()
            case .starting:
                ProgressView().controlSize(.small)
            case .notRunning(let runtime):
                Button {
                    onLaunch(runtime)
                } label: {
                    if isLaunching {
                        ProgressView().controlSize(.small)
                    } else {
                        Label("Launch \(runtime.displayName)", systemImage: "play.fill")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isLaunching)
            case .missing:
                InstallMenu(
                    primaryLabel: "Install Docker Desktop",
                    primaryURL: DockerRuntime.dockerDesktop.installURL,
                    brewCommand: DockerRuntime.dockerDesktop.brewInstallCommand,
                    secondary: (
                        label: "Install OrbStack",
                        url: DockerRuntime.orbstack.installURL,
                        brew: DockerRuntime.orbstack.brewInstallCommand
                    )
                )
            }
        }
    }

    private var iconSystemName: String {
        switch status {
        case .ok: "checkmark.circle.fill"
        case .checking, .starting: "ellipsis.circle"
        case .notRunning: "pause.circle.fill"
        case .missing: "xmark.octagon.fill"
        }
    }

    private var iconTint: Color {
        switch status {
        case .ok: .green
        case .checking, .starting: .yellow
        case .notRunning: .orange
        case .missing: .red
        }
    }

    private var title: String {
        switch status {
        case .starting(let runtime): "\(runtime.displayName) is starting…"
        case .notRunning(let runtime): "\(runtime.displayName) is not running"
        case .ok: "Docker is running"
        case .missing: "No Docker runtime detected"
        case .checking: "Checking Docker…"
        }
    }

    private var subtitle: String {
        switch status {
        case .ok: "Daemon responded to `docker info`."
        case .checking: "Looking for a running Docker daemon."
        case .starting: "Waiting for the daemon to accept connections."
        case .notRunning: "Launch it to start the Docker daemon."
        case .missing: "Install Docker Desktop or OrbStack to continue."
        }
    }
}

private struct DDEVRow: View {
    let status: DDEVStatus

    var body: some View {
        PrerequisiteRowLayout(
            iconSystemName: iconSystemName,
            iconTint: iconTint,
            title: title,
            subtitle: subtitle
        ) {
            switch status {
            case .ok, .checking:
                EmptyView()
            case .missing:
                InstallMenu(
                    primaryLabel: "Install DDEV",
                    primaryURL: DDEVInstallMethod.installURL,
                    brewCommand: DDEVInstallMethod.brewCommand,
                    secondary: nil
                )
            }
        }
    }

    private var iconSystemName: String {
        switch status {
        case .ok: "checkmark.circle.fill"
        case .checking: "ellipsis.circle"
        case .missing: "xmark.octagon.fill"
        }
    }

    private var iconTint: Color {
        switch status {
        case .ok: .green
        case .checking: .yellow
        case .missing: .red
        }
    }

    private var title: String {
        switch status {
        case .ok(let version): version.map { "DDEV \($0)" } ?? "DDEV installed"
        case .missing: "DDEV is not installed"
        case .checking: "Checking DDEV…"
        }
    }

    private var subtitle: String {
        switch status {
        case .ok: "`ddev version` responded successfully."
        case .checking: "Looking for the ddev binary on PATH."
        case .missing: "Install DDEV via Homebrew or the official installer."
        }
    }
}

private struct PrerequisiteRowLayout<Trailing: View>: View {
    let iconSystemName: String
    let iconTint: Color
    let title: String
    let subtitle: String
    @ViewBuilder let trailing: () -> Trailing

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: iconSystemName)
                .font(.title2)
                .foregroundStyle(iconTint)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            trailing()
        }
    }
}

private struct InstallMenu: View {
    let primaryLabel: String
    let primaryURL: URL
    let brewCommand: String
    let secondary: (label: String, url: URL, brew: String)?

    var body: some View {
        Menu {
            Button(primaryLabel) { NSWorkspace.shared.open(primaryURL) }
            Button("Copy `\(brewCommand)`") { copy(brewCommand) }

            if let secondary {
                Divider()
                Button(secondary.label) { NSWorkspace.shared.open(secondary.url) }
                Button("Copy `\(secondary.brew)`") { copy(secondary.brew) }
            }
        } label: {
            Label("Install…", systemImage: "arrow.down.circle")
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    private func copy(_ text: String) {
        Pasteboard.copy(text)
    }
}

#Preview("Missing both") {
    PrerequisiteSheet(monitor: PrerequisiteMonitor(
        service: StaticPrerequisiteService(state: PrerequisiteState(docker: .missing, ddev: .missing))
    ))
}

#Preview("Docker not running") {
    PrerequisiteSheet(monitor: PrerequisiteMonitor(
        service: StaticPrerequisiteService(state: PrerequisiteState(docker: .notRunning(.dockerDesktop), ddev: .ok(version: "v1.24.0")))
    ))
}

#Preview("Docker starting") {
    PrerequisiteSheet(monitor: PrerequisiteMonitor(
        service: StaticPrerequisiteService(state: PrerequisiteState(docker: .starting(.dockerDesktop), ddev: .ok(version: "v1.24.0")))
    ))
}
