import Foundation
import CoreData
import os.log

/// Manages Luhmann's sparse keyword index.
/// Each keyword maps to 1-3 "entry point" notes — NOT every note about this topic.
/// Persists to a JSON file in Application Support/NoteNous/.
final class IndexService: ObservableObject {
    @Published private(set) var entries: [IndexEntry] = []

    private let logger = Logger(subsystem: "com.notenous.app", category: "IndexService")
    private let fileURL: URL

    static let maxEntryNotesPerKeyword = 3

    init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("NoteNous", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        self.fileURL = dir.appendingPathComponent("index-entries.json")

        loadFromDisk()
    }

    // MARK: - CRUD

    /// Add a new keyword entry or add a note to an existing keyword.
    /// Returns `false` if the keyword already has 3 entry notes (warns but allows override with `force`).
    @discardableResult
    func addEntry(keyword: String, noteId: UUID, force: Bool = false) -> Bool {
        let normalizedKeyword = keyword.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedKeyword.isEmpty else { return false }

        if let index = entries.firstIndex(where: { $0.keyword == normalizedKeyword }) {
            // Keyword exists — add note to it
            if entries[index].entryNoteIds.contains(noteId) {
                logger.info("Note already in index entry for '\(normalizedKeyword)'")
                return true
            }
            if entries[index].entryNoteIds.count >= Self.maxEntryNotesPerKeyword && !force {
                logger.warning("Keyword '\(normalizedKeyword)' already has \(Self.maxEntryNotesPerKeyword) entry notes. Use force to override.")
                return false
            }
            entries[index].entryNoteIds.append(noteId)
            entries[index].updatedAt = Date()
        } else {
            // New keyword
            let entry = IndexEntry(keyword: normalizedKeyword, entryNoteIds: [noteId])
            entries.append(entry)
        }

        saveToDisk()
        logger.info("Added entry note for keyword '\(normalizedKeyword)'")
        return true
    }

    /// Remove an entire keyword from the index.
    func removeEntry(keyword: String) {
        let normalized = keyword.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        entries.removeAll { $0.keyword == normalized }
        saveToDisk()
        logger.info("Removed index entry: '\(normalized)'")
    }

    /// Remove a specific note from a keyword entry.
    func removeNoteFromEntry(keyword: String, noteId: UUID) {
        let normalized = keyword.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard let index = entries.firstIndex(where: { $0.keyword == normalized }) else { return }
        entries[index].entryNoteIds.removeAll { $0 == noteId }
        entries[index].updatedAt = Date()

        // Remove the entire entry if no notes remain
        if entries[index].entryNoteIds.isEmpty {
            entries.remove(at: index)
        }

        saveToDisk()
    }

    /// Update the keyword text for an existing entry.
    func renameEntry(from oldKeyword: String, to newKeyword: String) {
        let normalizedOld = oldKeyword.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedNew = newKeyword.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard let index = entries.firstIndex(where: { $0.keyword == normalizedOld }) else { return }

        // Check if the new keyword already exists
        if entries.contains(where: { $0.keyword == normalizedNew }) {
            logger.warning("Cannot rename: keyword '\(normalizedNew)' already exists")
            return
        }

        entries[index].keyword = normalizedNew
        entries[index].updatedAt = Date()
        saveToDisk()
    }

    // MARK: - Queries

    /// Autocomplete keywords by prefix.
    func searchKeywords(prefix: String) -> [IndexEntry] {
        let normalized = prefix.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return allKeywordsSorted() }
        return entries
            .filter { $0.keyword.hasPrefix(normalized) }
            .sorted { $0.keyword < $1.keyword }
    }

    /// All keywords sorted alphabetically.
    func allKeywordsSorted() -> [IndexEntry] {
        entries.sorted { $0.keyword < $1.keyword }
    }

    /// Get entry for a specific keyword.
    func entry(for keyword: String) -> IndexEntry? {
        let normalized = keyword.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        return entries.first { $0.keyword == normalized }
    }

    /// Resolve UUIDs to NoteEntity objects using a Core Data context.
    func entryNotes(for keyword: String, in context: NSManagedObjectContext) -> [NoteEntity] {
        guard let entry = entry(for: keyword) else { return [] }
        return entry.entryNoteIds.compactMap { noteId in
            let request = NoteEntity.fetchRequest() as! NSFetchRequest<NoteEntity>
            request.predicate = NSPredicate(format: "id == %@", noteId as CVarArg)
            request.fetchLimit = 1
            return try? context.fetch(request).first
        }
    }

    /// Keywords that reference a given note.
    func keywords(for noteId: UUID) -> [IndexEntry] {
        entries.filter { $0.entryNoteIds.contains(noteId) }
    }

    /// Add an empty keyword (no notes yet) — used by IndexBrowserView.
    func addEmptyEntry(keyword: String) {
        let normalized = keyword.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return }
        guard !entries.contains(where: { $0.keyword == normalized }) else { return }
        entries.append(IndexEntry(keyword: normalized))
        saveToDisk()
    }

    /// Check if a keyword has more entry notes than recommended.
    func isOverloaded(keyword: String) -> Bool {
        guard let entry = entry(for: keyword) else { return false }
        return entry.entryNoteIds.count > Self.maxEntryNotesPerKeyword
    }

    // MARK: - Stats

    struct IndexStats {
        let totalKeywords: Int
        let totalEntryNotes: Int
        let averageNotesPerKeyword: Double
        let overloadedKeywords: Int
    }

    func stats() -> IndexStats {
        let totalNotes = entries.reduce(0) { $0 + $1.entryNoteIds.count }
        let avg = entries.isEmpty ? 0 : Double(totalNotes) / Double(entries.count)
        let overloaded = entries.filter { $0.entryNoteIds.count > Self.maxEntryNotesPerKeyword }.count

        return IndexStats(
            totalKeywords: entries.count,
            totalEntryNotes: totalNotes,
            averageNotesPerKeyword: avg,
            overloadedKeywords: overloaded
        )
    }

    // MARK: - Persistence

    private func saveToDisk() {
        do {
            let data = try JSONEncoder().encode(entries)
            try data.write(to: fileURL, options: .atomicWrite)
        } catch {
            logger.error("Failed to save index entries: \(error.localizedDescription)")
        }
    }

    private func loadFromDisk() {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            logger.info("No index file found, starting fresh")
            return
        }
        do {
            let data = try Data(contentsOf: fileURL)
            entries = try JSONDecoder().decode([IndexEntry].self, from: data)
            logger.info("Loaded \(self.entries.count) index entries from disk")
        } catch {
            logger.error("Failed to load index entries: \(error.localizedDescription)")
            entries = []
        }
    }
}
