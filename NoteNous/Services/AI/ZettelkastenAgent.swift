import Foundation
import CoreData
import os.log

// MARK: - Agent Phase

enum AgentPhase: String, CaseIterable {
    case idle = "Idle"
    case analyzing = "Analyzing notes..."
    case classifying = "Classifying..."
    case connecting = "Finding connections..."
    case indexing = "Updating index..."
    case synthesizing = "Synthesizing..."
    case complete = "Review ready"
}

// MARK: - Agent Action

struct AgentAction: Identifiable {
    let id = UUID()
    let type: ActionType
    let description: String
    let reasoning: String
    var status: ActionStatus = .pending
    let affectedNoteIds: [UUID]
    let payload: ActionPayload

    enum ActionType: String, CaseIterable {
        case classify = "Classify"
        case promote = "Promote"
        case placeFolgezettel = "Place in Tree"
        case createLink = "Create Link"
        case updateIndex = "Update Index"
        case splitNote = "Split Note"
        case mergeNotes = "Merge Notes"
        case createStructureNote = "Create Structure Note"

        var icon: String {
            switch self {
            case .classify: "tag.fill"
            case .promote: "arrow.up.circle.fill"
            case .placeFolgezettel: "arrow.triangle.branch"
            case .createLink: "link"
            case .updateIndex: "list.bullet.rectangle"
            case .splitNote: "scissors"
            case .mergeNotes: "arrow.triangle.merge"
            case .createStructureNote: "folder.fill.badge.plus"
            }
        }

        var color: String {
            switch self {
            case .classify: "ambient"
            case .promote: "oracle"
            case .placeFolgezettel: "verdit"
            case .createLink: "oracle"
            case .updateIndex: "ambient"
            case .splitNote: "signal"
            case .mergeNotes: "ambient"
            case .createStructureNote: "verdit"
            }
        }
    }

    enum ActionStatus: String {
        case pending = "Pending"
        case approved = "Approved"
        case rejected = "Rejected"
        case applied = "Applied"
    }

    enum ActionPayload {
        case classify(para: PARACategory, codeStage: CODEStage, noteType: NoteType, tags: [String])
        case promote(fromType: NoteType, toType: NoteType)
        case placeFolgezettel(suggestedId: String, parentZettelId: String?, parentTitle: String?)
        case createLink(sourceId: UUID, targetId: UUID, linkType: LinkType, reason: String)
        case updateIndex(keyword: String, noteId: UUID)
        case splitNote(noteId: UUID, splitPoints: [String])
        case mergeNotes(sourceId: UUID, targetId: UUID)
        case createStructureNote(title: String, linkedNoteIds: [UUID], content: String)
    }
}

// MARK: - AI Batch Response

private struct BatchAnalysisResponse: Codable {
    let notes: [NoteAnalysis]

    struct NoteAnalysis: Codable {
        let note_index: Int
        let para_category: String
        let note_type: String
        let code_stage: String
        let tags: [String]
        let concepts: [String]
        let should_promote: Bool
        let promote_reason: String?
        let suggested_parent_zettel_id: String?
        let suggested_parent_title: String?
        let placement_reason: String?
        let suggested_links: [SuggestedLink]
        let index_keywords: [String]
        let should_split: Bool
        let split_reason: String?
        let split_segments: [String]?
    }

    struct SuggestedLink: Codable {
        let target_zettel_id: String
        let link_type: String
        let reason: String
    }
}

private struct MergeCandidate: Codable {
    let note_a_index: Int
    let note_b_index: Int
    let reason: String
}

private struct StructureCandidate: Codable {
    let title: String
    let note_indices: [Int]
    let content_outline: String
}

private struct SynthesisResponse: Codable {
    let merges: [MergeCandidate]
    let structure_notes: [StructureCandidate]
}

// MARK: - Zettelkasten Agent

@MainActor
final class ZettelkastenAgent: ObservableObject {
    @Published var phase: AgentPhase = .idle
    @Published var actions: [AgentAction] = []
    @Published var progress: Double = 0
    @Published var isRunning: Bool = false
    @Published var log: [LogEntry] = []

    struct LogEntry: Identifiable {
        let id = UUID()
        let timestamp: Date
        let message: String
        let severity: Severity

        enum Severity: String {
            case info, action, warning, error
        }
    }

    private let client = OpenRouterClient()
    private let classificationEngine = ClassificationEngine()
    private let logger = Logger(subsystem: "com.notenous.app", category: "ZettelkastenAgent")

    var pendingCount: Int { actions.filter { $0.status == .pending }.count }
    var approvedCount: Int { actions.filter { $0.status == .approved }.count }
    var appliedCount: Int { actions.filter { $0.status == .applied }.count }

    // MARK: - Process Fleeting Notes

    func processFleetingNotes(context: NSManagedObjectContext) async {
        let noteService = NoteService(context: context)
        let fleetingNotes = noteService.fetchNotes(noteType: .fleeting, limit: 50)
        guard !fleetingNotes.isEmpty else {
            appendLog("No fleeting notes to process.", severity: .info)
            return
        }
        await processNotes(fleetingNotes, context: context)
    }

    // MARK: - Process Specific Notes

    func processNotes(_ notes: [NoteEntity], context: NSManagedObjectContext) async {
        guard !isRunning else {
            appendLog("Agent is already running.", severity: .warning)
            return
        }
        guard client.isConfigured else {
            appendLog("OpenRouter API key not configured. Set it in .env or preferences.", severity: .error)
            return
        }

        isRunning = true
        actions = []
        log = []
        progress = 0

        appendLog("Starting Zettelkasten Agent on \(notes.count) notes.", severity: .action)

        // Phase 1: Analyzing
        phase = .analyzing
        progress = 0.05
        appendLog("Gathering context from existing Zettelkasten...", severity: .info)

        let noteService = NoteService(context: context)
        let tagService = TagService(context: context)
        let indexService = IndexService()
        let folgezettelService = FolgezettelService(context: context)
        let atomicService = AtomicNoteService(context: context)

        let existingTags = tagService.topTags(limit: 50).compactMap { $0.name }
        let recentNotes = noteService.fetchNotes(limit: 50).map { (zettelId: $0.zettelId ?? "?", title: $0.title) }
        let existingKeywords = indexService.allKeywordsSorted().map { $0.keyword }

        progress = 0.1

        // Phase 2: Classify via AI batch
        phase = .classifying
        appendLog("Sending batch to AI for classification...", severity: .action)

        let batchResult = await classifyBatch(
            notes: notes,
            existingTags: existingTags,
            recentNotes: recentNotes,
            existingKeywords: existingKeywords
        )

        progress = 0.4

        guard let batchAnalysis = batchResult else {
            appendLog("AI classification failed. Check API key and network.", severity: .error)
            phase = .idle
            isRunning = false
            return
        }

        // Build actions from batch analysis
        phase = .connecting
        appendLog("Building action plan from AI analysis...", severity: .info)

        for analysis in batchAnalysis.notes {
            guard analysis.note_index >= 0, analysis.note_index < notes.count else { continue }
            let note = notes[analysis.note_index]
            guard let noteId = note.id else { continue }

            // Classification action
            let para = parsePARA(analysis.para_category)
            let codeStage = parseCODE(analysis.code_stage)
            let noteType = parseNoteType(analysis.note_type)

            actions.append(AgentAction(
                type: .classify,
                description: "Classify '\(note.title.prefix(40))' as \(para.label) / \(noteType.label) / \(codeStage.label)",
                reasoning: "Tags: \(analysis.tags.joined(separator: ", ")). Concepts: \(analysis.concepts.joined(separator: ", ")).",
                affectedNoteIds: [noteId],
                payload: .classify(para: para, codeStage: codeStage, noteType: noteType, tags: analysis.tags)
            ))

            // Promotion action
            if analysis.should_promote && note.noteType == .fleeting {
                let targetType: NoteType = noteType == .fleeting ? .permanent : noteType
                actions.append(AgentAction(
                    type: .promote,
                    description: "Promote '\(note.title.prefix(40))' from Fleeting to \(targetType.label)",
                    reasoning: analysis.promote_reason ?? "Content is developed enough for promotion.",
                    affectedNoteIds: [noteId],
                    payload: .promote(fromType: .fleeting, toType: targetType)
                ))
            }

            // Folgezettel placement
            if let parentZettelId = analysis.suggested_parent_zettel_id, !parentZettelId.isEmpty {
                let branchId = folgezettelService.generateBranch(from: parentZettelId)
                actions.append(AgentAction(
                    type: .placeFolgezettel,
                    description: "Place '\(note.title.prefix(30))' as \(branchId) under \(parentZettelId)",
                    reasoning: analysis.placement_reason ?? "Content relates to parent note.",
                    affectedNoteIds: [noteId],
                    payload: .placeFolgezettel(
                        suggestedId: branchId,
                        parentZettelId: parentZettelId,
                        parentTitle: analysis.suggested_parent_title
                    )
                ))
            }

            // Link creation
            for link in analysis.suggested_links {
                let targetNote = noteService.findByZettelId(link.target_zettel_id)
                if let targetNote = targetNote, let targetId = targetNote.id {
                    let linkType = parseLinkType(link.link_type)
                    actions.append(AgentAction(
                        type: .createLink,
                        description: "Link '\(note.title.prefix(25))' -> '\(targetNote.title.prefix(25))' (\(linkType.label))",
                        reasoning: link.reason,
                        affectedNoteIds: [noteId, targetId],
                        payload: .createLink(sourceId: noteId, targetId: targetId, linkType: linkType, reason: link.reason)
                    ))
                }
            }

            // Index updates
            for keyword in analysis.index_keywords {
                let existingEntry = indexService.entry(for: keyword)
                if existingEntry == nil || (existingEntry?.entryNoteIds.count ?? 0) < IndexService.maxEntryNotesPerKeyword {
                    actions.append(AgentAction(
                        type: .updateIndex,
                        description: "Add '\(note.title.prefix(30))' as entry point for '\(keyword)'",
                        reasoning: "This note is a good entry point for the concept '\(keyword)'.",
                        affectedNoteIds: [noteId],
                        payload: .updateIndex(keyword: keyword, noteId: noteId)
                    ))
                }
            }

            // Split detection
            if analysis.should_split, let segments = analysis.split_segments, segments.count > 1 {
                actions.append(AgentAction(
                    type: .splitNote,
                    description: "Split '\(note.title.prefix(30))' into \(segments.count) atomic notes",
                    reasoning: analysis.split_reason ?? "Note contains multiple ideas.",
                    affectedNoteIds: [noteId],
                    payload: .splitNote(noteId: noteId, splitPoints: segments)
                ))
            }

            // Also check atomicity via local service
            let report = atomicService.analyze(note: note)
            if !report.isAtomic && !analysis.should_split {
                let suggestions = atomicService.splitSuggestions(for: note)
                if !suggestions.isEmpty {
                    actions.append(AgentAction(
                        type: .splitNote,
                        description: "Atomicity issue in '\(note.title.prefix(30))'",
                        reasoning: suggestions.joined(separator: " "),
                        affectedNoteIds: [noteId],
                        payload: .splitNote(noteId: noteId, splitPoints: [])
                    ))
                }
            }
        }

        progress = 0.7

        // Phase 3: Synthesis — merges and structure notes
        phase = .synthesizing
        appendLog("Analyzing for merges and structure note opportunities...", severity: .action)

        let synthesisResult = await synthesizeBatch(notes: notes, analyses: batchAnalysis.notes)
        if let synthesis = synthesisResult {
            for merge in synthesis.merges {
                guard merge.note_a_index >= 0, merge.note_a_index < notes.count,
                      merge.note_b_index >= 0, merge.note_b_index < notes.count else { continue }
                let noteA = notes[merge.note_a_index]
                let noteB = notes[merge.note_b_index]
                guard let idA = noteA.id, let idB = noteB.id else { continue }

                actions.append(AgentAction(
                    type: .mergeNotes,
                    description: "Merge '\(noteA.title.prefix(25))' with '\(noteB.title.prefix(25))'",
                    reasoning: merge.reason,
                    affectedNoteIds: [idA, idB],
                    payload: .mergeNotes(sourceId: idA, targetId: idB)
                ))
            }

            for structure in synthesis.structure_notes {
                let linkedIds = structure.note_indices.compactMap { idx -> UUID? in
                    guard idx >= 0, idx < notes.count else { return nil }
                    return notes[idx].id
                }
                guard !linkedIds.isEmpty else { continue }

                actions.append(AgentAction(
                    type: .createStructureNote,
                    description: "Create structure note: '\(structure.title.prefix(40))'",
                    reasoning: "Cluster of \(linkedIds.count) related notes detected.",
                    affectedNoteIds: linkedIds,
                    payload: .createStructureNote(
                        title: structure.title,
                        linkedNoteIds: linkedIds,
                        content: structure.content_outline
                    )
                ))
            }
        }

        progress = 0.9

        // Phase 4: Indexing pass
        phase = .indexing
        appendLog("Finalizing index suggestions...", severity: .info)

        progress = 1.0
        phase = .complete
        appendLog("Agent complete. \(actions.count) actions proposed for review.", severity: .action)
        isRunning = false
    }

    // MARK: - Approve / Reject

    func approve(_ actionId: UUID) {
        if let index = actions.firstIndex(where: { $0.id == actionId }) {
            actions[index].status = .approved
        }
    }

    func reject(_ actionId: UUID) {
        if let index = actions.firstIndex(where: { $0.id == actionId }) {
            actions[index].status = .rejected
        }
    }

    func approveAll() {
        for i in actions.indices where actions[i].status == .pending {
            actions[i].status = .approved
        }
    }

    func rejectAll() {
        for i in actions.indices where actions[i].status == .pending {
            actions[i].status = .rejected
        }
    }

    func approveByType(_ type: AgentAction.ActionType) {
        for i in actions.indices where actions[i].type == type && actions[i].status == .pending {
            actions[i].status = .approved
        }
    }

    // MARK: - Apply Actions

    func applyAction(_ action: AgentAction, context: NSManagedObjectContext) {
        guard let index = actions.firstIndex(where: { $0.id == action.id }),
              actions[index].status == .approved else { return }

        let noteService = NoteService(context: context)
        let tagService = TagService(context: context)
        let linkService = LinkService(context: context)
        let indexService = IndexService()

        switch action.payload {
        case .classify(let para, let codeStage, let noteType, let tags):
            guard let noteId = action.affectedNoteIds.first,
                  let note = fetchNote(id: noteId, context: context) else { return }
            note.paraCategory = para
            note.codeStage = codeStage
            note.noteType = noteType
            note.aiClassified = true
            note.aiConfidence = 0.8
            note.updatedAt = Date()
            for tagName in tags {
                let tag = tagService.findOrCreate(name: tagName)
                tagService.addTag(tag, to: note)
            }
            saveContext(context)

        case .promote(_, let toType):
            guard let noteId = action.affectedNoteIds.first,
                  let note = fetchNote(id: noteId, context: context) else { return }
            note.noteType = toType
            note.codeStage = .organized
            note.updatedAt = Date()
            saveContext(context)

        case .placeFolgezettel(let suggestedId, _, _):
            guard let noteId = action.affectedNoteIds.first,
                  let note = fetchNote(id: noteId, context: context) else { return }
            note.zettelId = suggestedId
            note.updatedAt = Date()
            saveContext(context)

        case .createLink(let sourceId, let targetId, let linkType, let reason):
            guard let source = fetchNote(id: sourceId, context: context),
                  let target = fetchNote(id: targetId, context: context) else { return }
            linkService.createLink(from: source, to: target, type: linkType, context: reason, strength: 0.7, isAISuggested: true)

        case .updateIndex(let keyword, let noteId):
            indexService.addEntry(keyword: keyword, noteId: noteId)

        case .splitNote:
            appendLog("Split requires manual editing. Note flagged for review.", severity: .warning)

        case .mergeNotes:
            appendLog("Merge requires manual editing. Notes flagged for review.", severity: .warning)

        case .createStructureNote(let title, let linkedNoteIds, let content):
            let structureNote = noteService.createNote(title: title, content: content)
            structureNote.noteType = .structure
            structureNote.codeStage = .organized
            structureNote.updatedAt = Date()
            for linkedId in linkedNoteIds {
                if let linkedNote = fetchNote(id: linkedId, context: context) {
                    linkService.createLink(from: structureNote, to: linkedNote, type: .reference, context: "Structure note link", strength: 0.6, isAISuggested: true)
                }
            }
            saveContext(context)
        }

        actions[index].status = .applied
        appendLog("Applied: \(action.description)", severity: .action)
    }

    func applyAllApproved(context: NSManagedObjectContext) {
        let approved = actions.filter { $0.status == .approved }
        for action in approved {
            applyAction(action, context: context)
        }
        appendLog("Applied \(approved.count) actions.", severity: .action)
    }

    // MARK: - AI Batch Classification

    private func classifyBatch(
        notes: [NoteEntity],
        existingTags: [String],
        recentNotes: [(zettelId: String, title: String)],
        existingKeywords: [String]
    ) async -> BatchAnalysisResponse? {
        let notesPayload = notes.enumerated().map { (i, note) in
            """
            [Note \(i)] Title: \(note.title)
            ZettelID: \(note.zettelId ?? "none")
            Type: \(note.noteType.label)
            Content: \(note.contentPlainText.prefix(500))
            """
        }.joined(separator: "\n---\n")

        let recentContext = recentNotes.prefix(30).map { "\($0.zettelId): \($0.title)" }.joined(separator: "\n")
        let tagsContext = existingTags.prefix(30).joined(separator: ", ")
        let keywordsContext = existingKeywords.prefix(30).joined(separator: ", ")

        let systemPrompt = """
        You are an expert Zettelkasten assistant analyzing a batch of notes. For each note, determine:
        1. para_category: "inbox"|"project"|"area"|"resource"|"archive"
        2. note_type: "fleeting"|"literature"|"permanent"
        3. code_stage: "captured"|"organized"|"distilled"|"expressed"
        4. tags: 1-5 lowercase tags (prefer existing: \(tagsContext))
        5. concepts: 1-3 key concept noun phrases
        6. should_promote: true if fleeting note has enough substance for permanent
        7. promote_reason: why promote (if should_promote)
        8. suggested_parent_zettel_id: best existing zettel ID to branch from (or null)
        9. suggested_parent_title: title of that parent (or null)
        10. placement_reason: why this parent (if suggested)
        11. suggested_links: [{target_zettel_id, link_type ("reference"|"supports"|"contradicts"|"extends"|"example"), reason}]
        12. index_keywords: 0-2 keywords for the sparse keyword index
        13. should_split: true if note contains multiple distinct ideas
        14. split_reason: why split
        15. split_segments: suggested segment titles if splitting

        Existing keywords in index: \(keywordsContext)
        Existing notes for linking context:
        \(recentContext)

        Respond ONLY with valid JSON: {"notes": [{note_index: 0, ...}, ...]}
        No markdown fences, no explanation.
        """

        do {
            let (content, tokens) = try await client.sendWithFallback(system: systemPrompt, user: notesPayload)
            appendLog("AI responded with \(tokens) tokens.", severity: .info)

            let cleaned = content
                .replacingOccurrences(of: "```json", with: "")
                .replacingOccurrences(of: "```", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)

            guard let data = cleaned.data(using: .utf8) else {
                appendLog("Failed to parse AI response as UTF-8.", severity: .error)
                return nil
            }

            let decoder = JSONDecoder()
            return try decoder.decode(BatchAnalysisResponse.self, from: data)
        } catch {
            appendLog("AI batch classification failed: \(error.localizedDescription)", severity: .error)
            logger.error("Batch classification error: \(error.localizedDescription)")
            return nil
        }
    }

    // MARK: - AI Synthesis (Merges + Structure Notes)

    private func synthesizeBatch(notes: [NoteEntity], analyses: [BatchAnalysisResponse.NoteAnalysis]) async -> SynthesisResponse? {
        guard notes.count >= 3 else { return nil }

        let noteSummaries = notes.enumerated().map { (i, note) in
            let tags = analyses.first(where: { $0.note_index == i })?.tags.joined(separator: ", ") ?? ""
            return "[Note \(i)] '\(note.title)' tags: \(tags)"
        }.joined(separator: "\n")

        let systemPrompt = """
        You are a Zettelkasten synthesis assistant. Given a set of notes with their tags and concepts:
        1. Identify pairs that should be MERGED (very similar/overlapping content)
        2. Identify clusters of 3+ notes that warrant a STRUCTURE NOTE (hub note linking related ideas)

        Respond ONLY with valid JSON:
        {"merges": [{"note_a_index": 0, "note_b_index": 1, "reason": "..."}], "structure_notes": [{"title": "...", "note_indices": [0,2,4], "content_outline": "..."}]}
        No markdown fences.
        """

        do {
            let (content, _) = try await client.sendWithFallback(system: systemPrompt, user: noteSummaries)

            let cleaned = content
                .replacingOccurrences(of: "```json", with: "")
                .replacingOccurrences(of: "```", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)

            guard let data = cleaned.data(using: .utf8) else { return nil }
            return try JSONDecoder().decode(SynthesisResponse.self, from: data)
        } catch {
            appendLog("Synthesis analysis failed: \(error.localizedDescription)", severity: .warning)
            return nil
        }
    }

    // MARK: - Helpers

    private func fetchNote(id: UUID, context: NSManagedObjectContext) -> NoteEntity? {
        let request = NoteEntity.fetchRequest() as! NSFetchRequest<NoteEntity>
        request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        request.fetchLimit = 1
        return try? context.fetch(request).first
    }

    private func saveContext(_ context: NSManagedObjectContext) {
        guard context.hasChanges else { return }
        try? context.save()
    }

    private func appendLog(_ message: String, severity: LogEntry.Severity) {
        log.append(LogEntry(timestamp: Date(), message: message, severity: severity))
        logger.log(level: severity == .error ? .error : .info, "\(message)")
    }

    private func parsePARA(_ raw: String) -> PARACategory {
        switch raw.lowercased() {
        case "project": return .project
        case "area": return .area
        case "resource": return .resource
        case "archive": return .archive
        default: return .inbox
        }
    }

    private func parseCODE(_ raw: String) -> CODEStage {
        switch raw.lowercased() {
        case "organized": return .organized
        case "distilled": return .distilled
        case "expressed": return .expressed
        default: return .captured
        }
    }

    private func parseNoteType(_ raw: String) -> NoteType {
        switch raw.lowercased() {
        case "literature": return .literature
        case "permanent": return .permanent
        case "structure": return .structure
        default: return .fleeting
        }
    }

    private func parseLinkType(_ raw: String) -> LinkType {
        switch raw.lowercased() {
        case "supports": return .supports
        case "contradicts": return .contradicts
        case "extends": return .extends
        case "example": return .example
        default: return .reference
        }
    }
}
