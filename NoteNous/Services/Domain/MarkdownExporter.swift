import CoreData
import os.log

// MARK: - Export Stats

struct MarkdownExportStats {
    var notesExported: Int = 0
    var foldersCreated: Int = 0
    var errors: [String] = []
}

// MARK: - Markdown Exporter

final class MarkdownExporter {
    private let context: NSManagedObjectContext
    private let logger = Logger(subsystem: "com.notenous.app", category: "MarkdownExporter")

    init(context: NSManagedObjectContext) {
        self.context = context
    }

    // MARK: - Public

    /// Export all notes to a folder as individual .md files organized by PARA category.
    func exportAll(to folderURL: URL) async -> MarkdownExportStats {
        var stats = MarkdownExportStats()
        let fileManager = FileManager.default

        // Fetch all non-archived notes
        let request = NoteEntity.fetchRequest() as! NSFetchRequest<NoteEntity>
        request.sortDescriptors = [NSSortDescriptor(key: "title", ascending: true)]

        let notes: [NoteEntity]
        do {
            notes = try context.fetch(request)
        } catch {
            stats.errors.append("Failed to fetch notes: \(error.localizedDescription)")
            return stats
        }

        // Create PARA subfolders
        let paraFolders: [PARACategory: String] = [
            .inbox: "Inbox",
            .project: "Projects",
            .area: "Areas",
            .resource: "Resources",
            .archive: "Archive"
        ]

        for (_, folderName) in paraFolders {
            let subfolderURL = folderURL.appendingPathComponent(folderName, isDirectory: true)
            do {
                try fileManager.createDirectory(at: subfolderURL, withIntermediateDirectories: true)
                stats.foldersCreated += 1
            } catch {
                stats.errors.append("Failed to create folder \(folderName): \(error.localizedDescription)")
            }
        }

        // Export each note
        for note in notes {
            let folderName = paraFolders[note.paraCategory] ?? "Inbox"
            let subfolder = folderURL.appendingPathComponent(folderName, isDirectory: true)
            let filename = sanitizeFilename(note.title) + ".md"
            let fileURL = subfolder.appendingPathComponent(filename)

            let markdown = buildMarkdown(for: note)

            do {
                try markdown.write(to: fileURL, atomically: true, encoding: .utf8)
                stats.notesExported += 1
            } catch {
                stats.errors.append("Failed to export '\(note.title)': \(error.localizedDescription)")
            }
        }

        logger.info("Export complete: \(stats.notesExported) notes to \(stats.foldersCreated) folders")
        return stats
    }

    // MARK: - Markdown Building

    private func buildMarkdown(for note: NoteEntity) -> String {
        var lines: [String] = []

        // YAML frontmatter
        lines.append("---")
        lines.append("title: \"\(escapeFrontmatterValue(note.title))\"")

        if let zettelId = note.zettelId {
            lines.append("zettelId: \(zettelId)")
        }

        lines.append("paraCategory: \(note.paraCategory.label)")
        lines.append("noteType: \(note.noteType.label)")
        lines.append("codeStage: \(note.codeStage.label)")

        let tagNames = note.tagsArray.compactMap(\.name).sorted()
        if !tagNames.isEmpty {
            lines.append("tags: [\(tagNames.joined(separator: ", "))]")
        }

        if let createdAt = note.createdAt {
            lines.append("createdAt: \(iso8601String(from: createdAt))")
        }
        if let updatedAt = note.updatedAt {
            lines.append("updatedAt: \(iso8601String(from: updatedAt))")
        }

        lines.append("---")
        lines.append("")

        // Content
        lines.append(note.content)

        return lines.joined(separator: "\n")
    }

    // MARK: - Helpers

    private func sanitizeFilename(_ title: String) -> String {
        let invalidChars = CharacterSet(charactersIn: #"/\:*?"<>|"#)
        var sanitized = title.components(separatedBy: invalidChars).joined(separator: "_")
        sanitized = sanitized.trimmingCharacters(in: .whitespacesAndNewlines)
        if sanitized.isEmpty {
            sanitized = "Untitled"
        }
        // Limit filename length
        if sanitized.count > 200 {
            sanitized = String(sanitized.prefix(200))
        }
        return sanitized
    }

    private func escapeFrontmatterValue(_ value: String) -> String {
        value.replacingOccurrences(of: "\"", with: "\\\"")
    }

    private func iso8601String(from date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: date)
    }
}
