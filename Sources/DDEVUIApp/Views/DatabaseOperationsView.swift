import AppKit
import SwiftUI

struct DatabaseOperationsView: View {
    let project: DDEVProject
    @ObservedObject var viewModel: ProjectDashboardViewModel

    @State private var importDraft: DatabaseImportDraft?
    @State private var exportDraft: DatabaseExportDraft?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Database")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                    .kerning(0.5)
                Spacer()
            }

            HStack(spacing: 8) {
                Button {
                    chooseImportFile()
                } label: {
                    Label("Import", systemImage: "square.and.arrow.down")
                }

                Button {
                    exportDraft = DatabaseExportDraft()
                } label: {
                    Label("Export", systemImage: "square.and.arrow.up")
                }

                Spacer(minLength: 0)
            }
            .buttonStyle(.bordered)
            .controlSize(.regular)
            .labelStyle(.titleAndIcon)
            .disabled(viewModel.isRunningCommand)
        }
        .sheet(item: $importDraft) { draft in
            DatabaseImportSheet(project: project, draft: draft, viewModel: viewModel)
        }
        .sheet(item: $exportDraft) { draft in
            DatabaseExportSheet(project: project, draft: draft, viewModel: viewModel)
        }
    }

    private func chooseImportFile() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.title = "Choose Database Dump"
        panel.message = "Choose a SQL dump or supported archive to import into \(project.name)."

        guard panel.runModal() == .OK, let file = panel.url else { return }
        importDraft = DatabaseImportDraft(filePath: file.path)
    }
}

private struct DatabaseImportDraft: Identifiable {
    let id = UUID()
    let filePath: String
}

private struct DatabaseExportDraft: Identifiable {
    let id = UUID()
}

private struct DatabaseImportSheet: View {
    let project: DDEVProject
    let draft: DatabaseImportDraft
    @ObservedObject var viewModel: ProjectDashboardViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var database = "db"
    @State private var extractPath = ""
    @State private var dropExistingDatabase = true
    @State private var confirmationText = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                Image(systemName: "square.and.arrow.down.circle.fill")
                    .font(.largeTitle)
                    .foregroundStyle(dropExistingDatabase ? .red : Color.accentColor)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Import Database")
                        .font(.title3.weight(.semibold))
                    Text(project.name)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Source")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                    .kerning(0.5)
                Text(draft.filePath)
                    .font(.system(.callout, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
            }

            Form {
                Section {
                    TextField("Database", text: $database, prompt: Text("db"))
                    TextField("Archive extract path", text: $extractPath, prompt: Text("Optional path inside archive"))
                    Toggle("Drop existing database before import", isOn: $dropExistingDatabase)
                }
            }
            .formStyle(.grouped)
            .frame(maxHeight: 180)

            if dropExistingDatabase {
                VStack(alignment: .leading, spacing: 8) {
                    Label("This will replace the selected local database in \(project.name).", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                    Text("Type **\(project.name)** to confirm")
                        .font(.callout)
                    TextField("", text: $confirmationText, prompt: Text(project.name))
                        .textFieldStyle(.roundedBorder)
                }
            }

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(role: dropExistingDatabase ? .destructive : nil) {
                    let options = DDEVDatabaseImportOptions(
                        filePath: draft.filePath,
                        database: database,
                        extractPath: extractPath,
                        dropExistingDatabase: dropExistingDatabase
                    )
                    Task {
                        await viewModel.importDatabase(options)
                        dismiss()
                    }
                } label: {
                    Label("Import", systemImage: "square.and.arrow.down")
                }
                .buttonStyle(.borderedProminent)
                .tint(dropExistingDatabase ? .red : nil)
                .disabled(!canImport)
            }
        }
        .padding(24)
        .frame(width: 560)
    }

    private var canImport: Bool {
        if dropExistingDatabase {
            confirmationText == project.name
        } else {
            true
        }
    }
}

private struct DatabaseExportSheet: View {
    let project: DDEVProject
    let draft: DatabaseExportDraft
    @ObservedObject var viewModel: ProjectDashboardViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var database = "db"
    @State private var outputPath = ""
    @State private var compression: DDEVDatabaseExportCompression = .gzip

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                Image(systemName: "square.and.arrow.up.circle.fill")
                    .font(.largeTitle)
                    .foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Export Database")
                        .font(.title3.weight(.semibold))
                    Text(project.name)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }

            Form {
                Section {
                    TextField("Database", text: $database, prompt: Text("db"))
                    Picker("Compression", selection: $compression) {
                        ForEach(DDEVDatabaseExportCompression.allCases, id: \.self) { option in
                            Text(option.displayName).tag(option)
                        }
                    }
                    HStack {
                        TextField("Output path", text: $outputPath)
                            .font(.system(.body, design: .monospaced))
                        Button {
                            chooseExportPath()
                        } label: {
                            Label("Choose", systemImage: "folder")
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .frame(maxHeight: 190)

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button {
                    let options = DDEVDatabaseExportOptions(
                        outputPath: outputPath,
                        database: database,
                        compression: compression
                    )
                    Task {
                        await viewModel.exportDatabase(options)
                        dismiss()
                    }
                } label: {
                    Label("Export", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(.borderedProminent)
                .disabled(outputPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(24)
        .frame(width: 620)
    }

    private func chooseExportPath() {
        let panel = NSSavePanel()
        panel.title = "Export Database"
        panel.message = "Choose where to save the database export for \(project.name)."
        panel.nameFieldStringValue = "\(project.name)-db\(compression.defaultFileSuffix)"

        guard panel.runModal() == .OK, let file = panel.url else { return }
        outputPath = file.path
    }
}

private extension DDEVDatabaseExportCompression {
    var defaultFileSuffix: String {
        switch self {
        case .gzip: ".sql.gz"
        case .none: ".sql"
        case .bzip2: ".sql.bz2"
        case .xz: ".sql.xz"
        }
    }
}
