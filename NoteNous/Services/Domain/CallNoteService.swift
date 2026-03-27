import Foundation
import CoreData
import os.log

/// Manages Call Notes — live annotations during meetings/calls, AI extraction into Zettels.
/// Persists to a JSON file in Application Support/NoteNous/.
final class CallNoteService: ObservableObject {

    // MARK: - Models

    struct CallNote: Identifiable, Codable {
        let id: UUID
        var topic: String
        var participants: [String]
        var date: Date
        var duration: TimeInterval?
        var annotations: String
        var transcription: String?
        var actionItems: [ActionItem]
        var noteId: UUID?
        var isProcessed: Bool
        var processedAt: Date?

        struct ActionItem: Identifiable, Codable {
            let id: UUID
            var text: String
            var assignee: String?
            var isCompleted: Bool
            var dueDate: Date?
            var linkedNoteId: UUID?

            init(
                id: UUID = UUID(),
                text: String,
                assignee: String? = nil,
                isCompleted: Bool = false,
                dueDate: Date? = nil,
                linkedNoteId: UUID? = nil
            ) {
                self.id = id
                self.text = text
                self.assignee = assignee
                self.isCompleted = isCompleted
                self.dueDate = dueDate
                self.linkedNoteId = linkedNoteId
            }
        }

        init(
            id: UUID = UUID(),
            topic: String,
            participants: [String] = [],
            date: Date = Date(),
            duration: TimeInterval? = nil,
            annotations: String = "",
            transcription: String? = nil,
            actionItems: [ActionItem] = [],
            noteId: UUID? = nil,
            isProcessed: Bool = false,
            processedAt: Date? = nil
        ) {
            self.id = id
            self.topic = topic
            self.participants = participants
            self.date = date
            self.duration = duration
            self.annotations = annotations
            self.transcription = transcription
            self.actionItems = actionItems
            self.noteId = noteId
            self.isProcessed = isProcessed
            self.processedAt = processedAt
        }
    }

    struct ExtractionResult {
        let summary: String
        let keyDecisions: [String]
        let actionItems: [CallNote.ActionItem]
        let insights: [ExtractedInsight]
        let suggestedTags: [String]
        let followUpDate: Date?

        struct ExtractedInsight {
            let title: String
            let content: String
            let noteType: NoteType
            let suggestedTags: [String]
        }
    }

    // MARK: - State

    @Published private(set) var callNotes: [CallNote] = []

    private let logger = Logger(subsystem: "com.notenous.app", category: "CallNoteService")
    private let fileURL: URL
    private let client = OpenRouterClient()

    init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("NoteNous", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        self.fileURL = dir.appendingPathComponent("call-notes.json")

        loadFromDisk()
    }

    // MARK: - CRUD

    @discardableResult
    func createCallNote(topic: String, participants: [String], date: Date) -> CallNote {
        let callNote = CallNote(topic: topic, participants: participants, date: date)
        callNotes.append(callNote)
        saveToDisk()
        logger.info("Created call note: \(topic)")
        return callNote
    }

    func updateCallNote(_ callNote: CallNote) {
        guard let index = callNotes.firstIndex(where: { $0.id == callNote.id }) else {
            logger.warning("Call note not found for update: \(callNote.id.uuidString)")
            return
        }
        callNotes[index] = callNote
        saveToDisk()
        logger.info("Updated call note: \(callNote.topic)")
    }

    func deleteCallNote(id: UUID) {
        callNotes.removeAll { $0.id == id }
        saveToDisk()
        logger.info("Deleted call note: \(id.uuidString)")
    }

    func allCallNotes() -> [CallNote] {
        callNotes.sorted { $0.date > $1.date }
    }

    func pendingCallNotes() -> [CallNote] {
        callNotes.filter { !$0.isProcessed }.sorted { $0.date > $1.date }
    }

    func callNote(for id: UUID) -> CallNote? {
        callNotes.first { $0.id == id }
    }

    // MARK: - Transcription

    func attachTranscription(_ text: String, to callNoteId: UUID) {
        guard let index = callNotes.firstIndex(where: { $0.id == callNoteId }) else { return }
        callNotes[index].transcription = text
        saveToDisk()
        logger.info("Attached transcription to call note: \(callNoteId.uuidString)")
    }

    // MARK: - AI Extraction

    static let extractionSystemPrompt = """
    You are analyzing a meeting/call. You have:
    1. The user's live annotations (notes they took during the call)
    2. The call transcription (if available)

    Extract:
    1. SUMMARY: 2-3 sentence executive summary
    2. KEY DECISIONS: Bullet list of decisions made
    3. ACTION ITEMS: Tasks with assignee if mentioned
    4. INSIGHTS: Atomic knowledge insights (each one idea, title as proposition):
       - title: "Proposition-style title stating the insight"
       - content: "The insight explained in 40-200 words"
       - type: "permanent" or "literature"
       - tags: ["relevant", "tags"]
    5. SUGGESTED TAGS: Tags for the overall call note
    6. FOLLOW_UP_DATE: Suggested follow-up date if applicable (ISO 8601 format or null)

    Return ONLY valid JSON with this exact structure:
    {
      "summary": "...",
      "key_decisions": ["..."],
      "action_items": [{"text": "...", "assignee": "...", "due_date": "..."}],
      "insights": [{"title": "...", "content": "...", "type": "permanent", "tags": ["..."]}],
      "suggested_tags": ["..."],
      "follow_up_date": null
    }
    """

    func extractFromCall(_ callNote: CallNote, context: NSManagedObjectContext) async throws -> ExtractionResult {
        var userPrompt = "TOPIC: \(callNote.topic)\n"
        userPrompt += "DATE: \(callNote.date.formatted())\n"
        if !callNote.participants.isEmpty {
            userPrompt += "PARTICIPANTS: \(callNote.participants.joined(separator: ", "))\n"
        }
        userPrompt += "\nANNOTATIONS:\n\(callNote.annotations)\n"
        if let transcription = callNote.transcription, !transcription.isEmpty {
            userPrompt += "\nTRANSCRIPTION:\n\(String(transcription.prefix(6000)))\n"
        }

        let (responseContent, _) = try await client.sendWithFallback(
            system: Self.extractionSystemPrompt,
            user: userPrompt
        )

        return try parseExtractionResponse(responseContent)
    }

    private func parseExtractionResponse(_ response: String) throws -> ExtractionResult {
        let cleaned = response
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard let data = cleaned.data(using: .utf8) else {
            throw OpenRouterError.decodingError
        }

        let raw = try JSONDecoder().decode(RawExtractionResponse.self, from: data)

        let actionItems = raw.action_items.map { item in
            CallNote.ActionItem(
                text: item.text,
                assignee: item.assignee,
                isCompleted: false,
                dueDate: item.due_date.flatMap { parseDateFuzzy($0) }
            )
        }

        let insights = raw.insights.map { insight in
            ExtractionResult.ExtractedInsight(
                title: insight.title,
                content: insight.content,
                noteType: insight.type == "literature" ? .literature : .permanent,
                suggestedTags: insight.tags
            )
        }

        let followUpDate = raw.follow_up_date.flatMap { parseDateFuzzy($0) }

        return ExtractionResult(
            summary: raw.summary,
            keyDecisions: raw.key_decisions,
            actionItems: actionItems,
            insights: insights,
            suggestedTags: raw.suggested_tags,
            followUpDate: followUpDate
        )
    }

    private func parseDateFuzzy(_ string: String) -> Date? {
        let iso = ISO8601DateFormatter()
        if let d = iso.date(from: string) { return d }

        let formatter = DateFormatter()
        for fmt in ["yyyy-MM-dd", "MM/dd/yyyy", "dd/MM/yyyy"] {
            formatter.dateFormat = fmt
            if let d = formatter.date(from: string) { return d }
        }
        return nil
    }

    // MARK: - Apply Extraction

    @discardableResult
    func applyExtraction(
        _ result: ExtractionResult,
        for callNote: CallNote,
        context: NSManagedObjectContext
    ) -> [NoteEntity] {
        let noteService = NoteService(context: context)
        let tagService = TagService(context: context)
        let linkService = LinkService(context: context)

        var createdNotes: [NoteEntity] = []
        let topicSlug = callNote.topic
            .lowercased()
            .replacingOccurrences(of: " ", with: "-")
            .replacingOccurrences(of: #"[^a-z0-9\-]"#, with: "", options: .regularExpression)

        // Create a summary note
        let summaryContent = buildSummaryContent(result: result, callNote: callNote)
        let summaryNote = noteService.createNote(
            title: "Call: \(callNote.topic)",
            content: summaryContent,
            paraCategory: .resource
        )
        summaryNote.noteType = .literature
        summaryNote.sourceTitle = "Call with \(callNote.participants.joined(separator: ", "))"

        // Tag the summary note
        let callExtractTag = tagService.findOrCreate(name: "call-extract")
        tagService.addTag(callExtractTag, to: summaryNote)
        let topicTag = tagService.findOrCreate(name: topicSlug)
        tagService.addTag(topicTag, to: summaryNote)
        for tagName in result.suggestedTags {
            let tag = tagService.findOrCreate(name: tagName)
            tagService.addTag(tag, to: summaryNote)
        }
        createdNotes.append(summaryNote)

        // Create insight notes
        for insight in result.insights {
            let insightNote = noteService.createNote(
                title: insight.title,
                content: insight.content,
                paraCategory: .resource
            )
            insightNote.noteType = insight.noteType

            let extractTag = tagService.findOrCreate(name: "call-extract")
            tagService.addTag(extractTag, to: insightNote)
            let slugTag = tagService.findOrCreate(name: topicSlug)
            tagService.addTag(slugTag, to: insightNote)
            for tagName in insight.suggestedTags {
                let tag = tagService.findOrCreate(name: tagName)
                tagService.addTag(tag, to: insightNote)
            }

            // Link insight to summary
            linkService.createLink(
                from: summaryNote,
                to: insightNote,
                type: .reference,
                context: "Extracted from call: \(callNote.topic)",
                strength: 0.8,
                isAISuggested: true
            )
            createdNotes.append(insightNote)
        }

        // Cross-link all insights
        for i in 0..<createdNotes.count {
            for j in (i + 1)..<createdNotes.count {
                if i > 0 && j > 0 { // skip summary-to-insight (already linked)
                    linkService.createLink(
                        from: createdNotes[i],
                        to: createdNotes[j],
                        type: .reference,
                        context: "Same call context: \(callNote.topic)",
                        strength: 0.6,
                        isAISuggested: true
                    )
                }
            }
        }

        // Mark call note as processed
        var updated = callNote
        updated.isProcessed = true
        updated.processedAt = Date()
        updated.actionItems = result.actionItems
        updated.noteId = summaryNote.id
        updateCallNote(updated)

        logger.info("Applied extraction: \(createdNotes.count) notes created for call '\(callNote.topic)'")
        return createdNotes
    }

    private func buildSummaryContent(result: ExtractionResult, callNote: CallNote) -> String {
        var lines: [String] = []
        lines.append("## Summary")
        lines.append(result.summary)
        lines.append("")

        if !result.keyDecisions.isEmpty {
            lines.append("## Key Decisions")
            for decision in result.keyDecisions {
                lines.append("- \(decision)")
            }
            lines.append("")
        }

        if !result.actionItems.isEmpty {
            lines.append("## Action Items")
            for item in result.actionItems {
                var line = "- [ ] \(item.text)"
                if let assignee = item.assignee { line += " (@\(assignee))" }
                if let due = item.dueDate { line += " — due: \(due.formatted(date: .abbreviated, time: .omitted))" }
                lines.append(line)
            }
            lines.append("")
        }

        if let followUp = result.followUpDate {
            lines.append("## Follow-up")
            lines.append("Suggested: \(followUp.formatted(date: .abbreviated, time: .omitted))")
            lines.append("")
        }

        lines.append("---")
        lines.append("*Extracted from call on \(callNote.date.formatted()) with \(callNote.participants.joined(separator: ", "))*")

        return lines.joined(separator: "\n")
    }

    // MARK: - Persistence

    private func saveToDisk() {
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(callNotes)
            try data.write(to: fileURL, options: .atomicWrite)
        } catch {
            logger.error("Failed to save call notes: \(error.localizedDescription)")
        }
    }

    private func loadFromDisk() {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            logger.info("No call notes file found, starting fresh")
            return
        }
        do {
            let data = try Data(contentsOf: fileURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            callNotes = try decoder.decode([CallNote].self, from: data)
            logger.info("Loaded \(self.callNotes.count) call notes from disk")
        } catch {
            logger.error("Failed to load call notes: \(error.localizedDescription)")
            callNotes = []
        }
    }
}

// MARK: - Raw JSON Response Model

private struct RawExtractionResponse: Codable {
    let summary: String
    let key_decisions: [String]
    let action_items: [RawActionItem]
    let insights: [RawInsight]
    let suggested_tags: [String]
    let follow_up_date: String?

    struct RawActionItem: Codable {
        let text: String
        let assignee: String?
        let due_date: String?
    }

    struct RawInsight: Codable {
        let title: String
        let content: String
        let type: String
        let tags: [String]
    }
}
