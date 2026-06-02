import SwiftUI

struct CommandOutputView: View {
    let result: CommandResult?
    let history: [CommandHistoryEntry]
    let errorMessage: String?
    /// B4 — re-run a past command. When nil, the re-run action is hidden (copy still works).
    let onRerun: ((CommandResult) -> Void)?

    init(
        result: CommandResult?,
        history: [CommandHistoryEntry] = [],
        errorMessage: String?,
        onRerun: ((CommandResult) -> Void)? = nil
    ) {
        self.result = result
        self.history = history
        self.errorMessage = errorMessage
        self.onRerun = onRerun
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let errorMessage {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                    Text(errorMessage)
                        .foregroundStyle(.red)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(.red.opacity(0.08))
                )
            }

            if !history.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    // Keyed on the entry's stable id (not the array offset) so the sliding,
                    // capped history window can't hand a row's view state to a different command.
                    ForEach(Array(history.enumerated()), id: \.element.id) { index, entry in
                        commandBlock(for: entry.result, index: index, total: history.count)
                    }
                }
            } else if let result {
                commandBlock(for: result, index: 0, total: 1)
            } else if errorMessage == nil {
                Text("No command has run yet.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func commandBlock(for result: CommandResult, index: Int, total: Int) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if total > 1 {
                Text("Command \(index + 1)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            metadataRow(for: result)
            outputPanel(for: result)
        }
    }

    private func metadataRow(for result: CommandResult) -> some View {
        let duration = result.finishedAt.timeIntervalSince(result.startedAt)
        let durationText = String(format: "%.2fs", duration)
        let invocation = ([result.executable] + result.arguments).joined(separator: " ")

        return HStack(spacing: 10) {
            Text(invocation)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 8)
            Label(durationText, systemImage: "clock")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.tertiary)
                .labelStyle(.titleAndIcon)
            if result.wasCancelled {
                Label("Cancelled", systemImage: "xmark.circle")
                    .font(.caption)
                    .foregroundStyle(.orange)
            } else {
                Label("exit \(result.exitCode)", systemImage: result.succeeded ? "checkmark.circle" : "xmark.octagon")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(result.succeeded ? .green : .red)
            }

            actionsMenu(for: result)
        }
    }

    /// B4 — per-entry copy/re-run actions.
    private func actionsMenu(for result: CommandResult) -> some View {
        Menu {
            Button {
                Pasteboard.copy(result.commandLine)
            } label: {
                Label("Copy Command", systemImage: "doc.on.doc")
            }
            Button {
                Pasteboard.copy(outputText(for: result))
            } label: {
                Label("Copy Output", systemImage: "text.alignleft")
            }
            if let onRerun, result.isSafelyRerunnable {
                Divider()
                Button {
                    onRerun(result)
                } label: {
                    Label("Re-run", systemImage: "arrow.clockwise")
                }
            }
        } label: {
            Image(systemName: "ellipsis.circle")
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Copy or re-run this command")
    }

    private func outputText(for result: CommandResult) -> String {
        let output = [result.stdout, result.stderr]
            .filter { !$0.isEmpty }
            .joined(separator: "\n")

        return output.isEmpty ? "Command completed with no output." : output
    }

    private func outputPanel(for result: CommandResult) -> some View {
        ScrollView {
            Text(outputText(for: result))
                .font(.system(.caption, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
        }
        .frame(minHeight: 200, maxHeight: 360)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(.black.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(.quaternary, lineWidth: 1)
        )
    }
}
