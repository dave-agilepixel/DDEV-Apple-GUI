import AppKit
import SwiftUI

struct LogsViewerView: View {
    let project: DDEVProject
    @ObservedObject var viewModel: ProjectDashboardViewModel

    @State private var service: DDEVLogRequest.Service = .web
    @State private var tailCount = 100
    @State private var includeTimestamps = false

    var body: some View {
        // Join stdout/stderr once per render instead of recomputing the (potentially large)
        // string for each use in the body (audit L2).
        let logs = logText
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Logs")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                    .kerning(0.5)
                Spacer()
                Button {
                    Task { await refreshLogs() }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .disabled(!canRefresh)
            }

            HStack(spacing: 10) {
                Picker("Service", selection: $service) {
                    ForEach(DDEVLogRequest.Service.allCases) { service in
                        Text(service.displayName).tag(service)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 260)

                Picker("Tail", selection: $tailCount) {
                    ForEach(DDEVLogRequest.supportedTailCounts, id: \.self) { count in
                        Text("\(count)").tag(count)
                    }
                }
                .frame(width: 100)

                Toggle("Timestamps", isOn: $includeTimestamps)
                    .toggleStyle(.checkbox)
                    .fixedSize()

                Spacer(minLength: 0)

                Button {
                    copyLogsToPasteboard()
                } label: {
                    Label("Copy", systemImage: "doc.on.doc")
                }
                .disabled(logs.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .buttonStyle(.bordered)
            .controlSize(.regular)
            // Consistent "busy" axis for the logs panel: disable controls while a read is in
            // flight too, matching the spinner which keys on isReadingData (audit L14c).
            .disabled(viewModel.isSelectedProjectBusy || viewModel.selectedProjectState.isReadingData)

            if project.status != .running {
                Label("Start the project before refreshing logs.", systemImage: "pause.circle")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            if let errorMessage = viewModel.projectLogsErrorMessage {
                Label(errorMessage, systemImage: "xmark.octagon.fill")
                    .font(.callout)
                    .foregroundStyle(.red)
            }

            if viewModel.selectedProjectState.isReadingData {
                ProgressView("Loading logs...")
                    .controlSize(.small)
            } else if logs.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                ContentUnavailableView(
                    "No Log Output",
                    systemImage: "doc.text.magnifyingglass",
                    description: Text(project.status == .running ? "Refresh logs to load recent output." : "Logs can be refreshed when the project is running.")
                )
                .frame(maxWidth: .infinity, minHeight: 120)
            } else {
                // Selectable Text in a ScrollView (as CommandOutputView does) rather than an
                // editable TextEditor bound via .constant just to get selection (audit L2).
                ScrollView {
                    Text(logs)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                }
                .frame(minHeight: 240, maxHeight: 400)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(.separator, lineWidth: 1)
                )
            }
        }
        .task(id: loadTrigger) {
            viewModel.clearProjectLogs()
            await viewModel.loadLogsForSelectedProjectIfRunning(currentRequest)
        }
    }

    private var canRefresh: Bool {
        project.status == .running && !viewModel.selectedProjectState.isReadingData
    }

    private var logText: String {
        guard let result = viewModel.projectLogsResult else { return "" }
        return [result.stdout, result.stderr]
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }

    private var currentRequest: DDEVLogRequest {
        DDEVLogRequest(
            service: service,
            tailCount: tailCount,
            includeTimestamps: includeTimestamps
        )
    }

    private var loadTrigger: LogsLoadTrigger {
        LogsLoadTrigger(projectID: project.id, request: currentRequest)
    }

    private func refreshLogs() async {
        await viewModel.loadLogsForSelectedProject(currentRequest)
    }

    private func copyLogsToPasteboard() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(logText, forType: .string)
    }
}

private struct LogsLoadTrigger: Equatable {
    let projectID: DDEVProject.ID
    let request: DDEVLogRequest
}
