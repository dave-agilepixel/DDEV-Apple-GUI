import SwiftUI

struct ProjectConfigEditorView: View {
    let project: DDEVProject
    @ObservedObject var viewModel: ProjectDashboardViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var loadedConfig: DDEVConfig?
    @State private var phpVersion = ""
    @State private var nodeJSVersion = ""
    @State private var databaseType = DDEVDatabaseType.mariadb
    @State private var databaseVersion = ""
    @State private var webserverType = DDEVWebserverType.nginxFPM
    @State private var performanceMode = DDEVPerformanceMode.global
    @State private var xdebugEnabled = false
    @State private var xhprofMode = DDEVXHProfMode.global
    @State private var uploadDirsText = ""
    @State private var additionalHostnamesText = ""

    var body: some View {
        VStack(spacing: 0) {
            header

            Divider()

            content

            Divider()

            footer
        }
        .frame(width: 620)
        .frame(minHeight: 620)
        .task(id: project.id) {
            // Single source of truth: load, then sync only if we're still on the same project.
            // The previous dual-sync (.task + .onChange on the shared @Published projectConfig)
            // could splice project A's config into project B's fields on a fast switch (audit M7).
            loadedConfig = nil
            let loadingProjectID = project.id
            await viewModel.loadConfigForSelectedProject()
            guard !Task.isCancelled,
                  viewModel.selectedProject?.id == loadingProjectID,
                  let config = viewModel.projectConfig else { return }
            syncState(from: config)
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "slider.horizontal.3")
                .font(.title2)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 2) {
                Text("Project Configuration")
                    .font(.title3.weight(.semibold))
                Text(project.name)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
            }
            .buttonStyle(.borderless)
            .keyboardShortcut(.cancelAction)
        }
        .padding(20)
    }

    @ViewBuilder
    private var content: some View {
        if let errorMessage = viewModel.projectConfigErrorMessage {
            ContentUnavailableView(
                "Could Not Load Config",
                systemImage: "exclamationmark.triangle",
                description: Text(errorMessage)
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(24)
        } else if loadedConfig == nil || viewModel.isSelectedProjectBusy && viewModel.projectConfig == nil {
            VStack(spacing: 12) {
                ProgressView()
                Text("Loading DDEV config")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(24)
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    restartBanner
                    runtimeSection
                    databaseSection
                    webSection
                    performanceSection
                    pathsSection
                    commandSummary
                }
                .padding(24)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    @ViewBuilder
    private var restartBanner: some View {
        if viewModel.projectConfigRestartRecommended {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "arrow.clockwise.circle.fill")
                    .foregroundStyle(.orange)
                    .font(.title3)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Restart recommended")
                        .font(.headline)
                    Text("DDEV applies many config changes after the project restarts.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if project.status == .running {
                    Button {
                        Task {
                            await viewModel.restartSelectedProject()
                            viewModel.clearProjectConfigRestartRecommendation()
                        }
                    } label: {
                        Label("Restart", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(viewModel.isSelectedProjectBusy)
                }
            }
            .padding(12)
            .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
        }
    }

    private var runtimeSection: some View {
        ConfigEditorSection(title: "Runtime") {
            editableRow(title: "PHP version", hasChanges: phpVersion != loadedConfig?.phpVersion) {
                Picker("", selection: $phpVersion) {
                    ForEach(viewModel.supportedPHPVersions, id: \.self) { version in
                        Text(version).tag(version)
                    }
                }
                .labelsHidden()
                .frame(width: 140)
            } apply: {
                await apply(.phpVersion(phpVersion))
            }

            editableRow(title: "Node.js version", hasChanges: nodeJSVersion != loadedConfig?.nodeJSVersion) {
                TextField("22", text: $nodeJSVersion)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 140)
            } apply: {
                await apply(.nodeJSVersion(nodeJSVersion))
            }
        }
    }

    private var databaseSection: some View {
        ConfigEditorSection(title: "Database") {
            editableRow(
                title: "Database",
                hasChanges: databaseType != loadedConfig?.databaseType || databaseVersion != loadedConfig?.databaseVersion
            ) {
                HStack(spacing: 8) {
                    Picker("", selection: $databaseType) {
                        ForEach(DDEVDatabaseType.allCases) { type in
                            Text(type.displayName).tag(type)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 150)

                    TextField("11.8", text: $databaseVersion)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 110)
                }
            } apply: {
                await apply(.database(type: databaseType, version: databaseVersion))
            }
        }
    }

    private var webSection: some View {
        ConfigEditorSection(title: "Web") {
            editableRow(title: "Webserver", hasChanges: webserverType != loadedConfig?.webserverType) {
                Picker("", selection: $webserverType) {
                    ForEach(DDEVWebserverType.allCases) { type in
                        Text(type.displayName).tag(type)
                    }
                }
                .labelsHidden()
                .frame(width: 180)
            } apply: {
                await apply(.webserverType(webserverType))
            }

            editableRow(title: "Xdebug", hasChanges: xdebugEnabled != loadedConfig?.xdebugEnabled) {
                Toggle("", isOn: $xdebugEnabled)
                    .labelsHidden()
            } apply: {
                await apply(.xdebugEnabled(xdebugEnabled))
            }

            editableRow(title: "XHProf mode", hasChanges: xhprofMode != loadedConfig?.xhprofMode) {
                Picker("", selection: $xhprofMode) {
                    ForEach(DDEVXHProfMode.allCases) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                .labelsHidden()
                .frame(width: 160)
            } apply: {
                await apply(.xhprofMode(xhprofMode))
            }
        }
    }

    private var performanceSection: some View {
        ConfigEditorSection(title: "Performance") {
            editableRow(title: "Performance mode", hasChanges: performanceMode != loadedConfig?.performanceMode) {
                Picker("", selection: $performanceMode) {
                    ForEach(DDEVPerformanceMode.allCases) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                .labelsHidden()
                .frame(width: 160)
            } apply: {
                await apply(.performanceMode(performanceMode))
            }
        }
    }

    private var pathsSection: some View {
        ConfigEditorSection(title: "Paths And Hostnames") {
            editableRow(title: "Upload dirs", hasChanges: uploadDirs != loadedConfig?.uploadDirs) {
                TextField("web/app/uploads, web/sites/default/files", text: $uploadDirsText)
                    .textFieldStyle(.roundedBorder)
            } apply: {
                await apply(.uploadDirs(uploadDirs))
            }

            editableRow(title: "Additional hostnames", hasChanges: additionalHostnames != loadedConfig?.additionalHostnames) {
                TextField("www, admin", text: $additionalHostnamesText)
                    .textFieldStyle(.roundedBorder)
            } apply: {
                await apply(.additionalHostnames(additionalHostnames))
            }
        }
    }

    @ViewBuilder
    private var commandSummary: some View {
        if let result = viewModel.selectedProjectState.lastResult, result.arguments.first == "config" {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("Last command")
                    .foregroundStyle(.secondary)
                Text(([result.executable] + result.arguments).joined(separator: " "))
                    .font(.system(.callout, design: .monospaced))
                    .textSelection(.enabled)
                    .lineLimit(2)
            }
            .font(.callout)
        }
    }

    private var footer: some View {
        HStack {
            Text("Raw YAML editing is intentionally excluded from this editor.")
                .font(.callout)
                .foregroundStyle(.secondary)
            Spacer()
            Button("Close") { dismiss() }
                .keyboardShortcut(.defaultAction)
        }
        .padding(20)
    }

    private var uploadDirs: [String] {
        commaList(from: uploadDirsText)
    }

    private var additionalHostnames: [String] {
        commaList(from: additionalHostnamesText)
    }

    private func editableRow<Control: View>(
        title: String,
        hasChanges: Bool,
        @ViewBuilder control: () -> Control,
        apply: @escaping () async -> Void
    ) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Text(title)
                .foregroundStyle(.secondary)
                .frame(width: 170, alignment: .leading)

            control()

            Spacer(minLength: 12)

            Button {
                Task { await apply() }
            } label: {
                Label("Apply", systemImage: "checkmark")
            }
            .disabled(!hasChanges || viewModel.isSelectedProjectBusy)
        }
        .font(.callout)
    }

    private func apply(_ change: DDEVConfigChange) async {
        await viewModel.applyConfigChangeForSelectedProject(change)

        // Advance only the applied field's baseline (audit M7). Rebuilding the baseline from a
        // full draft of every field used to clear other rows' "changed" indicators incorrectly.
        if viewModel.selectedProjectState.lastErrorMessage == nil {
            loadedConfig = loadedConfig?.applying(change)
        }
    }

    private func syncState(from config: DDEVConfig) {
        loadedConfig = config
        phpVersion = config.phpVersion
        nodeJSVersion = config.nodeJSVersion
        databaseType = config.databaseType
        databaseVersion = config.databaseVersion
        webserverType = config.webserverType
        performanceMode = config.performanceMode
        xdebugEnabled = config.xdebugEnabled
        xhprofMode = config.xhprofMode
        uploadDirsText = config.uploadDirs.joined(separator: ", ")
        additionalHostnamesText = config.additionalHostnames.joined(separator: ", ")
    }

    private func commaList(from text: String) -> [String] {
        text
            .split(separator: ",", omittingEmptySubsequences: false)
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}

private struct ConfigEditorSection<Content: View>: View {
    let title: String
    let content: Content

    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .kerning(0.5)

            VStack(spacing: 10) {
                content
            }
        }
    }
}
