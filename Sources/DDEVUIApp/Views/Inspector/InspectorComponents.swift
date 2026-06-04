import AppKit
import SwiftUI

// MARK: - Section wrapper (header + dividing rule, NOT a card)

struct InspectorSection<Content: View>: View {
    let title: String
    let content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(title)
                    .sectionHeaderStyle()
                Spacer()
            }
            content
        }
    }
}

// MARK: - Status badge (dot + label, single inline element)

struct ProjectStatusBadge: View {
    let status: DDEVProjectStatus

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
                .overlay(
                    Circle()
                        .stroke(color.opacity(0.35), lineWidth: 4)
                        .blur(radius: 2)
                        .opacity(status == .running ? 1 : 0)
                )
            Text(label)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
        }
    }

    private var color: Color {
        switch status {
        case .running: .green
        case .paused: .orange
        case .stopped: .secondary
        case .unknown: .yellow
        }
    }

    private var label: String {
        switch status {
        case .running: "Running"
        case .paused: "Paused"
        case .stopped: "Stopped"
        case .unknown: "Unknown"
        }
    }
}

// MARK: - Chip-style label (icon + text, no background)

struct InspectorChipLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 5) {
            configuration.icon
                .foregroundStyle(.tertiary)
            configuration.title
        }
    }
}

// MARK: - Launch hub (A1)

/// One openable destination for the Open/Launch hub: the primary site, Mailpit, XHGui, and any
/// add-on service UI surfaced from `ddev describe -j`.
struct LaunchLink: Identifiable {
    var id: String { name }
    let name: String
    let systemImage: String
    let url: URL
}

/// Every browser-openable URL the project exposes — the project's own URLs plus add-on service UIs
/// (phpMyAdmin, Adminer, …) derived from the live describe detail. Shared by the toolbar "Open"
/// menu and the Overview URL chips so they can't drift apart.
func projectLaunchLinks(_ project: DDEVProject, _ details: DDEVProjectDetails?) -> [LaunchLink] {
    var links: [LaunchLink] = []
    if let url = project.primaryURL { links.append(LaunchLink(name: "Primary", systemImage: "safari", url: url)) }
    if let url = project.httpsURL { links.append(LaunchLink(name: "HTTPS", systemImage: "lock.shield", url: url)) }
    if let url = project.httpURL { links.append(LaunchLink(name: "HTTP", systemImage: "globe", url: url)) }
    if let url = project.mailpitHTTPSURL ?? project.mailpitURL {
        links.append(LaunchLink(name: "Mailpit", systemImage: "envelope", url: url))
    }
    if let url = project.openableXHGuiURL {
        links.append(LaunchLink(name: "XHGui", systemImage: "chart.bar.xaxis", url: url))
    }
    for service in details?.addonServiceLinks ?? [] {
        links.append(LaunchLink(name: service.name.capitalized, systemImage: "puzzlepiece.extension", url: service.url))
    }
    return links
}

// MARK: - DB drift banner (A5)

/// Ambient warning shown when the on-disk database volume disagrees with the configured DB
/// type/version — promotes a buried `check-db-match` diagnostic into something the user can't miss.
struct DBDriftBanner: View {
    let message: String
    let onEditConfig: () -> Void

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.yellow)
            VStack(alignment: .leading, spacing: 2) {
                Text("Database version mismatch")
                    .font(.callout.weight(.semibold))
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            Button("Edit Config", action: onEditConfig)
                .buttonStyle(.bordered)
                .controlSize(.small)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.yellow.opacity(0.10), in: .rect(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(Color.yellow.opacity(0.35), lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Copyable value row (A3)

/// A label + value row with a one-click copy button, optionally masking the value (passwords).
struct CopyableRow: View {
    let label: String
    let value: String
    var isSecret: Bool = false
    @State private var revealed = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(label)
                .foregroundStyle(.secondary)
                .frame(width: 96, alignment: .leading)
            Text(displayValue)
                .font(.system(.callout, design: .monospaced))
                .textSelection(.enabled)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 4)
            if isSecret {
                Button {
                    revealed.toggle()
                } label: {
                    Image(systemName: revealed ? "eye.slash" : "eye")
                }
                .buttonStyle(.borderless)
                .help(revealed ? "Hide" : "Reveal")
            }
            Button {
                Pasteboard.copy(value)
            } label: {
                Image(systemName: "doc.on.doc")
            }
            .buttonStyle(.borderless)
            .help("Copy \(label.lowercased())")
        }
        .font(.callout)
    }

    private var displayValue: String {
        guard isSecret, !revealed else { return value }
        return String(repeating: "•", count: max(8, min(value.count, 16)))
    }
}

// MARK: - Source folder delete sheet

struct SourceFolderDeleteSheet: View {
    let project: DDEVProject
    var viewModel: ProjectDashboardViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var confirmationText = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                Image(systemName: "trash.circle.fill")
                    .font(.largeTitle)
                    .foregroundStyle(.red)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Move Source Folder To Trash")
                        .font(.title3.weight(.semibold))
                    Text("Independent of DDEV data deletion.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Folder")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                    .kerning(0.5)
                Text(project.appRoot)
                    .font(.system(.callout, design: .monospaced))
                    .textSelection(.enabled)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Type **\(project.name)** to confirm")
                    .font(.callout)
                TextField("", text: $confirmationText, prompt: Text(project.name))
                    .textFieldStyle(.roundedBorder)
            }

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(role: .destructive) {
                    viewModel.moveSelectedProjectFolderToTrash()
                    dismiss()
                } label: {
                    Label("Move To Trash", systemImage: "trash")
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .disabled(confirmationText != project.name)
            }
        }
        .padding(24)
        .frame(width: 500)
    }
}

// MARK: - InspectorCard

/// A titled, bordered card used across the redesigned Overview and Manage tabs. Optional trailing
/// header action (e.g. "Open in TablePlus"). Replaces the old header-only `InspectorSection` for
/// grouped content.
struct InspectorCard<Content: View>: View {
    let title: String
    var systemImage: String? = nil
    var headerActionTitle: String? = nil
    var headerAction: (() -> Void)? = nil
    @ViewBuilder var content: Content

    init(
        _ title: String,
        systemImage: String? = nil,
        headerActionTitle: String? = nil,
        headerAction: (() -> Void)? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.systemImage = systemImage
        self.headerActionTitle = headerActionTitle
        self.headerAction = headerAction
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .foregroundStyle(.secondary)
                }
                Text(title)
                    .sectionHeaderStyle()
                Spacer(minLength: 8)
                if let headerActionTitle, let headerAction {
                    Button(headerActionTitle, action: headerAction)
                        .buttonStyle(.borderless)
                        .font(.caption)
                }
            }
            content
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background.opacity(0.4), in: .rect(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(.separator, lineWidth: 1)
        )
    }
}
