import Foundation
import os.log

struct ClassificationResult: Codable {
    let para_category: String
    let note_type: String
    let code_stage: String
    let tags: [String]
    let concepts: [String]
    let suggested_links: [SuggestedLink]
    let confidence: Double

    struct SuggestedLink: Codable {
        let zettel_id: String
        let reason: String
        let link_type: String
        let strength: Double
    }

    var paraCategory: PARACategory {
        switch para_category.lowercased() {
        case "project": .project
        case "area": .area
        case "resource": .resource
        case "archive": .archive
        default: .inbox
        }
    }

    var noteType: NoteType {
        switch note_type.lowercased() {
        case "literature": .literature
        case "permanent": .permanent
        default: .fleeting
        }
    }

    var codeStage: CODEStage {
        switch code_stage.lowercased() {
        case "organized": .organized
        case "distilled": .distilled
        case "expressed": .expressed
        default: .captured
        }
    }
}

final class ClassificationEngine {
    private let client = OpenRouterClient()
    private let logger = Logger(subsystem: "com.notenous.app", category: "Classification")

    static let systemPrompt = """
    You are a knowledge management assistant. Analyze the following note and return a JSON object with:
    1. para_category: one of "project", "area", "resource", "archive" based on PARA methodology
    2. note_type: one of "fleeting" (quick thought), "literature" (from a source), "permanent" (developed idea)
    3. code_stage: one of "captured", "organized", "distilled", "expressed"
    4. tags: array of 1-5 lowercase tags (prefer existing tags when relevant)
    5. concepts: array of 1-3 key concepts (noun phrases)
    6. suggested_links: array of 0-3 zettel IDs from the provided context that this note relates to, with reason
    7. confidence: float 0.0-1.0 representing your confidence in the classification

    Respond ONLY with valid JSON. No explanation, no markdown fences.
    """

    func classify(
        title: String,
        content: String,
        contextNote: String? = nil,
        existingTags: [String] = [],
        recentNotes: [(zettelId: String, title: String)] = []
    ) async throws -> ClassificationResult {
        let tagsContext = existingTags.isEmpty ? "None yet" : existingTags.joined(separator: ", ")
        let notesContext = recentNotes.isEmpty ? "None yet" :
            recentNotes.prefix(30).map { "\($0.zettelId): \($0.title)" }.joined(separator: "\n")

        let systemWithContext = """
        \(Self.systemPrompt)

        Existing tags: \(tagsContext)
        Recent notes for link context:
        \(notesContext)
        """

        let contextSection = if let ctx = contextNote, !ctx.isEmpty {
            "\nUser-provided context: \(ctx)"
        } else {
            ""
        }

        let userPrompt = """
        Note title: \(title)
        Note content: \(content.prefix(3000))\(contextSection)
        """

        let (responseContent, _) = try await client.sendWithFallback(
            system: systemWithContext,
            user: userPrompt
        )

        // Clean potential markdown fences
        let cleaned = responseContent
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard let data = cleaned.data(using: .utf8) else {
            throw OpenRouterError.decodingError
        }

        return try JSONDecoder().decode(ClassificationResult.self, from: data)
    }
}
