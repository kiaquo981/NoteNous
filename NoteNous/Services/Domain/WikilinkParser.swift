import CoreData
import os.log

// MARK: - WikilinkMatch

struct WikilinkMatch: Equatable {
    let fullMatch: String
    let targetTitle: String
    let displayText: String?
    let range: Range<String.Index>

    static func == (lhs: WikilinkMatch, rhs: WikilinkMatch) -> Bool {
        lhs.fullMatch == rhs.fullMatch && lhs.range == rhs.range
    }
}

// MARK: - WikilinkResolution

struct WikilinkResolution {
    let match: WikilinkMatch
    let resolvedNote: NoteEntity?

    var isBroken: Bool { resolvedNote == nil }
}

// MARK: - WikilinkParser

final class WikilinkParser {
    private let context: NSManagedObjectContext
    private let logger = Logger(subsystem: "com.notenous.app", category: "WikilinkParser")

    /// Regex pattern: `[[target]]` or `[[target|display]]`
    /// Captures the inner content between `[[` and `]]`
    private static let wikilinkPattern = try! NSRegularExpression(
        pattern: #"\[\[([^\[\]]+?)\]\]"#,
        options: []
    )

    init(context: NSManagedObjectContext) {
        self.context = context
    }

    // MARK: - Extraction

    /// Extracts all wikilink matches from a string without resolving them.
    func extractWikilinks(from text: String) -> [WikilinkMatch] {
        let nsRange = NSRange(text.startIndex..., in: text)
        let results = Self.wikilinkPattern.matches(in: text, options: [], range: nsRange)

        return results.compactMap { result -> WikilinkMatch? in
            guard let fullRange = Range(result.range, in: text),
                  let innerRange = Range(result.range(at: 1), in: text) else {
                return nil
            }

            let fullMatch = String(text[fullRange])
            let inner = String(text[innerRange])

            let components = inner.split(separator: "|", maxSplits: 1)
            let targetTitle = components[0].trimmingCharacters(in: .whitespaces)
            let displayText: String? = components.count > 1
                ? components[1].trimmingCharacters(in: .whitespaces)
                : nil

            guard !targetTitle.isEmpty else { return nil }

            return WikilinkMatch(
                fullMatch: fullMatch,
                targetTitle: targetTitle,
                displayText: displayText,
                range: fullRange
            )
        }
    }

    // MARK: - Resolution

    /// Resolves all wikilinks in text to NoteEntity references.
    func resolveWikilinks(in text: String) -> [WikilinkResolution] {
        let matches = extractWikilinks(from: text)
        return matches.map { match in
            let note = findNote(byTitle: match.targetTitle)
            return WikilinkResolution(match: match, resolvedNote: note)
        }
    }

    /// Returns only broken links (wikilinks with no matching note).
    func brokenLinks(in text: String) -> [WikilinkMatch] {
        resolveWikilinks(in: text)
            .filter(\.isBroken)
            .map(\.match)
    }

    /// Returns only resolved links (wikilinks that match an existing note).
    func resolvedLinks(in text: String) -> [(match: WikilinkMatch, note: NoteEntity)] {
        resolveWikilinks(in: text)
            .compactMap { resolution in
                guard let note = resolution.resolvedNote else { return nil }
                return (match: resolution.match, note: note)
            }
    }

    // MARK: - Note Lookup

    /// Finds a note by title (case-insensitive).
    func findNote(byTitle title: String) -> NoteEntity? {
        let request = NoteEntity.fetchRequest() as! NSFetchRequest<NoteEntity>
        request.predicate = NSPredicate(format: "title ==[cd] %@", title)
        request.fetchLimit = 1

        do {
            return try context.fetch(request).first
        } catch {
            logger.error("Failed to find note by title '\(title)': \(error.localizedDescription)")
            return nil
        }
    }

    /// Finds notes whose titles contain the query (for autocomplete).
    func searchNotes(matching query: String, limit: Int = 20) -> [NoteEntity] {
        guard !query.isEmpty else { return [] }

        let request = NoteEntity.fetchRequest() as! NSFetchRequest<NoteEntity>
        request.predicate = NSCompoundPredicate(orPredicateWithSubpredicates: [
            NSPredicate(format: "title CONTAINS[cd] %@", query),
            NSPredicate(format: "zettelId CONTAINS[cd] %@", query)
        ])
        request.sortDescriptors = [NSSortDescriptor(key: "updatedAt", ascending: false)]
        request.fetchLimit = limit

        do {
            return try context.fetch(request)
        } catch {
            logger.error("Wikilink search failed for '\(query)': \(error.localizedDescription)")
            return []
        }
    }

    // MARK: - Note Creation from Broken Links

    /// Creates a new note from a broken wikilink.
    @discardableResult
    func createNoteFromBrokenLink(_ match: WikilinkMatch) -> NoteEntity {
        let note = NoteEntity(context: context)
        note.id = UUID()
        note.zettelId = ZettelIDGenerator.generate()
        note.title = match.targetTitle
        note.content = ""
        note.contentPlainText = ""
        note.paraCategory = .inbox
        note.codeStage = .captured
        note.noteType = .fleeting
        note.aiClassified = false
        note.aiConfidence = 0
        note.isPinned = false
        note.isArchived = false
        note.createdAt = Date()
        note.updatedAt = Date()

        save()
        logger.info("Created note from broken wikilink: '\(match.targetTitle)'")
        return note
    }

    // MARK: - Unlinked Mentions

    /// Finds notes that mention the given note's title in their content
    /// but do not have an explicit link to it.
    func unlinkedMentions(for note: NoteEntity) -> [NoteEntity] {
        let title = note.title
        guard !title.isEmpty else { return [] }

        let request = NoteEntity.fetchRequest() as! NSFetchRequest<NoteEntity>
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            NSPredicate(format: "contentPlainText CONTAINS[cd] %@", title),
            NSPredicate(format: "SELF != %@", note),
            NSPredicate(format: "isArchived == NO")
        ])
        request.sortDescriptors = [NSSortDescriptor(key: "updatedAt", ascending: false)]
        request.fetchLimit = 50

        do {
            let mentioningNotes = try context.fetch(request)

            // Filter out notes that already have a link to this note
            let linkedNoteIDs = Set(
                note.incomingLinksArray.compactMap { $0.sourceNote?.objectID }
            )

            return mentioningNotes.filter { !linkedNoteIDs.contains($0.objectID) }
        } catch {
            logger.error("Failed to find unlinked mentions: \(error.localizedDescription)")
            return []
        }
    }

    // MARK: - Link Sync

    /// Synchronizes wikilinks in content with actual NoteLinkEntity records.
    /// Creates links for resolved wikilinks that don't have a corresponding link entity,
    /// using `.reference` as the default link type.
    func syncLinks(for note: NoteEntity) {
        let resolved = resolvedLinks(in: note.content)
        let existingTargetIDs = Set(note.outgoingLinksArray.compactMap { $0.targetNote?.objectID })

        for (_, targetNote) in resolved {
            guard !existingTargetIDs.contains(targetNote.objectID),
                  targetNote.objectID != note.objectID else {
                continue
            }

            let link = NoteLinkEntity(context: context)
            link.id = UUID()
            link.sourceNote = note
            link.targetNote = targetNote
            link.linkType = .reference
            link.strength = 0.5
            link.isAISuggested = false
            link.isConfirmed = true
            link.createdAt = Date()
        }

        save()
    }

    // MARK: - Formatting

    /// Builds a wikilink string from a note title.
    static func formatWikilink(title: String, displayText: String? = nil) -> String {
        if let display = displayText {
            return "[[\(title)|\(display)]]"
        }
        return "[[\(title)]]"
    }

    // MARK: - Private

    private func save() {
        guard context.hasChanges else { return }
        do {
            try context.save()
        } catch {
            logger.error("Save failed: \(error.localizedDescription)")
        }
    }
}
