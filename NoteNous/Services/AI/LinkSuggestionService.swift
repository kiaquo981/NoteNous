import Foundation
import CoreData
import os.log

final class LinkSuggestionService {

    // MARK: - Types

    struct LinkSuggestion: Identifiable {
        let id = UUID()
        let targetNote: NoteEntity
        let reason: String
        let suggestedLinkType: LinkType
        let confidence: Float
    }

    // MARK: - Private

    private let logger = Logger(subsystem: "com.notenous.app", category: "LinkSuggestionService")
    private let client = OpenRouterClient()

    // MARK: - Local Suggestions (no API)

    func suggestLinks(for note: NoteEntity, context: NSManagedObjectContext, limit: Int = 5) -> [LinkSuggestion] {
        let keywords = extractKeywords(from: note)
        guard !keywords.isEmpty else { return [] }

        // Get all non-archived notes excluding self
        let request = NoteEntity.fetchRequest() as! NSFetchRequest<NoteEntity>
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            NSPredicate(format: "isArchived == NO"),
            NSPredicate(format: "SELF != %@", note)
        ])
        request.sortDescriptors = [NSSortDescriptor(key: "updatedAt", ascending: false)]
        request.fetchLimit = 100

        guard let candidates = try? context.fetch(request) else { return [] }

        // Get already-linked note IDs
        let linkedIds = Set(
            note.outgoingLinksArray.compactMap { $0.targetNote?.objectID } +
            note.incomingLinksArray.compactMap { $0.sourceNote?.objectID }
        )

        // Score each candidate
        var scored: [(NoteEntity, Float, String)] = []

        let noteTags = Set(note.tagsArray.compactMap { $0.name?.lowercased() })
        let noteConcepts = Set(note.conceptsArray.compactMap { $0.name?.lowercased() })

        for candidate in candidates {
            // Skip already linked
            if linkedIds.contains(candidate.objectID) { continue }

            var score: Float = 0
            var reasons: [String] = []

            // Keyword overlap (40%)
            let candidateKeywords = extractKeywords(from: candidate)
            let overlap = keywords.intersection(candidateKeywords)
            if !overlap.isEmpty {
                let keywordScore = Float(overlap.count) / Float(max(keywords.count, 1))
                score += keywordScore * 0.4
                reasons.append("Shares keywords: \(overlap.prefix(3).joined(separator: ", "))")
            }

            // Shared tags (30%)
            let candidateTags = Set(candidate.tagsArray.compactMap { $0.name?.lowercased() })
            let sharedTags = noteTags.intersection(candidateTags)
            if !sharedTags.isEmpty {
                let tagScore = Float(sharedTags.count) / Float(max(noteTags.count, 1))
                score += tagScore * 0.3
                reasons.append("Shared tags: \(sharedTags.prefix(3).joined(separator: ", "))")
            }

            // Shared concepts (bonus within tag weight)
            let candidateConcepts = Set(candidate.conceptsArray.compactMap { $0.name?.lowercased() })
            let sharedConcepts = noteConcepts.intersection(candidateConcepts)
            if !sharedConcepts.isEmpty {
                score += 0.1
                reasons.append("Shared concepts: \(sharedConcepts.prefix(2).joined(separator: ", "))")
            }

            // Folgezettel proximity (20%)
            if let noteZid = note.zettelId, let candidateZid = candidate.zettelId {
                if sharesFolgezettelPrefix(noteZid, candidateZid) {
                    score += 0.2
                    reasons.append("Folgezettel neighbor")
                }
            }

            // Temporal proximity (10%) — notes created around the same time
            if let noteDate = note.createdAt, let candidateDate = candidate.createdAt {
                let daysDiff = abs(noteDate.timeIntervalSince(candidateDate)) / 86400
                if daysDiff < 7 {
                    score += 0.1 * Float(1.0 - daysDiff / 7.0)
                }
            }

            if score > 0.1 {
                let reason = reasons.joined(separator: "; ")
                scored.append((candidate, min(score, 1.0), reason))
            }
        }

        // Sort by score descending
        scored.sort { $0.1 > $1.1 }

        return scored.prefix(limit).map { candidate, confidence, reason in
            let linkType = suggestLinkType(source: note, target: candidate)
            return LinkSuggestion(
                targetNote: candidate,
                reason: reason,
                suggestedLinkType: linkType,
                confidence: confidence
            )
        }
    }

    // MARK: - AI Suggestions (with API)

    func suggestLinksWithAI(for note: NoteEntity, context: NSManagedObjectContext) async throws -> [LinkSuggestion] {
        guard client.isConfigured else {
            throw OpenRouterError.noAPIKey
        }

        // Get candidate notes
        let request = NoteEntity.fetchRequest() as! NSFetchRequest<NoteEntity>
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            NSPredicate(format: "isArchived == NO"),
            NSPredicate(format: "SELF != %@", note)
        ])
        request.sortDescriptors = [NSSortDescriptor(key: "updatedAt", ascending: false)]
        request.fetchLimit = 20

        guard let candidates = try? context.fetch(request) else { return [] }

        // Filter out already-linked
        let linkedIds = Set(
            note.outgoingLinksArray.compactMap { $0.targetNote?.objectID } +
            note.incomingLinksArray.compactMap { $0.sourceNote?.objectID }
        )
        let filteredCandidates = candidates.filter { !linkedIds.contains($0.objectID) }
        guard !filteredCandidates.isEmpty else { return [] }

        let systemPrompt = """
        You are a Zettelkasten link suggestion assistant. Given a main note and candidate notes, suggest which candidates should be linked to the main note.
        For each suggestion, provide:
        - The candidate number
        - A brief reason for the link
        - A link type: one of "reference", "supports", "contradicts", "extends", "example"
        - A confidence score from 0.0 to 1.0

        Respond ONLY with valid JSON array. Example:
        [{"candidate": 1, "reason": "Both discuss epistemology", "link_type": "extends", "confidence": 0.8}]

        Only suggest links with confidence >= 0.5. Maximum 5 suggestions.
        """

        var userPrompt = "MAIN NOTE:\nTitle: \(note.title)\nContent: \(String(note.contentPlainText.prefix(1000)))\n\nCANDIDATES:\n"
        for (i, candidate) in filteredCandidates.enumerated() {
            userPrompt += "[\(i + 1)] \(candidate.title): \(String(candidate.contentPlainText.prefix(300)))\n"
        }

        let (response, _) = try await client.sendWithFallback(system: systemPrompt, user: userPrompt)

        // Parse response
        let cleaned = response
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard let data = cleaned.data(using: .utf8) else { return [] }

        struct AISuggestion: Codable {
            let candidate: Int
            let reason: String
            let link_type: String
            let confidence: Double
        }

        guard let aiSuggestions = try? JSONDecoder().decode([AISuggestion].self, from: data) else {
            logger.error("Failed to parse AI link suggestions")
            return []
        }

        return aiSuggestions.compactMap { suggestion -> LinkSuggestion? in
            let index = suggestion.candidate - 1
            guard index >= 0, index < filteredCandidates.count else { return nil }

            let linkType: LinkType = {
                switch suggestion.link_type.lowercased() {
                case "supports": return .supports
                case "contradicts": return .contradicts
                case "extends": return .extends
                case "example": return .example
                default: return .reference
                }
            }()

            return LinkSuggestion(
                targetNote: filteredCandidates[index],
                reason: suggestion.reason,
                suggestedLinkType: linkType,
                confidence: Float(suggestion.confidence)
            )
        }
    }

    // MARK: - Private Helpers

    private func extractKeywords(from note: NoteEntity) -> Set<String> {
        let text = "\(note.title) \(note.contentPlainText)"
        let words = text
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count > 3 }

        // Remove very common words
        let stopwords: Set<String> = [
            "this", "that", "with", "from", "they", "been", "have", "were",
            "about", "which", "when", "their", "will", "each", "make",
            "como", "para", "mais", "pode", "sobre", "entre", "quando"
        ]

        return Set(words.filter { !stopwords.contains($0) })
    }

    private func sharesFolgezettelPrefix(_ a: String, _ b: String) -> Bool {
        // Check if they share a common prefix of at least 1 character
        // e.g., "1a" and "1b" share "1", "2a1" and "2a2" share "2a"
        guard !a.isEmpty, !b.isEmpty else { return false }
        let minLen = min(a.count, b.count)
        let prefixLen = max(1, minLen - 1)
        return String(a.prefix(prefixLen)) == String(b.prefix(prefixLen)) && a != b
    }

    private func suggestLinkType(source: NoteEntity, target: NoteEntity) -> LinkType {
        // Heuristic: suggest link type based on note types
        if target.noteType == .literature {
            return .reference
        }
        if source.noteType == .permanent && target.noteType == .permanent {
            return .extends
        }
        if target.noteType == .fleeting {
            return .supports
        }
        return .reference
    }
}
