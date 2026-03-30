import CoreData
import AppKit
import os.log

final class VaultService: ObservableObject {
    static let shared = VaultService()

    private let logger = Logger(subsystem: "com.notenous.app", category: "VaultService")
    private let fileManager = FileManager.default

    private static let vaultPathKey = "VaultService.vaultPath"

    @Published var vaultPath: URL
    @Published var isSyncing: Bool = false

    private init() {
        if let stored = UserDefaults.standard.string(forKey: Self.vaultPathKey),
           let url = URL(string: stored) {
            self.vaultPath = url
        } else {
            let home = fileManager.homeDirectoryForCurrentUser
            self.vaultPath = home.appendingPathComponent("NoteNous", isDirectory: true)
        }
    }

    // MARK: - Vault Path

    func updateVaultPath(_ newPath: URL) {
        vaultPath = newPath
        UserDefaults.standard.set(newPath.absoluteString, forKey: Self.vaultPathKey)
        ensurePARADirectories()
    }

    // MARK: - PARA Directory Management

    private static let paraFolderNames: [PARACategory: String] = [
        .inbox: "Inbox",
        .project: "Projects",
        .area: "Areas",
        .resource: "Resources",
        .archive: "Archive"
    ]

    func ensurePARADirectories() {
        for (_, folderName) in Self.paraFolderNames {
            let folderURL = vaultPath.appendingPathComponent(folderName, isDirectory: true)
            if !fileManager.fileExists(atPath: folderURL.path) {
                do {
                    try fileManager.createDirectory(at: folderURL, withIntermediateDirectories: true)
                } catch {
                    logger.error("Failed to create PARA directory \(folderName): \(error.localizedDescription)")
                }
            }
        }
    }

    // MARK: - Sync Single Note

    func syncNote(_ note: NoteEntity) {
        ensurePARADirectories()

        let fileURL = filePath(for: note)
        let markdown = buildMarkdown(for: note)

        do {
            // Remove old file if note was moved to a different PARA category
            removeStaleFiles(for: note, currentURL: fileURL)
            try markdown.write(to: fileURL, atomically: true, encoding: .utf8)
            logger.debug("Synced note to vault: \(fileURL.lastPathComponent)")
        } catch {
            logger.error("Failed to sync note \(note.zettelId ?? "unknown"): \(error.localizedDescription)")
        }
    }

    // MARK: - Sync All

    func syncAll(context: NSManagedObjectContext) {
        isSyncing = true
        defer { isSyncing = false }

        ensurePARADirectories()

        let request = NoteEntity.fetchRequest() as! NSFetchRequest<NoteEntity>
        request.sortDescriptors = [NSSortDescriptor(key: "title", ascending: true)]

        let notes: [NoteEntity]
        do {
            notes = try context.fetch(request)
        } catch {
            logger.error("Failed to fetch notes for vault sync: \(error.localizedDescription)")
            return
        }

        var synced = 0
        for note in notes {
            let fileURL = filePath(for: note)
            let markdown = buildMarkdown(for: note)
            do {
                try markdown.write(to: fileURL, atomically: true, encoding: .utf8)
                synced += 1
            } catch {
                logger.error("Failed to sync '\(note.title)': \(error.localizedDescription)")
            }
        }

        logger.info("Vault sync complete: \(synced)/\(notes.count) notes synced")
    }

    func syncAllIfNeeded(context: NSManagedObjectContext) {
        ensurePARADirectories()

        // Check if vault has any .md files
        let inboxURL = vaultPath.appendingPathComponent("Inbox", isDirectory: true)
        let hasFiles = (try? fileManager.contentsOfDirectory(atPath: inboxURL.path))?.contains(where: { $0.hasSuffix(".md") }) ?? false

        if !hasFiles {
            syncAll(context: context)
        }
    }

    // MARK: - Delete Note File

    func deleteNoteFile(_ note: NoteEntity) {
        let fileURL = filePath(for: note)
        if fileManager.fileExists(atPath: fileURL.path) {
            do {
                try fileManager.removeItem(at: fileURL)
                logger.debug("Deleted vault file: \(fileURL.lastPathComponent)")
            } catch {
                logger.error("Failed to delete vault file: \(error.localizedDescription)")
            }
        }
        // Also try to clean up from all PARA folders in case of stale files
        removeAllFilesMatching(note: note)
    }

    // MARK: - File Path

    func filePath(for note: NoteEntity) -> URL {
        let folderName = Self.paraFolderNames[note.paraCategory] ?? "Inbox"
        let subfolder = vaultPath.appendingPathComponent(folderName, isDirectory: true)
        let filename = sanitizedFilename(for: note) + ".md"
        return subfolder.appendingPathComponent(filename)
    }

    // MARK: - Finder & External Editor

    func showInFinder(_ note: NoteEntity) {
        let fileURL = filePath(for: note)
        // Sync first to ensure file exists
        syncNote(note)
        NSWorkspace.shared.selectFile(fileURL.path, inFileViewerRootedAtPath: fileURL.deletingLastPathComponent().path)
    }

    func openInExternalEditor(_ note: NoteEntity) {
        let fileURL = filePath(for: note)
        // Sync first to ensure file exists
        syncNote(note)
        NSWorkspace.shared.open(fileURL)
    }

    func copyPath(_ note: NoteEntity) {
        let fileURL = filePath(for: note)
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(fileURL.path, forType: .string)
    }

    func openVaultInFinder() {
        ensurePARADirectories()
        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: vaultPath.path)
    }

    // MARK: - Stats

    func noteCount() -> Int {
        var count = 0
        for (_, folderName) in Self.paraFolderNames {
            let folderURL = vaultPath.appendingPathComponent(folderName, isDirectory: true)
            if let contents = try? fileManager.contentsOfDirectory(atPath: folderURL.path) {
                count += contents.filter { $0.hasSuffix(".md") }.count
            }
        }
        return count
    }

    func diskUsage() -> Int64 {
        var totalSize: Int64 = 0
        for (_, folderName) in Self.paraFolderNames {
            let folderURL = vaultPath.appendingPathComponent(folderName, isDirectory: true)
            if let contents = try? fileManager.contentsOfDirectory(atPath: folderURL.path) {
                for file in contents where file.hasSuffix(".md") {
                    let fileURL = folderURL.appendingPathComponent(file)
                    if let attrs = try? fileManager.attributesOfItem(atPath: fileURL.path),
                       let size = attrs[.size] as? Int64 {
                        totalSize += size
                    }
                }
            }
        }
        return totalSize
    }

    // MARK: - Markdown Building

    private func buildMarkdown(for note: NoteEntity) -> String {
        var lines: [String] = []

        // YAML frontmatter
        lines.append("---")
        lines.append("title: \"\(escapeFrontmatter(note.title))\"")

        if let zettelId = note.zettelId {
            lines.append("zettelId: \"\(zettelId)\"")
        }

        lines.append("type: \(note.noteType.label.lowercased())")
        lines.append("para: \(note.paraCategory.label.lowercased())")
        lines.append("codeStage: \(note.codeStage.label.lowercased())")

        let tagNames = note.tagsArray.compactMap(\.name).sorted()
        if !tagNames.isEmpty {
            lines.append("tags: [\(tagNames.joined(separator: ", "))]")
        }

        if let createdAt = note.createdAt {
            lines.append("created: \(iso8601(from: createdAt))")
        }
        if let updatedAt = note.updatedAt {
            lines.append("updated: \(iso8601(from: updatedAt))")
        }

        if let contextNote = note.contextNote, !contextNote.isEmpty {
            lines.append("context: \"\(escapeFrontmatter(contextNote))\"")
        }

        lines.append("---")
        lines.append("")

        // Title as H1
        if !note.title.isEmpty {
            lines.append("# \(note.title)")
            lines.append("")
        }

        // Content
        lines.append(note.content)

        return lines.joined(separator: "\n")
    }

    // MARK: - Helpers

    private func sanitizedFilename(for note: NoteEntity) -> String {
        let title = note.title.trimmingCharacters(in: .whitespacesAndNewlines)

        if title.isEmpty {
            return "Untitled-\(note.zettelId ?? UUID().uuidString)"
        }

        let invalidChars = CharacterSet(charactersIn: #"/\:*?"<>|"#)
        var sanitized = title.components(separatedBy: invalidChars).joined(separator: "-")
        sanitized = sanitized.trimmingCharacters(in: .whitespacesAndNewlines)

        // Collapse multiple dashes
        while sanitized.contains("--") {
            sanitized = sanitized.replacingOccurrences(of: "--", with: "-")
        }

        // Max 80 chars
        if sanitized.count > 80 {
            sanitized = String(sanitized.prefix(80))
        }

        // Remove trailing dash
        sanitized = sanitized.trimmingCharacters(in: CharacterSet(charactersIn: "-"))

        if sanitized.isEmpty {
            sanitized = "Untitled-\(note.zettelId ?? UUID().uuidString)"
        }

        return sanitized
    }

    private func escapeFrontmatter(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: " ")
    }

    private func iso8601(from date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: date)
    }

    /// Remove files from other PARA folders if the note has moved
    private func removeStaleFiles(for note: NoteEntity, currentURL: URL) {
        let filename = currentURL.lastPathComponent
        for (category, folderName) in Self.paraFolderNames where category != note.paraCategory {
            let staleURL = vaultPath.appendingPathComponent(folderName, isDirectory: true).appendingPathComponent(filename)
            if fileManager.fileExists(atPath: staleURL.path) {
                try? fileManager.removeItem(at: staleURL)
                logger.debug("Removed stale file: \(staleURL.path)")
            }
        }
    }

    /// Remove all files matching a note's possible filenames across all folders
    private func removeAllFilesMatching(note: NoteEntity) {
        let filename = sanitizedFilename(for: note) + ".md"
        for (_, folderName) in Self.paraFolderNames {
            let fileURL = vaultPath.appendingPathComponent(folderName, isDirectory: true).appendingPathComponent(filename)
            if fileManager.fileExists(atPath: fileURL.path) {
                try? fileManager.removeItem(at: fileURL)
            }
        }
    }
}
