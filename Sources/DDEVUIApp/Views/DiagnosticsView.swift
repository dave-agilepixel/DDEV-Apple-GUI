import AppKit
import SwiftUI

struct DiagnosticsView: View {
    @ObservedObject var viewModel: ProjectDashboardViewModel
    @State private var confirmMutagenReset = false

    private var selectedProject: DDEVProject? {
        viewModel.selectedProject
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header
                runControls

                if let diagnosticsErrorMessage = viewModel.diagnosticsErrorMessage {
                    Label(diagnosticsErrorMessage, systemImage: "xmark.octagon.fill")
                        .font(.callout)
                        .foregroundStyle(.red)
                }

                if selectedProject?.mutagenEnabled == true {
                    mutagenControls
                }

                resultsSection
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationTitle("Diagnostics")
        .confirmationDialog("Reset Mutagen data?", isPresented: $confirmMutagenReset) {
            Button("Reset Mutagen", role: .destructive) {
                Task { await viewModel.runMutagenDiagnosticForSelectedProject(.reset) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This stops the selected project and removes its Mutagen Docker volume. Use it only when sync is broken.")
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("Diagnostics")
                    .font(.largeTitle.bold())
                Spacer()
                Button {
                    copy(viewModel.copyableDiagnosticOutput)
                } label: {
                    Label("Copy All", systemImage: "doc.on.doc")
                }
                .disabled(viewModel.copyableDiagnosticOutput.isEmpty)
            }

            Text(selectedProject.map { "Project checks will run in \($0.name)." } ?? "Run global checks for DDEV, Docker, networking, and HTTPS.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    private var runControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Health Checks")
                .sectionHeaderStyle()

            HStack(spacing: 10) {
                Button {
                    Task { await viewModel.runGlobalDiagnostics() }
                } label: {
                    Label("Run Global Checks", systemImage: "network")
                }
                .buttonStyle(.borderedProminent)

                Button {
                    Task { await viewModel.runProjectDiagnosticsForSelectedProject() }
                } label: {
                    Label("Run Project Checks", systemImage: "shippingbox")
                }
                .disabled(selectedProject == nil)

                Spacer(minLength: 0)
            }
            .buttonStyle(.bordered)
            .disabled(viewModel.isRunningGlobalCommand)

            if let selectedProject {
                HStack(spacing: 8) {
                    Label(selectedProject.appRoot, systemImage: "folder")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                }
            }
        }
    }

    private var mutagenControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Mutagen")
                .sectionHeaderStyle()

            HStack(spacing: 8) {
                mutagenButton(.status, title: "Status", systemImage: "waveform.path.ecg")
                mutagenButton(.sync, title: "Sync", systemImage: "arrow.clockwise.icloud")
                mutagenButton(.logs, title: "Logs", systemImage: "text.page")
                Button(role: .destructive) {
                    confirmMutagenReset = true
                } label: {
                    Label("Reset", systemImage: "exclamationmark.arrow.triangle.2.circlepath")
                }
            }
            .buttonStyle(.bordered)
            .disabled(viewModel.isRunningGlobalCommand)
        }
    }

    private var resultsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Output")
                .sectionHeaderStyle()

            if viewModel.diagnosticReport.entries.isEmpty {
                ContentUnavailableView(
                    "No Diagnostic Output",
                    systemImage: "stethoscope",
                    description: Text("Run global or project checks to collect copyable output.")
                )
                .frame(maxWidth: .infinity, minHeight: 180)
            } else {
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(viewModel.diagnosticReport.entries) { entry in
                        DiagnosticResultView(entry: entry) {
                            copy(entry.output)
                        }
                    }
                }
            }
        }
    }

    private func mutagenButton(_ command: DDEVMutagenCommand, title: String, systemImage: String) -> some View {
        Button {
            Task { await viewModel.runMutagenDiagnosticForSelectedProject(command) }
        } label: {
            Label(title, systemImage: systemImage)
        }
    }

    private func copy(_ output: String) {
        guard !output.isEmpty else { return }
        Pasteboard.copy(output)
    }
}

private struct DiagnosticResultView: View {
    let entry: DDEVDiagnosticEntry
    let copyOutput: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Label(entry.check.title, systemImage: entry.succeeded ? "checkmark.circle.fill" : "xmark.octagon.fill")
                    .font(.headline)
                    .foregroundStyle(entry.succeeded ? .green : .red)

                Spacer()

                Text("Exit \(entry.result.exitCode)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)

                Button {
                    copyOutput()
                } label: {
                    Label("Copy", systemImage: "doc.on.doc")
                }
                .labelStyle(.iconOnly)
                .help("Copy this diagnostic output")
                .disabled(entry.output.isEmpty)
            }

            Text(entry.check.summary)
                .font(.caption)
                .foregroundStyle(.secondary)

            Text("ddev \(entry.result.arguments.joined(separator: " "))")
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
                .textSelection(.enabled)

            if let workingDirectory = entry.result.workingDirectory {
                Text(workingDirectory)
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
            }

            if !entry.output.isEmpty {
                Text(entry.output)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 8))
            }
        }
    }
}
