import Foundation
import CoreData
import os.log

/// Takes a set of connected permanent notes and generates a draft essay/article.
/// Uses OpenRouter AI to weave atomic notes into a coherent narrative.
final class SynthesisService {

    // MARK: - Types

    struct SynthesisRequest {
        let notes: [NoteEntity]
        let style: WritingStyle
        let targetLength: LengthTarget
        let title: String?

        enum WritingStyle: String, CaseIterable, Identifiable {
            case essay = "Essay"
            case article = "Article"
            case report = "Report"
            case outline = "Outline"
            case briefing = "Briefing"

            var id: String { rawValue }

            var description: String {
                switch self {
                case .essay: "A flowing, argumentative essay with a clear thesis"
                case .article: "An informative article with sections and subheadings"
                case .report: "A structured report with executive summary and findings"
                case .outline: "A hierarchical outline with key points and sub-points"
                case .briefing: "A concise briefing document with bullet points"
                }
            }
        }

        enum LengthTarget: String, CaseIterable, Identifiable {
            case short = "Short (500 words)"
            case medium = "Medium (1500 words)"
            case long = "Long (3000+ words)"

            var id: String { rawValue }

            var wordCount: Int {
                switch self {
                case .short: 500
                case .medium: 1500
                case .long: 3000
                }
            }
        }
    }

    struct SynthesisResult {
        let title: String
        let content: String  // markdown
        let wordCount: Int
        let sourcedNotes: [UUID]
        let outline: [String]
    }

    // MARK: - Private

    private let aiClient = OpenRouterClient()
    private let logger = Logger(subsystem: "com.notenous.app", category: "SynthesisService")

    // MARK: - Synthesize

    func synthesize(request: SynthesisRequest, context: NSManagedObjectContext) async throws -> SynthesisResult {
        guard aiClient.isConfigured else {
            throw SynthesisError.aiNotConfigured
        }

        guard !request.notes.isEmpty else {
            throw SynthesisError.noNotes
        }

        // Build the prompt
        let systemPrompt = buildSystemPrompt(request: request)
        let userPrompt = buildUserPrompt(request: request, context: context)

        logger.info("Synthesizing \(request.notes.count) notes, style=\(request.style.rawValue), length=\(request.targetLength.rawValue)")

        let (content, _) = try await aiClient.sendWithFallback(system: systemPrompt, user: userPrompt)

        // Parse the result
        let title = request.title ?? extractTitle(from: content)
        let wordCount = content.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.count
        let sourcedNotes = request.notes.compactMap { $0.id }
        let outline = extractOutline(from: content)

        logger.info("Synthesis complete: \(wordCount) words, \(outline.count) sections")

        return SynthesisResult(
            title: title,
            content: content,
            wordCount: wordCount,
            sourcedNotes: sourcedNotes,
            outline: outline
        )
    }

    /// Refine an existing synthesis with feedback.
    func refine(previousResult: SynthesisResult, feedback: String, request: SynthesisRequest) async throws -> SynthesisResult {
        guard aiClient.isConfigured else {
            throw SynthesisError.aiNotConfigured
        }

        let systemPrompt = """
        You are a writing assistant refining a document based on feedback.
        The document was synthesized from atomic Zettelkasten notes.
        Apply the feedback while maintaining the original sources and citations.
        Keep using [[wikilink]] notation to cite source notes.
        Output format: pure markdown.
        """

        let userPrompt = """
        ## Current Document

        \(previousResult.content)

        ## Feedback

        \(feedback)

        ## Instructions

        Revise the document according to the feedback. Maintain the \(request.style.rawValue) style and target approximately \(request.targetLength.wordCount) words.
        """

        let (content, _) = try await aiClient.sendWithFallback(system: systemPrompt, user: userPrompt)

        let wordCount = content.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.count
        let outline = extractOutline(from: content)

        return SynthesisResult(
            title: previousResult.title,
            content: content,
            wordCount: wordCount,
            sourcedNotes: previousResult.sourcedNotes,
            outline: outline
        )
    }

    // MARK: - Prompt Building

    private func buildSystemPrompt(request: SynthesisRequest) -> String {
        """
        You are a knowledge synthesis engine for a Zettelkasten system.
        Your task is to weave atomic notes into a coherent \(request.style.rawValue.lowercased()).

        Rules:
        1. Every claim or idea MUST trace back to a source note. Cite using [[NoteTitle]] wikilinks.
        2. Respect the writing style: \(request.style.description).
        3. Target approximately \(request.targetLength.wordCount) words.
        4. Use the Folgezettel hierarchy to understand how ideas branch and relate.
        5. Pay attention to link types: "supports" means agreement, "contradicts" means tension, "extends" means building upon.
        6. Where notes contradict, present both sides fairly and analyze the tension.
        7. The context notes provide the author's reasoning — use them to understand intent.
        8. Output pure markdown. Start with the title as an H1 heading.
        9. Include section headings (H2) that organize the material logically.
        10. End with a brief conclusion that synthesizes the key insights.
        """
    }

    private func buildUserPrompt(request: SynthesisRequest, context: NSManagedObjectContext) -> String {
        var sections: [String] = []

        // Title instruction
        if let title = request.title {
            sections.append("## Document Title: \(title)")
        } else {
            sections.append("## Generate an appropriate title based on the content.")
        }

        // Notes with hierarchy
        sections.append("\n## Source Notes (in order)\n")

        let folgezettelService = FolgezettelService(context: context)

        for (index, note) in request.notes.enumerated() {
            let zettelId = note.zettelId ?? "?"
            let depth = folgezettelService.depth(of: zettelId)
            let indent = String(repeating: "  ", count: max(0, depth - 1))
            let parentId = folgezettelService.parentId(of: zettelId)

            var noteSection = "\(indent)### Note \(index + 1): [[" + note.title + "]] (ID: \(zettelId))\n"

            if let parentId = parentId {
                noteSection += "\(indent)Parent: \(parentId)\n"
            }

            noteSection += "\(indent)Type: \(note.noteType.label)\n"
            noteSection += "\n\(note.content)\n"

            if let contextNote = note.contextNote, !contextNote.isEmpty {
                noteSection += "\n\(indent)*Author's context: \(contextNote)*\n"
            }

            // Include link information
            let outgoing = note.outgoingLinksArray
            if !outgoing.isEmpty {
                noteSection += "\n\(indent)Links:\n"
                for link in outgoing {
                    let targetTitle = link.targetNote?.title ?? "Unknown"
                    noteSection += "\(indent)- \(link.linkType.label) -> [[\(targetTitle)]]\n"
                    if let linkContext = link.context, !linkContext.isEmpty {
                        noteSection += "\(indent)  (\(linkContext))\n"
                    }
                }
            }

            sections.append(noteSection)
        }

        return sections.joined(separator: "\n")
    }

    // MARK: - Parsing

    private func extractTitle(from content: String) -> String {
        let lines = content.components(separatedBy: .newlines)
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("# ") {
                return String(trimmed.dropFirst(2))
            }
        }
        return "Untitled Synthesis"
    }

    private func extractOutline(from content: String) -> [String] {
        content.components(separatedBy: .newlines)
            .filter { $0.trimmingCharacters(in: .whitespaces).hasPrefix("## ") }
            .map { $0.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "## ", with: "") }
    }
}

// MARK: - Errors

enum SynthesisError: LocalizedError {
    case aiNotConfigured
    case noNotes
    case generationFailed

    var errorDescription: String? {
        switch self {
        case .aiNotConfigured: "OpenRouter API key not configured. Add your key in Settings."
        case .noNotes: "No notes selected for synthesis."
        case .generationFailed: "Failed to generate synthesis."
        }
    }
}
