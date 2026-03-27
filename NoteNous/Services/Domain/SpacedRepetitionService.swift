import Foundation
import os.log

/// SM-2 based spaced repetition scheduler for permanent notes.
/// Persists to a JSON file in Application Support/NoteNous/.
final class SpacedRepetitionService: ObservableObject {

    // MARK: - ReviewCard

    struct ReviewCard: Identifiable, Codable {
        let id: UUID  // = note UUID
        var easeFactor: Double  // starts at 2.5
        var interval: Int  // days until next review
        var repetitions: Int  // successful reviews count
        var nextReviewDate: Date
        var lastReviewDate: Date?
        var lastQuality: Int?  // 0-5 rating
    }

    // MARK: - Published State

    @Published private(set) var cards: [UUID: ReviewCard] = [:]
    @Published private(set) var streak: Int = 0

    // MARK: - Private

    private let logger = Logger(subsystem: "com.notenous.app", category: "SpacedRepetition")
    private let fileURL: URL
    private let streakFileURL: URL

    // MARK: - Init

    init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("NoteNous", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        self.fileURL = dir.appendingPathComponent("srs-cards.json")
        self.streakFileURL = dir.appendingPathComponent("srs-streak.json")

        loadFromDisk()
        loadStreak()
    }

    // MARK: - SM-2 Algorithm

    /// Process a review for a given note.
    /// - Parameters:
    ///   - noteId: UUID of the note being reviewed
    ///   - quality: 0=blackout, 1=wrong, 2=hard, 3=ok, 4=good, 5=easy
    func review(noteId: UUID, quality: Int) {
        let q = max(0, min(5, quality))
        guard var card = cards[noteId] else {
            logger.warning("Attempted review on unenrolled note: \(noteId.uuidString)")
            return
        }

        if q < 3 {
            // Failed review: reset
            card.repetitions = 0
            card.interval = 1
        } else {
            // Successful review
            if card.repetitions == 0 {
                card.interval = 1
            } else if card.repetitions == 1 {
                card.interval = 6
            } else {
                card.interval = Int(round(Double(card.interval) * card.easeFactor))
            }
            card.repetitions += 1
        }

        // Update ease factor (applies for all quality levels)
        let ef = card.easeFactor + (0.1 - Double(5 - q) * (0.08 + Double(5 - q) * 0.02))
        card.easeFactor = max(1.3, ef)

        card.lastQuality = q
        card.lastReviewDate = Date()
        card.nextReviewDate = Calendar.current.date(byAdding: .day, value: card.interval, to: Date()) ?? Date()

        cards[noteId] = card
        updateStreak()
        saveToDisk()
        saveStreak()

        logger.info("Reviewed note \(noteId.uuidString) q=\(q) next=\(card.interval)d ef=\(String(format: "%.2f", card.easeFactor))")
    }

    // MARK: - Due Cards

    /// Get cards due for review today (nextReviewDate <= end of today).
    func dueCards() -> [ReviewCard] {
        let endOfToday = Calendar.current.startOfDay(for: Date()).addingTimeInterval(86400)
        return cards.values
            .filter { $0.nextReviewDate <= endOfToday }
            .sorted { $0.nextReviewDate < $1.nextReviewDate }
    }

    /// Get cards due in the next N days.
    func upcomingCards(days: Int) -> [ReviewCard] {
        guard let futureDate = Calendar.current.date(byAdding: .day, value: days, to: Date()) else {
            return []
        }
        return cards.values
            .filter { $0.nextReviewDate <= futureDate }
            .sorted { $0.nextReviewDate < $1.nextReviewDate }
    }

    /// Get cards due on a specific date.
    func cardsDue(on date: Date) -> [ReviewCard] {
        let startOfDay = Calendar.current.startOfDay(for: date)
        let endOfDay = startOfDay.addingTimeInterval(86400)
        return cards.values
            .filter { $0.nextReviewDate >= startOfDay && $0.nextReviewDate < endOfDay }
            .sorted { $0.nextReviewDate < $1.nextReviewDate }
    }

    // MARK: - Enrollment

    /// Enroll a permanent note for review.
    func enroll(noteId: UUID) {
        guard cards[noteId] == nil else {
            logger.info("Note already enrolled: \(noteId.uuidString)")
            return
        }
        let card = ReviewCard(
            id: noteId,
            easeFactor: 2.5,
            interval: 0,
            repetitions: 0,
            nextReviewDate: Date(),
            lastReviewDate: nil,
            lastQuality: nil
        )
        cards[noteId] = card
        saveToDisk()
        logger.info("Enrolled note: \(noteId.uuidString)")
    }

    /// Remove from review schedule.
    func unenroll(noteId: UUID) {
        cards.removeValue(forKey: noteId)
        saveToDisk()
        logger.info("Unenrolled note: \(noteId.uuidString)")
    }

    /// Check if a note is enrolled.
    func isEnrolled(noteId: UUID) -> Bool {
        cards[noteId] != nil
    }

    // MARK: - Stats

    struct SRSStats {
        let enrolled: Int
        let dueToday: Int
        let dueThisWeek: Int
        let averageEase: Double
    }

    func stats() -> SRSStats {
        let due = dueCards().count
        let week = upcomingCards(days: 7).count
        let avgEase = cards.isEmpty ? 2.5 : cards.values.reduce(0.0) { $0 + $1.easeFactor } / Double(cards.count)

        return SRSStats(
            enrolled: cards.count,
            dueToday: due,
            dueThisWeek: week,
            averageEase: avgEase
        )
    }

    // MARK: - Streak

    private struct StreakData: Codable {
        var currentStreak: Int
        var lastReviewDate: Date?
    }

    private func updateStreak() {
        let today = Calendar.current.startOfDay(for: Date())
        if let lastDate = streakData.lastReviewDate {
            let lastDay = Calendar.current.startOfDay(for: lastDate)
            let diff = Calendar.current.dateComponents([.day], from: lastDay, to: today).day ?? 0
            if diff == 1 {
                streakData.currentStreak += 1
            } else if diff > 1 {
                streakData.currentStreak = 1
            }
            // diff == 0 means same day, no change
        } else {
            streakData.currentStreak = 1
        }
        streakData.lastReviewDate = Date()
        streak = streakData.currentStreak
    }

    private var streakData = StreakData(currentStreak: 0, lastReviewDate: nil)

    // MARK: - Persistence

    private func saveToDisk() {
        do {
            let cardsArray = Array(cards.values)
            let data = try JSONEncoder().encode(cardsArray)
            try data.write(to: fileURL, options: .atomicWrite)
        } catch {
            logger.error("Failed to save SRS cards: \(error.localizedDescription)")
        }
    }

    private func loadFromDisk() {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            logger.info("No SRS cards file found, starting fresh")
            return
        }
        do {
            let data = try Data(contentsOf: fileURL)
            let cardsArray = try JSONDecoder().decode([ReviewCard].self, from: data)
            cards = Dictionary(uniqueKeysWithValues: cardsArray.map { ($0.id, $0) })
            logger.info("Loaded \(self.cards.count) SRS cards from disk")
        } catch {
            logger.error("Failed to load SRS cards: \(error.localizedDescription)")
            cards = [:]
        }
    }

    private func saveStreak() {
        do {
            let data = try JSONEncoder().encode(streakData)
            try data.write(to: streakFileURL, options: .atomicWrite)
        } catch {
            logger.error("Failed to save streak: \(error.localizedDescription)")
        }
    }

    private func loadStreak() {
        guard FileManager.default.fileExists(atPath: streakFileURL.path) else { return }
        do {
            let data = try Data(contentsOf: streakFileURL)
            streakData = try JSONDecoder().decode(StreakData.self, from: data)
            // Check if streak is still valid (not broken by missing a day)
            if let lastDate = streakData.lastReviewDate {
                let today = Calendar.current.startOfDay(for: Date())
                let lastDay = Calendar.current.startOfDay(for: lastDate)
                let diff = Calendar.current.dateComponents([.day], from: lastDay, to: today).day ?? 0
                if diff > 1 {
                    streakData.currentStreak = 0
                }
            }
            streak = streakData.currentStreak
        } catch {
            logger.error("Failed to load streak: \(error.localizedDescription)")
        }
    }
}
