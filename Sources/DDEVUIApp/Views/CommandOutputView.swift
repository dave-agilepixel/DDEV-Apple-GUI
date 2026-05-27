import SwiftUI

struct CommandOutputView: View {
    let result: CommandResult?
    let errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Command Output")
                .font(.headline)

            if let errorMessage {
                Text(errorMessage)
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
            }

            if let result {
                Text(outputText(for: result))
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
                    .background(.quaternary)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            } else if errorMessage == nil {
                Text("No command has run yet.")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func outputText(for result: CommandResult) -> String {
        let output = [result.stdout, result.stderr]
            .filter { !$0.isEmpty }
            .joined(separator: "\n")

        return output.isEmpty ? "Command completed with no output." : output
    }
}
