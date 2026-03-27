import CoreData
import os.log

// MARK: - Import Stats

struct ObsidianImportStats {
    var notesImported: Int = 0
    var linksCreated: Int = 0
    var tagsCreated: Int = 0
    var skipped: Int = 0
    var errors: [String] = []
}

// MARK: - Obsidian Importer

final class ObsidianImporter {
    private let context: NSManagedObjectContext
    private let logger = Logger(subsystem: "com.notenous.app", category: "ObsidianImporter")

    init(context: NSManagedObjectContext) {
        self.context = context
    }

    // MARK: - Public

    /// Import all .md files from a folder (Obsidian vault).
    /// Returns stats about the import operation.
    func importVault(at folderURL: URL) async -> ObsidianImportStats {
        var stats = ObsidianImportStats()
        let fileManager = FileManager.default

        // Collect all .md files recursively
        guard let enumerator = fileManager.enumerator(
            at: folderURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            stats.errors.append("Could not enumerate folder: \(folderURL.path)")
            return stats
        }

        var mdFiles: [URL] = []
        for case let fileURL as URL in enumerator {
            if fileURL.pathExtension.lowercased() == "md" {
                mdFiles.append(fileURL)
            }
        }

        logger.info("Found \(mdFiles.count) markdown files in vault")

        // Phase 1: Create all notes (without links)
        var titleToNote: [String: NoteEntity] = [:]

        for fileURL in mdFiles {
            do {
                let rawContent = try String(contentsOf: fileURL, encoding: .utf8)
                let filename = fileURL.deletingPathExtension().lastPathComponent
                let parsed = parseFrontmatter(from: rawContent)

                let title = parsed.frontmatter["title"] ?? filename
                let contentBody = parsed.content

                // Determine note type
                let noteType = classifyNoteType(content: contentBody, frontmatter: parsed.frontmatter)

                // Create note
                let note = NoteEntity(context: context)
                note.id = UUID()
                note.zettelId = ZettelIDGenerator.generate()
                note.title = title
                note.content = contentBody
                note.contentPlainText = contentBody.replacingOccurrences(
                    of: #"[#*_`\[\]()]"#, with: "", options: .regularExpression
                )
                note.paraCategory = .inbox
                note.codeStage = .captured
                note.noteType = noteType
                note.aiClassified = false
                note.aiConfidence = 0
                note.isPinned = false
                note.isArchived = false
                note.createdAt = Date()
                note.updatedAt = Date()

                titleToNote[title.lowercased()] = note
                stats.notesImported += 1

                // Parse and create tags from frontmatter
                if let tagsString = parsed.frontmatter["tags"] {
                    let tagNames = parseTagList(tagsString)
                    for tagName in tagNames {
                        let tag = findOrCreateTag(name: tagName)
                        let mutable = note.mutableSetValue(forKey: "tags")
                        mutable.add(tag)
                        tag.usageCount += 1
                        stats.tagsCreated += 1
                    }
                }

                // Parse inline #tags from content
                let inlineTags = extractInlineTags(from: contentBody)
                for tagName in inlineTags {
                    let tag = findOrCreateTag(name: tagName)
                    let mutable = note.mutableSetValue(forKey: "tags")
                    if !(mutable.contains(tag)) {
                        mutable.add(tag)
                        tag.usageCount += 1
                        stats.tagsCreated += 1
                    }
                }

            } catch {
                stats.errors.append("Failed to read \(fileURL.lastPathComponent): \(error.localizedDescription)")
                stats.skipped += 1
            }
        }

        // Phase 2: Create links from [[wikilinks]]
        for (_, note) in titleToNote {
            let wikilinks = extractWikilinkTargets(from: note.content)
            for targetTitle in wikilinks {
                if let targetNote = titleToNote[targetTitle.lowercased()],
                   targetNote.objectID != note.objectID {
                    let link = NoteLinkEntity(context: context)
                    link.id = UUID()
                    link.sourceNote = note
                    link.targetNote = targetNote
                    link.linkType = .reference
                    link.strength = 0.5
                    link.isAISuggested = false
                    link.isConfirmed = true
                    link.createdAt = Date()
                    stats.linksCreated += 1
                }
            }
        }

        // Save all changes
        do {
            try context.save()
            logger.info("Import complete: \(stats.notesImported) notes, \(stats.linksCreated) links, \(stats.tagsCreated) tags")
        } catch {
            stats.errors.append("Failed to save: \(error.localizedDescription)")
            logger.error("Import save failed: \(error.localizedDescription)")
        }

        return stats
    }

    // MARK: - Frontmatter Parsing

    private struct ParsedMarkdown {
        let frontmatter: [String: String]
        let content: String
    }

    private func parseFrontmatter(from text: String) -> ParsedMarkdown {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)

        guard trimmed.hasPrefix("---") else {
            return ParsedMarkdown(frontmatter: [:], content: text)
        }

        let lines = trimmed.components(separatedBy: "\n")
        guard lines.count > 2 else {
            return ParsedMarkdown(frontmatter: [:], content: text)
        }

        var frontmatter: [String: String] = [:]
        var endIndex = -1

        for i in 1..<lines.count {
            let line = lines[i].trimmingCharacters(in: .whitespaces)
            if line == "---" {
                endIndex = i
                break
            }
            let parts = line.split(separator: ":", maxSplits: 1)
            if parts.count == 2 {
                let key = parts[0].trimmingCharacters(in: .whitespaces).lowercased()
                let value = parts[1].trimmingCharacters(in: .whitespaces)
                    .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
                frontmatter[key] = value
            }
        }

        guard endIndex > 0 else {
            return ParsedMarkdown(frontmatter: [:], content: text)
        }

        let contentLines = Array(lines[(endIndex + 1)...])
        let content = contentLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)

        return ParsedMarkdown(frontmatter: frontmatter, content: content)
    }

    // MARK: - Tag Parsing

    private func parseTagList(_ value: String) -> [String] {
        // Handle YAML list formats: [tag1, tag2] or tag1, tag2
        let cleaned = value
            .trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
            .replacingOccurrences(of: "#", with: "")
        return cleaned.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    private func extractInlineTags(from text: String) -> [String] {
        let pattern = #"(?:^|\s)#([a-zA-Z][a-zA-Z0-9_/-]*)"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return [] }

        let nsRange = NSRange(text.startIndex..., in: text)
        let matches = regex.matches(in: text, options: [], range: nsRange)

        return matches.compactMap { match in
            guard let range = Range(match.range(at: 1), in: text) else { return nil }
            return String(text[range])
        }
    }

    // MARK: - Wikilink Extraction

    private func extractWikilinkTargets(from text: String) -> [String] {
        let pattern = #"\[\[([^\[\]]+?)\]\]"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return [] }

        let nsRange = NSRange(text.startIndex..., in: text)
        let matches = regex.matches(in: text, options: [], range: nsRange)

        return matches.compactMap { match in
            guard let range = Range(match.range(at: 1), in: text) else { return nil }
            let inner = String(text[range])
            // Handle [[target|display]] — take target part only
            let target = inner.split(separator: "|", maxSplits: 1).first
                .map { $0.trimmingCharacters(in: .whitespaces) } ?? inner
            return target.isEmpty ? nil : target
        }
    }

    // MARK: - Classification

    private func classifyNoteType(content: String, frontmatter: [String: String]) -> NoteType {
        // Has source URL → literature
        if frontmatter["source"] != nil || frontmatter["url"] != nil {
            return .literature
        }

        // Check content for URLs that suggest a literature note
        let urlPattern = #"https?://[^\s]+"#
        if let regex = try? NSRegularExpression(pattern: urlPattern, options: []),
           regex.firstMatch(in: content, options: [], range: NSRange(content.startIndex..., in: content)) != nil,
           content.count < 500 {
            return .literature
        }

        // Short content → fleeting
        if content.count < 100 {
            return .fleeting
        }

        // Default → permanent
        return .permanent
    }

    // MARK: - Tag Helper

    private func findOrCreateTag(name: String) -> TagEntity {
        let normalized = name.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)

        let request = TagEntity.fetchRequest() as! NSFetchRequest<TagEntity>
        request.predicate = NSPredicate(format: "name == %@", normalized)
        request.fetchLimit = 1

        if let existing = try? context.fetch(request).first {
            return existing
        }

        let tag = TagEntity(context: context)
        tag.id = UUID()
        tag.name = normalized
        tag.usageCount = 0
        tag.createdAt = Date()
        return tag
    }
}
