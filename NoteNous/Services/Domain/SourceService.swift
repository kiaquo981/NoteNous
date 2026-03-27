import Foundation
import os.log

/// Manages Source CRUD and the "waiting period" workflow (Ryan Holiday's card system).
/// Persists to a JSON file in Application Support/NoteNous/.
final class SourceService: ObservableObject {
    @Published private(set) var sources: [Source] = []

    private let logger = Logger(subsystem: "com.notenous.app", category: "SourceService")
    private let fileURL: URL

    init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("NoteNous", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        self.fileURL = dir.appendingPathComponent("sources.json")

        loadFromDisk()
    }

    // MARK: - CRUD

    @discardableResult
    func addSource(
        title: String,
        author: String? = nil,
        sourceType: SourceType = .other,
        url: String? = nil,
        isbn: String? = nil,
        dateConsumed: Date? = nil,
        rating: Int? = nil,
        notes: String? = nil
    ) -> Source {
        let source = Source(
            title: title,
            author: author,
            sourceType: sourceType,
            url: url,
            isbn: isbn,
            dateConsumed: dateConsumed,
            rating: rating,
            notes: notes
        )
        sources.append(source)
        saveToDisk()
        logger.info("Added source: \(title)")
        return source
    }

    func updateSource(_ source: Source) {
        guard let index = sources.firstIndex(where: { $0.id == source.id }) else {
            logger.warning("Source not found for update: \(source.id.uuidString)")
            return
        }
        sources[index] = source
        saveToDisk()
        logger.info("Updated source: \(source.title)")
    }

    func deleteSource(id: UUID) {
        sources.removeAll { $0.id == id }
        saveToDisk()
        logger.info("Deleted source: \(id.uuidString)")
    }

    func source(for id: UUID) -> Source? {
        sources.first { $0.id == id }
    }

    // MARK: - Waiting Period Workflow

    /// Sources where the waiting period (>= 14 days since consumed) has passed and are ready to card.
    func sourcesReadyToCard() -> [Source] {
        sources.filter { $0.waitingStatus == .readyToCard }
    }

    /// Sources consumed but not yet carded (includes both waiting and ready).
    func sourcesPendingReview() -> [Source] {
        sources.filter { $0.dateConsumed != nil && $0.dateCarded == nil }
    }

    /// Sources already carded.
    func sourcesCarded() -> [Source] {
        sources.filter { $0.dateCarded != nil }
    }

    /// Mark a source as having started the carding process.
    func startCarding(id: UUID) {
        guard var source = source(for: id) else { return }
        source.dateCarded = Date()
        updateSource(source)
        logger.info("Started carding source: \(source.title)")
    }

    /// Link a note to a source and increment the card count.
    func linkNote(noteId: UUID, to sourceId: UUID) {
        guard var source = source(for: sourceId) else { return }
        if !source.linkedNoteIds.contains(noteId) {
            source.linkedNoteIds.append(noteId)
            source.cardsGenerated = source.linkedNoteIds.count
            updateSource(source)
        }
    }

    /// Unlink a note from a source.
    func unlinkNote(noteId: UUID, from sourceId: UUID) {
        guard var source = source(for: sourceId) else { return }
        source.linkedNoteIds.removeAll { $0 == noteId }
        source.cardsGenerated = source.linkedNoteIds.count
        updateSource(source)
    }

    // MARK: - Stats

    struct SourceStats {
        let totalSources: Int
        let waitingCount: Int
        let readyToCardCount: Int
        let cardedCount: Int
        let totalCardsGenerated: Int
        let averageCardsPerSource: Double
    }

    func stats() -> SourceStats {
        let carded = sourcesCarded()
        let totalCards = sources.reduce(0) { $0 + $1.cardsGenerated }
        let avgCards = carded.isEmpty ? 0 : Double(totalCards) / Double(carded.count)

        return SourceStats(
            totalSources: sources.count,
            waitingCount: sources.filter { $0.waitingStatus == .waiting }.count,
            readyToCardCount: sourcesReadyToCard().count,
            cardedCount: carded.count,
            totalCardsGenerated: totalCards,
            averageCardsPerSource: avgCards
        )
    }

    // MARK: - Persistence

    private func saveToDisk() {
        do {
            let data = try JSONEncoder().encode(sources)
            try data.write(to: fileURL, options: .atomicWrite)
        } catch {
            logger.error("Failed to save sources: \(error.localizedDescription)")
        }
    }

    private func loadFromDisk() {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            logger.info("No sources file found, starting fresh")
            return
        }
        do {
            let data = try Data(contentsOf: fileURL)
            sources = try JSONDecoder().decode([Source].self, from: data)
            logger.info("Loaded \(self.sources.count) sources from disk")
        } catch {
            logger.error("Failed to load sources: \(error.localizedDescription)")
            sources = []
        }
    }
}
