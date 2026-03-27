import CoreData
import os.log

// MARK: - Search Result

struct SearchResult: Identifiable {
    let id: NSManagedObjectID
    let note: NoteEntity
    let relevanceScore: Double
    let matchType: MatchType
    let matchedRanges: [MatchedRange]

    enum MatchType: Int, Comparable {
        case exactTitle = 4
        case titleContains = 3
        case tagMatch = 2
        case contentMatch = 1

        static func < (lhs: MatchType, rhs: MatchType) -> Bool {
            lhs.rawValue < rhs.rawValue
        }

        var label: String {
            switch self {
            case .exactTitle: return "Title"
            case .titleContains: return "Title"
            case .tagMatch: return "Tag"
            case .contentMatch: return "Content"
            }
        }

        var icon: String {
            switch self {
            case .exactTitle, .titleContains: return "textformat"
            case .tagMatch: return "tag"
            case .contentMatch: return "doc.text"
            }
        }
    }
}

struct MatchedRange {
    let field: String
    let range: Range<String.Index>
    let text: String
}

// MARK: - Search Filter

enum SearchScope: String, CaseIterable, Identifiable {
    case all = "All"
    case titles = "Titles"
    case content = "Content"
    case tags = "Tags"

    var id: String { rawValue }
}

// MARK: - Search Service

final class SearchService {
    private let context: NSManagedObjectContext
    private let logger = Logger(subsystem: "com.notenous.app", category: "SearchService")

    private static let recentSearchesKey = "SearchService.recentSearches"
    private static let maxRecentSearches = 10

    init(context: NSManagedObjectContext) {
        self.context = context
    }

    // MARK: - Full-text Search with Ranking

    func search(query: String, scope: SearchScope = .all) -> [SearchResult] {
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else { return [] }

        let trimmedQuery = query.trimmingCharacters(in: .whitespaces)
        let lowercasedQuery = trimmedQuery.lowercased()

        let notes = fetchCandidateNotes(query: trimmedQuery, scope: scope)
        var results: [SearchResult] = []

        for note in notes {
            if let result = rankNote(note, query: lowercasedQuery, scope: scope) {
                results.append(result)
            }
        }

        results.sort { lhs, rhs in
            if lhs.matchType != rhs.matchType {
                return lhs.matchType > rhs.matchType
            }
            return lhs.relevanceScore > rhs.relevanceScore
        }

        return results
    }

    // MARK: - Recent Searches

    var recentSearches: [String] {
        UserDefaults.standard.stringArray(forKey: Self.recentSearchesKey) ?? []
    }

    func addRecentSearch(_ query: String) {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }

        var recents = recentSearches
        recents.removeAll { $0.lowercased() == trimmed.lowercased() }
        recents.insert(trimmed, at: 0)
        if recents.count > Self.maxRecentSearches {
            recents = Array(recents.prefix(Self.maxRecentSearches))
        }
        UserDefaults.standard.set(recents, forKey: Self.recentSearchesKey)
    }

    func clearRecentSearches() {
        UserDefaults.standard.removeObject(forKey: Self.recentSearchesKey)
    }

    // MARK: - Search Suggestions

    func suggestions(for prefix: String) -> [String] {
        guard !prefix.isEmpty else { return [] }
        let lowered = prefix.lowercased()
        var suggestions: [String] = []

        // Tag-based suggestions
        let tagRequest = NSFetchRequest<TagEntity>(entityName: "TagEntity")
        tagRequest.predicate = NSPredicate(format: "name CONTAINS[cd] %@", prefix)
        tagRequest.fetchLimit = 5
        if let tags = try? context.fetch(tagRequest) {
            suggestions.append(contentsOf: tags.compactMap { $0.name })
        }

        // Concept-based suggestions
        let conceptRequest = NSFetchRequest<ConceptEntity>(entityName: "ConceptEntity")
        conceptRequest.predicate = NSPredicate(format: "name CONTAINS[cd] %@", prefix)
        conceptRequest.fetchLimit = 5
        if let concepts = try? context.fetch(conceptRequest) {
            suggestions.append(contentsOf: concepts.compactMap { $0.name })
        }

        // Deduplicate and filter
        return Array(Set(suggestions.filter { $0.lowercased().contains(lowered) }).prefix(8))
    }

    // MARK: - Match Count

    func matchCount(query: String, in notes: [NoteEntity]) -> Int {
        guard !query.isEmpty else { return notes.count }
        let lowered = query.lowercased()
        return notes.filter { noteMatches($0, query: lowered, scope: .all) }.count
    }

    // MARK: - Private

    private func fetchCandidateNotes(query: String, scope: SearchScope) -> [NoteEntity] {
        let request = NoteEntity.fetchRequest() as! NSFetchRequest<NoteEntity>
        request.fetchBatchSize = 20
        request.fetchLimit = 100
        request.sortDescriptors = [NSSortDescriptor(key: "updatedAt", ascending: false)]

        var predicates: [NSPredicate] = [NSPredicate(format: "isArchived == NO")]

        var searchPredicates: [NSPredicate] = []
        switch scope {
        case .all:
            searchPredicates = [
                NSPredicate(format: "title CONTAINS[cd] %@", query),
                NSPredicate(format: "contentPlainText CONTAINS[cd] %@", query),
                NSPredicate(format: "zettelId CONTAINS[cd] %@", query),
                NSPredicate(format: "ANY tags.name CONTAINS[cd] %@", query)
            ]
        case .titles:
            searchPredicates = [NSPredicate(format: "title CONTAINS[cd] %@", query)]
        case .content:
            searchPredicates = [NSPredicate(format: "contentPlainText CONTAINS[cd] %@", query)]
        case .tags:
            searchPredicates = [NSPredicate(format: "ANY tags.name CONTAINS[cd] %@", query)]
        }

        predicates.append(NSCompoundPredicate(orPredicateWithSubpredicates: searchPredicates))
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: predicates)

        do {
            return try context.fetch(request)
        } catch {
            logger.error("Search fetch failed: \(error.localizedDescription)")
            return []
        }
    }

    private func rankNote(_ note: NoteEntity, query: String, scope: SearchScope) -> SearchResult? {
        var matchedRanges: [MatchedRange] = []
        var bestType: SearchResult.MatchType?
        var score: Double = 0

        let titleLower = note.title.lowercased()
        let contentLower = note.contentPlainText.lowercased()

        // Exact title match
        if scope == .all || scope == .titles {
            if titleLower == query {
                bestType = .exactTitle
                score = 100
                if let range = note.title.range(of: query, options: .caseInsensitive) {
                    matchedRanges.append(MatchedRange(field: "title", range: range, text: note.title))
                }
            } else if titleLower.contains(query) {
                if bestType == nil || SearchResult.MatchType.titleContains > bestType! {
                    bestType = .titleContains
                }
                let titleScore = Double(query.count) / Double(max(titleLower.count, 1)) * 80
                score = max(score, titleScore)
                if let range = note.title.range(of: query, options: .caseInsensitive) {
                    matchedRanges.append(MatchedRange(field: "title", range: range, text: note.title))
                }
            }
        }

        // Tag match
        if scope == .all || scope == .tags {
            for tag in note.tagsArray {
                if let name = tag.name, name.lowercased().contains(query) {
                    if bestType == nil || SearchResult.MatchType.tagMatch > bestType! {
                        bestType = .tagMatch
                    }
                    score = max(score, 60)
                    if let range = name.range(of: query, options: .caseInsensitive) {
                        matchedRanges.append(MatchedRange(field: "tag", range: range, text: name))
                    }
                }
            }
        }

        // Zettel ID match (treated as title-level)
        if scope == .all || scope == .titles {
            if let zettelId = note.zettelId, zettelId.lowercased().contains(query) {
                if bestType == nil || SearchResult.MatchType.titleContains > bestType! {
                    bestType = .titleContains
                }
                score = max(score, 70)
            }
        }

        // Content match
        if scope == .all || scope == .content {
            if contentLower.contains(query) {
                if bestType == nil || SearchResult.MatchType.contentMatch > bestType! {
                    bestType = .contentMatch
                }
                // Higher score for content with more occurrences
                let occurrences = contentLower.components(separatedBy: query).count - 1
                let contentScore = min(Double(occurrences) * 10 + 20, 50)
                score = max(score, contentScore)
                if let range = note.contentPlainText.range(of: query, options: .caseInsensitive) {
                    matchedRanges.append(MatchedRange(field: "content", range: range, text: note.contentPlainText))
                }
            }
        }

        guard let matchType = bestType else { return nil }

        return SearchResult(
            id: note.objectID,
            note: note,
            relevanceScore: score,
            matchType: matchType,
            matchedRanges: matchedRanges
        )
    }

    private func noteMatches(_ note: NoteEntity, query: String, scope: SearchScope) -> Bool {
        let titleLower = note.title.lowercased()
        let contentLower = note.contentPlainText.lowercased()

        switch scope {
        case .all:
            return titleLower.contains(query)
                || contentLower.contains(query)
                || (note.zettelId?.lowercased().contains(query) ?? false)
                || note.tagsArray.contains { $0.name?.lowercased().contains(query) ?? false }
        case .titles:
            return titleLower.contains(query) || (note.zettelId?.lowercased().contains(query) ?? false)
        case .content:
            return contentLower.contains(query)
        case .tags:
            return note.tagsArray.contains { $0.name?.lowercased().contains(query) ?? false }
        }
    }
}
