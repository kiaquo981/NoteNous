import CoreData
import os.log

/// Enforces and encourages the "one idea per note" principle from Zettelkasten methodology.
/// Analyzes notes for atomicity: word count, heading count, paragraph density, link density, title quality.
final class AtomicNoteService {
    private let context: NSManagedObjectContext
    private let logger = Logger(subsystem: "com.notenous.app", category: "AtomicNoteService")

    // MARK: - Configuration

    struct Config {
        var minWords: Int = 40
        var maxWords: Int = 400
        var maxHeadings: Int = 1
        var maxParagraphs: Int = 4
        var minTitleWords: Int = 4
    }

    var config = Config()

    init(context: NSManagedObjectContext) {
        self.context = context
    }

    // MARK: - Analysis

    /// Analyze a note and produce an atomicity report.
    func analyze(note: NoteEntity) -> AtomicityReport {
        let content = note.contentPlainText
        let title = note.title

        let wordCount = countWords(in: content)
        let headingCount = countHeadings(in: note.content)
        let paragraphCount = countSubstantialParagraphs(in: content)
        let outgoingLinkCount = note.outgoingLinksArray.count
        let titleWordCount = countWords(in: title)

        var issues: [AtomicityIssue] = []

        // Only enforce atomicity on permanent notes
        let isPermanent = note.noteType == .permanent
        let isLiterature = note.noteType == .literature

        if isPermanent || isLiterature {
            // Word count checks
            if wordCount < config.minWords && wordCount > 0 {
                issues.append(.tooShort(wordCount: wordCount, minimum: config.minWords))
            }
            if wordCount > config.maxWords {
                issues.append(.tooLong(wordCount: wordCount, maximum: config.maxWords))
            }

            // Heading check — multiple headings suggest multiple ideas
            if headingCount > config.maxHeadings {
                issues.append(.multipleHeadings(count: headingCount))
            }

            // Paragraph check
            if paragraphCount > config.maxParagraphs {
                issues.append(.tooManyParagraphs(count: paragraphCount))
            }
        }

        if isPermanent {
            // Title should be a proposition, not a topic
            if titleWordCount > 0 && titleWordCount < config.minTitleWords {
                issues.append(.topicTitle)
            }

            // Link density — permanent notes should be connected
            if outgoingLinkCount == 0 {
                issues.append(.noOutgoingLinks)
            }
        }

        if isLiterature {
            // Literature notes should reference a source
            if note.sourceURL == nil && note.sourceTitle == nil {
                issues.append(.missingSource)
            }
        }

        return AtomicityReport(
            wordCount: wordCount,
            headingCount: headingCount,
            paragraphCount: paragraphCount,
            outgoingLinkCount: outgoingLinkCount,
            titleWordCount: titleWordCount,
            issues: issues
        )
    }

    /// Quick check: does this note pass atomicity?
    func isAtomic(note: NoteEntity) -> Bool {
        analyze(note: note).isAtomic
    }

    /// Batch analysis: percentage of permanent notes that are atomic.
    func atomicityPercentage() -> Double {
        let request = NoteEntity.fetchRequest() as! NSFetchRequest<NoteEntity>
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            NSPredicate(format: "noteTypeRaw == %d", NoteType.permanent.rawValue),
            NSPredicate(format: "isArchived == NO")
        ])

        do {
            let permanentNotes = try context.fetch(request)
            guard !permanentNotes.isEmpty else { return 100.0 }

            let atomicCount = permanentNotes.filter { isAtomic(note: $0) }.count
            return Double(atomicCount) / Double(permanentNotes.count) * 100.0
        } catch {
            logger.error("Failed to calculate atomicity: \(error.localizedDescription)")
            return 0.0
        }
    }

    /// Suggestions for splitting a note that has multiple ideas.
    func splitSuggestions(for note: NoteEntity) -> [String] {
        let report = analyze(note: note)
        var suggestions: [String] = []

        if case .multipleHeadings(let count) = report.issues.first(where: {
            if case .multipleHeadings = $0 { return true }; return false
        }) {
            suggestions.append("This note has \(count) headings. Each heading likely represents a separate idea. Consider creating \(count) separate notes.")
        }

        if case .tooManyParagraphs(let count) = report.issues.first(where: {
            if case .tooManyParagraphs = $0 { return true }; return false
        }) {
            suggestions.append("With \(count) paragraphs, this note might cover multiple points. Group related paragraphs and extract each group into its own note.")
        }

        if case .tooLong(let wordCount, let maximum) = report.issues.first(where: {
            if case .tooLong = $0 { return true }; return false
        }) {
            let estimatedNotes = max(2, wordCount / maximum)
            suggestions.append("At \(wordCount) words, consider splitting into approximately \(estimatedNotes) notes of \(maximum) words each.")
        }

        return suggestions
    }

    /// Count orphan notes (permanent notes with no links at all).
    func orphanNoteCount() -> Int {
        let request = NoteEntity.fetchRequest() as! NSFetchRequest<NoteEntity>
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            NSPredicate(format: "noteTypeRaw == %d", NoteType.permanent.rawValue),
            NSPredicate(format: "isArchived == NO")
        ])

        do {
            let notes = try context.fetch(request)
            return notes.filter { $0.totalLinkCount == 0 }.count
        } catch {
            return 0
        }
    }

    /// Average outgoing links per permanent note.
    func averageLinkDensity() -> Double {
        let request = NoteEntity.fetchRequest() as! NSFetchRequest<NoteEntity>
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            NSPredicate(format: "noteTypeRaw == %d", NoteType.permanent.rawValue),
            NSPredicate(format: "isArchived == NO")
        ])

        do {
            let notes = try context.fetch(request)
            guard !notes.isEmpty else { return 0 }
            let totalLinks = notes.reduce(0) { $0 + $1.outgoingLinksArray.count }
            return Double(totalLinks) / Double(notes.count)
        } catch {
            return 0
        }
    }

    // MARK: - Text Analysis Helpers

    private func countWords(in text: String) -> Int {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return 0 }
        return trimmed.components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .count
    }

    /// Count markdown headings (# or ##) in content.
    private func countHeadings(in markdown: String) -> Int {
        let lines = markdown.components(separatedBy: .newlines)
        return lines.filter { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            return trimmed.hasPrefix("# ") || trimmed.hasPrefix("## ")
        }.count
    }

    /// Count paragraphs with more than 20 words (substantial content).
    private func countSubstantialParagraphs(in text: String) -> Int {
        let paragraphs = text.components(separatedBy: "\n\n")
        return paragraphs.filter { paragraph in
            let words = paragraph.trimmingCharacters(in: .whitespacesAndNewlines)
                .components(separatedBy: .whitespacesAndNewlines)
                .filter { !$0.isEmpty }
            return words.count >= 20
        }.count
    }
}
