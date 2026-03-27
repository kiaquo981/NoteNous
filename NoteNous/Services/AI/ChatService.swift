import Foundation
import CoreData
import os.log

@MainActor
final class ChatService: ObservableObject {

    // MARK: - Types

    struct AIChatMessage: Identifiable {
        let id = UUID()
        let role: MessageRole
        let content: String
        let timestamp: Date
        var referencedNotes: [NoteEntity]

        enum MessageRole {
            case user, assistant, system
        }
    }

    // MARK: - Published State

    @Published var messages: [AIChatMessage] = []
    @Published var isStreaming: Bool = false
    @Published var statusMessage: String?

    // MARK: - Private

    private let client = OpenRouterClient()
    private let logger = Logger(subsystem: "com.notenous.app", category: "ChatService")

    // English stopwords for keyword extraction
    private static let stopwords: Set<String> = [
        "a", "an", "the", "is", "are", "was", "were", "be", "been", "being",
        "have", "has", "had", "do", "does", "did", "will", "would", "could",
        "should", "may", "might", "can", "shall", "about", "above", "after",
        "again", "all", "also", "am", "and", "any", "as", "at", "because",
        "before", "between", "both", "but", "by", "came", "come", "could",
        "each", "for", "from", "get", "got", "had", "he", "her", "here",
        "him", "his", "how", "i", "if", "in", "into", "it", "its", "just",
        "like", "make", "many", "me", "more", "most", "much", "my", "never",
        "no", "nor", "not", "now", "of", "on", "only", "or", "other", "our",
        "out", "over", "re", "said", "same", "she", "so", "some", "still",
        "such", "take", "than", "that", "their", "them", "then", "there",
        "these", "they", "this", "those", "through", "to", "too", "under",
        "up", "very", "want", "what", "when", "where", "which", "while",
        "who", "whom", "why", "with", "without", "you", "your",
        // Portuguese stopwords
        "de", "da", "do", "das", "dos", "em", "no", "na", "nos", "nas",
        "um", "uma", "uns", "umas", "o", "os", "as", "e", "ou", "que",
        "se", "com", "para", "por", "mais", "mas", "como", "qual", "quais",
        "quando", "onde", "quem", "esse", "essa", "este", "esta", "isso",
        "isto", "ele", "ela", "eles", "elas", "nos", "eu", "tu", "voce",
        "sobre", "entre", "ate", "sem", "muito", "ja", "ainda", "bem",
        "ter", "ser", "estar", "ir", "fazer", "poder", "dizer", "dar"
    ]

    // MARK: - Public API

    func ask(question: String, context managedContext: NSManagedObjectContext, currentNote: NoteEntity? = nil) async {
        guard !question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        guard client.isConfigured else {
            let errorMsg = AIChatMessage(
                role: .assistant,
                content: "OpenRouter API key is not configured. Please add your key to the .env file.",
                timestamp: Date(),
                referencedNotes: []
            )
            messages.append(errorMsg)
            return
        }

        // Add user message
        let userMsg = AIChatMessage(role: .user, content: question, timestamp: Date(), referencedNotes: [])
        messages.append(userMsg)

        isStreaming = true
        statusMessage = "Searching notes..."

        // RAG: Retrieve relevant notes
        var relevantNotes = retrieveRelevantNotes(query: question, context: managedContext, limit: 10)

        // Always include current note if provided and not already in results
        if let currentNote = currentNote,
           !relevantNotes.contains(where: { $0.objectID == currentNote.objectID }) {
            relevantNotes.insert(currentNote, at: 0)
            if relevantNotes.count > 10 {
                relevantNotes = Array(relevantNotes.prefix(10))
            }
        }

        statusMessage = "Thinking over \(relevantNotes.count) notes..."

        // Build prompt and send
        let systemPrompt = buildRAGPrompt(notes: relevantNotes)

        // Build conversation history (last 6 messages for context)
        let recentMessages = messages.suffix(7) // includes the user message we just added
        var apiMessages: [ChatMessage] = [ChatMessage(role: "system", content: systemPrompt)]
        for msg in recentMessages {
            let role: String
            switch msg.role {
            case .user: role = "user"
            case .assistant: role = "assistant"
            case .system: continue
            }
            apiMessages.append(ChatMessage(role: role, content: msg.content))
        }

        do {
            let request = ChatRequest(
                model: OpenRouterConfig.primaryModel,
                messages: apiMessages,
                max_tokens: OpenRouterConfig.maxOutputTokens,
                temperature: 0.4
            )

            let (content, _) = try await sendMultiMessage(request: request)

            let assistantMsg = AIChatMessage(
                role: .assistant,
                content: content,
                timestamp: Date(),
                referencedNotes: relevantNotes
            )
            messages.append(assistantMsg)
        } catch {
            logger.error("Chat failed: \(error.localizedDescription)")
            let errorMsg = AIChatMessage(
                role: .assistant,
                content: "I encountered an error: \(error.localizedDescription)",
                timestamp: Date(),
                referencedNotes: []
            )
            messages.append(errorMsg)
        }

        isStreaming = false
        statusMessage = nil
    }

    func clearChat() {
        messages.removeAll()
    }

    // MARK: - RAG: Retrieve Relevant Notes

    func retrieveRelevantNotes(query: String, context: NSManagedObjectContext, limit: Int = 10) -> [NoteEntity] {
        let keywords = extractKeywords(from: query)
        guard !keywords.isEmpty else { return [] }

        var matchedNotes: Set<NSManagedObjectID> = []
        var noteScores: [NSManagedObjectID: Int] = [:]
        var allNotes: [NSManagedObjectID: NoteEntity] = [:]

        // Search each keyword
        for keyword in keywords {
            let request = NoteEntity.fetchRequest() as! NSFetchRequest<NoteEntity>
            request.fetchLimit = 20
            request.sortDescriptors = [NSSortDescriptor(key: "updatedAt", ascending: false)]
            request.predicate = NSCompoundPredicate(orPredicateWithSubpredicates: [
                NSPredicate(format: "title CONTAINS[cd] %@", keyword),
                NSPredicate(format: "contentPlainText CONTAINS[cd] %@", keyword)
            ])

            if let results = try? context.fetch(request) {
                for note in results {
                    matchedNotes.insert(note.objectID)
                    noteScores[note.objectID, default: 0] += 1
                    allNotes[note.objectID] = note
                }
            }
        }

        // Also search by tags
        for keyword in keywords {
            let tagRequest = NoteEntity.fetchRequest() as! NSFetchRequest<NoteEntity>
            tagRequest.fetchLimit = 10
            tagRequest.sortDescriptors = [NSSortDescriptor(key: "updatedAt", ascending: false)]
            tagRequest.predicate = NSPredicate(format: "ANY tags.name CONTAINS[cd] %@", keyword)

            if let results = try? context.fetch(tagRequest) {
                for note in results {
                    matchedNotes.insert(note.objectID)
                    noteScores[note.objectID, default: 0] += 1
                    allNotes[note.objectID] = note
                }
            }
        }

        // Sort by score (most keyword matches first), take top results
        let sortedIds = matchedNotes.sorted { noteScores[$0, default: 0] > noteScores[$1, default: 0] }
        var topNotes = sortedIds.prefix(limit).compactMap { allNotes[$0] }

        // 1-hop neighborhood: include linked notes for top 3 matches
        let topForExpansion = Array(topNotes.prefix(3))
        for note in topForExpansion {
            for link in note.outgoingLinksArray {
                if let target = link.targetNote,
                   !topNotes.contains(where: { $0.objectID == target.objectID }),
                   topNotes.count < limit {
                    topNotes.append(target)
                }
            }
            for link in note.incomingLinksArray {
                if let source = link.sourceNote,
                   !topNotes.contains(where: { $0.objectID == source.objectID }),
                   topNotes.count < limit {
                    topNotes.append(source)
                }
            }
        }

        return Array(topNotes.prefix(limit))
    }

    // MARK: - Build RAG Prompt

    func buildRAGPrompt(notes: [NoteEntity]) -> String {
        var prompt = """
        You are NoteNous AI, a knowledge assistant for a Zettelkasten note-taking system.
        Answer based ONLY on the user's notes provided below. If the information is not in the notes, say so clearly.
        Cite note titles in [[brackets]] when referencing them.
        Be concise and precise. Connect ideas across notes when relevant.
        Respond in the same language the user uses in their question.

        """

        if notes.isEmpty {
            prompt += "\nNo relevant notes found in the knowledge base."
        } else {
            prompt += "\n--- USER'S NOTES ---\n"
            for (index, note) in notes.enumerated() {
                let zettelId = note.zettelId ?? "?"
                let tags = note.tagsArray.compactMap { $0.name }.joined(separator: ", ")
                let concepts = note.conceptsArray.compactMap { $0.name }.joined(separator: ", ")
                let contextNote = note.contextNote ?? ""

                prompt += """

                [\(index + 1)] ZettelID: \(zettelId)
                Title: \(note.title)
                Type: \(note.noteType.label) | Stage: \(note.codeStage.label) | PARA: \(note.paraCategory.label)
                Tags: \(tags.isEmpty ? "none" : tags)
                Concepts: \(concepts.isEmpty ? "none" : concepts)
                Context: \(contextNote.isEmpty ? "none" : String(contextNote.prefix(200)))
                Content: \(String(note.contentPlainText.prefix(800)))

                """
            }
            prompt += "--- END NOTES ---"
        }

        return prompt
    }

    // MARK: - Private: Keyword Extraction

    private func extractKeywords(from query: String) -> [String] {
        let words = query
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count > 2 && !Self.stopwords.contains($0) }

        // Deduplicate while preserving order
        var seen: Set<String> = []
        return words.filter { seen.insert($0).inserted }
    }

    // MARK: - Private: Multi-message send

    private func sendMultiMessage(request: ChatRequest) async throws -> (content: String, tokensUsed: Int) {
        guard let apiKey = EnvLoader.apiKey ?? UserDefaults.standard.string(forKey: "openRouterAPIKey"),
              !apiKey.isEmpty else {
            throw OpenRouterError.noAPIKey
        }

        var urlRequest = URLRequest(url: URL(string: OpenRouterConfig.baseURL)!)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("NoteNous/0.1.0", forHTTPHeaderField: "HTTP-Referer")
        urlRequest.timeoutInterval = OpenRouterConfig.requestTimeout
        urlRequest.httpBody = try JSONEncoder().encode(request)

        let (data, response) = try await URLSession.shared.data(for: urlRequest)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw OpenRouterError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            logger.error("OpenRouter returned \(httpResponse.statusCode)")
            throw OpenRouterError.httpError(httpResponse.statusCode)
        }

        let chatResponse = try JSONDecoder().decode(ChatResponse.self, from: data)

        guard let content = chatResponse.choices.first?.message.content else {
            throw OpenRouterError.emptyResponse
        }

        let tokens = chatResponse.usage?.total_tokens ?? 0
        return (content, tokens)
    }
}
