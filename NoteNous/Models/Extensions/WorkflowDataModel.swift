import Foundation

// MARK: - Source Type

enum SourceType: Int, Codable, CaseIterable, Identifiable {
    case book = 0
    case article = 1
    case video = 2
    case podcast = 3
    case conversation = 4
    case tweet = 5
    case other = 6

    var id: Int { rawValue }

    var label: String {
        switch self {
        case .book: "Book"
        case .article: "Article"
        case .video: "Video"
        case .podcast: "Podcast"
        case .conversation: "Conversation"
        case .tweet: "Tweet"
        case .other: "Other"
        }
    }

    var icon: String {
        switch self {
        case .book: "book.closed"
        case .article: "doc.text"
        case .video: "play.rectangle"
        case .podcast: "waveform"
        case .conversation: "bubble.left.and.bubble.right"
        case .tweet: "at"
        case .other: "ellipsis.circle"
        }
    }
}

// MARK: - Source (JSON-persisted)

struct Source: Identifiable, Codable, Equatable {
    let id: UUID
    var title: String
    var author: String?
    var sourceType: SourceType
    var url: String?
    var isbn: String?
    var dateConsumed: Date?
    var dateCarded: Date?
    var cardsGenerated: Int
    var rating: Int?
    var notes: String?
    var linkedNoteIds: [UUID]
    var createdAt: Date

    init(
        id: UUID = UUID(),
        title: String,
        author: String? = nil,
        sourceType: SourceType = .other,
        url: String? = nil,
        isbn: String? = nil,
        dateConsumed: Date? = nil,
        dateCarded: Date? = nil,
        cardsGenerated: Int = 0,
        rating: Int? = nil,
        notes: String? = nil,
        linkedNoteIds: [UUID] = [],
        createdAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.author = author
        self.sourceType = sourceType
        self.url = url
        self.isbn = isbn
        self.dateConsumed = dateConsumed
        self.dateCarded = dateCarded
        self.cardsGenerated = cardsGenerated
        self.rating = rating
        self.notes = notes
        self.linkedNoteIds = linkedNoteIds
        self.createdAt = createdAt
    }

    /// Days since the source was consumed and not yet carded.
    var waitingPeriodDays: Int? {
        guard let consumed = dateConsumed, dateCarded == nil else { return nil }
        return Calendar.current.dateComponents([.day], from: consumed, to: Date()).day
    }

    /// Holiday recommends 2-4 weeks before making cards from a source.
    var isReadyToCard: Bool {
        guard let days = waitingPeriodDays else { return dateCarded == nil && dateConsumed != nil }
        return days >= 14
    }

    var waitingStatus: WaitingStatus {
        if dateCarded != nil { return .carded }
        guard let days = waitingPeriodDays else { return .notConsumed }
        if days >= 14 { return .readyToCard }
        return .waiting
    }

    enum WaitingStatus: String, Codable {
        case notConsumed
        case waiting
        case readyToCard
        case carded

        var label: String {
            switch self {
            case .notConsumed: "Not Consumed"
            case .waiting: "Waiting"
            case .readyToCard: "Ready to Card"
            case .carded: "Carded"
            }
        }

        var color: String {
            switch self {
            case .notConsumed: "gray"
            case .waiting: "yellow"
            case .readyToCard: "green"
            case .carded: "blue"
            }
        }
    }
}

// MARK: - Index Entry (JSON-persisted, Luhmann's keyword index)

struct IndexEntry: Identifiable, Codable, Equatable, Hashable {
    let id: UUID
    var keyword: String
    var entryNoteIds: [UUID]  // deliberately sparse: 1-3 max per keyword
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        keyword: String,
        entryNoteIds: [UUID] = [],
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.keyword = keyword.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        self.entryNoteIds = entryNoteIds
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

// MARK: - Atomicity Report

struct AtomicityReport: Equatable {
    let wordCount: Int
    let headingCount: Int
    let paragraphCount: Int
    let outgoingLinkCount: Int
    let titleWordCount: Int
    let issues: [AtomicityIssue]

    var isAtomic: Bool { issues.isEmpty }

    var severity: Severity {
        if issues.isEmpty { return .good }
        if issues.contains(where: { $0.isCritical }) { return .critical }
        return .warning
    }

    enum Severity {
        case good, warning, critical

        var label: String {
            switch self {
            case .good: "Atomic"
            case .warning: "Minor Issues"
            case .critical: "Needs Work"
            }
        }
    }
}

enum AtomicityIssue: Equatable {
    case tooShort(wordCount: Int, minimum: Int)
    case tooLong(wordCount: Int, maximum: Int)
    case multipleHeadings(count: Int)
    case tooManyParagraphs(count: Int)
    case topicTitle
    case noOutgoingLinks
    case missingSource

    var isCritical: Bool {
        switch self {
        case .tooShort: true
        case .tooLong: true             // 1000+ words = definitely needs splitting
        case .multipleHeadings: true    // multiple H2+ = multiple ideas
        case .tooManyParagraphs: true   // 7+ paragraphs = too complex
        case .topicTitle: false
        case .noOutgoingLinks: false
        case .missingSource: false
        }
    }

    var description: String {
        switch self {
        case .tooShort(let wordCount, let minimum):
            "Too short (\(wordCount) words, minimum \(minimum))"
        case .tooLong(let wordCount, let maximum):
            "Too long (\(wordCount) words, maximum \(maximum)). Consider splitting."
        case .multipleHeadings(let count):
            "\(count) headings detected. Each note should contain one idea."
        case .tooManyParagraphs(let count):
            "\(count) paragraphs. Consider splitting into separate notes."
        case .topicTitle:
            "Title reads like a topic, not a proposition. Use a complete statement."
        case .noOutgoingLinks:
            "No outgoing links. Connect this idea to your existing knowledge."
        case .missingSource:
            "Literature note without a source reference."
        }
    }

    var icon: String {
        switch self {
        case .tooShort: "text.badge.minus"
        case .tooLong: "text.badge.plus"
        case .multipleHeadings: "list.bullet"
        case .tooManyParagraphs: "text.alignleft"
        case .topicTitle: "textformat"
        case .noOutgoingLinks: "link"
        case .missingSource: "book.closed"
        }
    }
}
