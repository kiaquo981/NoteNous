import SwiftUI
import AppKit

struct ImportExportView: View {
    @EnvironmentObject var appState: AppState

    @State private var isImporting = false
    @State private var isExporting = false
    @State private var importStats: ObsidianImportStats?
    @State private var exportStats: MarkdownExportStats?
    @State private var statusMessage: String?
    @State private var isBackingUp = false
    @State private var isRestoring = false
    @State private var backupMessage: String?

    var body: some View {
        Form {
            Section("Obsidian Import") {
                HStack {
                    Button("Import Obsidian Vault") {
                        selectFolderForImport()
                    }
                    .disabled(isImporting)

                    if isImporting {
                        ProgressView()
                            .controlSize(.small)
                        Text("Importing...")
                            .foregroundStyle(.secondary)
                    }
                }

                if let stats = importStats {
                    VStack(alignment: .leading, spacing: 4) {
                        Label("\(stats.notesImported) notes imported", systemImage: "doc.text")
                        Label("\(stats.linksCreated) links created", systemImage: "link")
                        Label("\(stats.tagsCreated) tags created", systemImage: "tag")
                        if stats.skipped > 0 {
                            Label("\(stats.skipped) files skipped", systemImage: "exclamationmark.triangle")
                                .foregroundStyle(.orange)
                        }
                        if !stats.errors.isEmpty {
                            ForEach(stats.errors.prefix(3), id: \.self) { error in
                                Text(error)
                                    .font(.caption)
                                    .foregroundStyle(.red)
                            }
                        }
                    }
                    .font(.callout)
                    .padding(.top, 4)
                }
            }

            Section("Markdown Export") {
                HStack {
                    Button("Export All Notes") {
                        selectFolderForExport()
                    }
                    .disabled(isExporting)

                    if isExporting {
                        ProgressView()
                            .controlSize(.small)
                        Text("Exporting...")
                            .foregroundStyle(.secondary)
                    }
                }

                if let stats = exportStats {
                    VStack(alignment: .leading, spacing: 4) {
                        Label("\(stats.notesExported) notes exported", systemImage: "doc.text")
                        Label("\(stats.foldersCreated) folders created", systemImage: "folder")
                        if !stats.errors.isEmpty {
                            ForEach(stats.errors.prefix(3), id: \.self) { error in
                                Text(error)
                                    .font(.caption)
                                    .foregroundStyle(.red)
                            }
                        }
                    }
                    .font(.callout)
                    .padding(.top, 4)
                }
            }

            Section("Backup & Restore") {
                HStack {
                    Button("Create Backup") {
                        createBackup()
                    }
                    .disabled(isBackingUp)

                    if isBackingUp {
                        ProgressView()
                            .controlSize(.small)
                    }
                }

                HStack {
                    Button("Restore from Backup") {
                        restoreBackup()
                    }
                    .disabled(isRestoring)

                    if isRestoring {
                        ProgressView()
                            .controlSize(.small)
                    }
                }

                if let msg = backupMessage {
                    Text(msg)
                        .font(.callout)
                        .foregroundStyle(msg.contains("Error") || msg.contains("Failed") ? .red : .green)
                        .padding(.top, 4)
                }
            }

            if let message = statusMessage {
                Text(message)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
    }

    // MARK: - Import

    private func selectFolderForImport() {
        let panel = NSOpenPanel()
        panel.title = "Select Obsidian Vault Folder"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false

        guard panel.runModal() == .OK, let url = panel.url else { return }

        isImporting = true
        importStats = nil
        statusMessage = nil

        Task {
            let importer = ObsidianImporter(context: appState.viewContext)
            let stats = await importer.importVault(at: url)
            await MainActor.run {
                importStats = stats
                isImporting = false
                statusMessage = "Import completed successfully."
            }
        }
    }

    // MARK: - Export

    private func selectFolderForExport() {
        let panel = NSOpenPanel()
        panel.title = "Select Export Destination"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true

        guard panel.runModal() == .OK, let url = panel.url else { return }

        isExporting = true
        exportStats = nil
        statusMessage = nil

        Task {
            let exporter = MarkdownExporter(context: appState.viewContext)
            let stats = await exporter.exportAll(to: url)
            await MainActor.run {
                exportStats = stats
                isExporting = false
                statusMessage = "Export completed successfully."
            }
        }
    }

    // MARK: - Backup

    private func createBackup() {
        let panel = NSSavePanel()
        panel.title = "Save Backup"
        panel.nameFieldStringValue = "NoteNous-Backup-\(backupDateString()).zip"
        panel.allowedContentTypes = [.zip]

        guard panel.runModal() == .OK, let url = panel.url else { return }

        isBackingUp = true
        backupMessage = nil

        Task {
            let service = BackupService()
            let result = await service.createBackup(to: url)
            await MainActor.run {
                isBackingUp = false
                switch result {
                case .success:
                    backupMessage = "Backup created successfully."
                case .failure(let error):
                    backupMessage = "Error: \(error.localizedDescription)"
                }
            }
        }
    }

    private func restoreBackup() {
        let panel = NSOpenPanel()
        panel.title = "Select Backup File"
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.zip]

        guard panel.runModal() == .OK, let url = panel.url else { return }

        isRestoring = true
        backupMessage = nil

        Task {
            let service = BackupService()
            let result = await service.restoreBackup(from: url)
            await MainActor.run {
                isRestoring = false
                switch result {
                case .success:
                    backupMessage = "Restore completed. Please restart the app."
                case .failure(let error):
                    backupMessage = "Failed: \(error.localizedDescription)"
                }
            }
        }
    }

    private func backupDateString() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd-HHmmss"
        return formatter.string(from: Date())
    }
}
