import Foundation
import CoreData
import os.log

// MARK: - Embedding Storage Model

struct NoteEmbedding: Codable {
    let noteId: UUID
    var vector: [Float]
    var updatedAt: Date
    var textHash: Int
    var isLocal: Bool

    init(noteId: UUID, vector: [Float], updatedAt: Date, textHash: Int, isLocal: Bool = false) {
        self.noteId = noteId
        self.vector = vector
        self.updatedAt = updatedAt
        self.textHash = textHash
        self.isLocal = isLocal
    }
}

// MARK: - Embedding Service

final class EmbeddingService: ObservableObject {
    static let shared = EmbeddingService()

    private let logger = Logger(subsystem: "com.notenous.app", category: "EmbeddingService")

    @Published var indexedCount: Int = 0
    @Published var totalCount: Int = 0
    @Published var isIndexing: Bool = false

    private var embeddings: [String: NoteEmbedding] = [:] // key = UUID string
    private let embeddingDimension = 512 // TF-IDF local dimension
    private let apiDimension = 1536 // OpenAI text-embedding-3-small
    private let maxVocabularySize = 2000
    private let batchSize = 20

    // TF-IDF vocabulary
    private var vocabulary: [String: Int] = [:] // word -> index
    private var idfScores: [String: Float] = [:] // word -> IDF score
    private var vocabularyBuilt = false

    // MARK: - File Storage

    private var storageURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("NoteNous", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("embeddings.json")
    }

    // MARK: - Init

    init() {
        loadEmbeddings()
    }

    // MARK: - Persistence

    func loadEmbeddings() {
        guard FileManager.default.fileExists(atPath: storageURL.path) else {
            logger.info("No embeddings file found, starting fresh")
            return
        }
        do {
            let data = try Data(contentsOf: storageURL)
            let decoded = try JSONDecoder().decode([String: NoteEmbedding].self, from: data)
            embeddings = decoded
            indexedCount = decoded.count
            logger.info("Loaded \(decoded.count) embeddings from disk")
        } catch {
            logger.error("Failed to load embeddings: \(error.localizedDescription)")
        }
    }

    func saveEmbeddings() {
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(embeddings)
            try data.write(to: storageURL, options: .atomic)
            logger.info("Saved \(self.embeddings.count) embeddings to disk")
        } catch {
            logger.error("Failed to save embeddings: \(error.localizedDescription)")
        }
    }

    // MARK: - API-based Embedding (OpenRouter)

    func generateEmbedding(text: String) async throws -> [Float] {
        guard let apiKey = EnvLoader.apiKey ?? UserDefaults.standard.string(forKey: "openRouterAPIKey"),
              !apiKey.isEmpty else {
            throw OpenRouterError.noAPIKey
        }

        let truncated = String(text.prefix(8000))

        struct EmbeddingRequest: Codable {
            let model: String
            let input: String
        }

        struct EmbeddingResponse: Codable {
            struct EmbeddingData: Codable {
                let embedding: [Float]
            }
            let data: [EmbeddingData]
        }

        let request = EmbeddingRequest(
            model: "openai/text-embedding-3-small",
            input: truncated
        )

        var urlRequest = URLRequest(url: URL(string: "https://openrouter.ai/api/v1/embeddings")!)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("NoteNous/0.1.0", forHTTPHeaderField: "HTTP-Referer")
        urlRequest.timeoutInterval = 30
        urlRequest.httpBody = try JSONEncoder().encode(request)

        let (data, response) = try await URLSession.shared.data(for: urlRequest)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            throw OpenRouterError.httpError(code)
        }

        let embeddingResponse = try JSONDecoder().decode(EmbeddingResponse.self, from: data)
        guard let vector = embeddingResponse.data.first?.embedding else {
            throw OpenRouterError.emptyResponse
        }

        return vector
    }

    // MARK: - Local TF-IDF Embedding (Offline)

    func generateLocalEmbedding(text: String) -> [Float] {
        guard vocabularyBuilt, !vocabulary.isEmpty else {
            return []
        }

        let words = tokenize(text)
        guard !words.isEmpty else { return Array(repeating: 0, count: embeddingDimension) }

        // Term frequency
        var tf: [String: Float] = [:]
        for word in words {
            tf[word, default: 0] += 1
        }
        let wordCount = Float(words.count)
        for key in tf.keys {
            tf[key]! /= wordCount
        }

        // Build TF-IDF vector
        var vector = Array(repeating: Float(0), count: embeddingDimension)
        for (word, freq) in tf {
            guard let index = vocabulary[word], index < embeddingDimension else { continue }
            let idf = idfScores[word] ?? 1.0
            vector[index] = freq * idf
        }

        // L2 normalize
        let norm = sqrt(vector.reduce(0) { $0 + $1 * $1 })
        if norm > 0 {
            for i in vector.indices {
                vector[i] /= norm
            }
        }

        return vector
    }

    func buildVocabulary(from notes: [NoteEntity]) {
        logger.info("Building TF-IDF vocabulary from \(notes.count) notes")

        var wordDocCount: [String: Int] = [:]
        var wordFreq: [String: Int] = [:]

        for note in notes {
            let text = note.title + " " + note.contentPlainText
            let words = tokenize(text)
            let uniqueWords = Set(words)

            for word in words {
                wordFreq[word, default: 0] += 1
            }
            for word in uniqueWords {
                wordDocCount[word, default: 0] += 1
            }
        }

        // Select top words by frequency
        let topWords = wordFreq
            .sorted { $0.value > $1.value }
            .prefix(maxVocabularySize)
            .map { $0.key }

        vocabulary = [:]
        for (index, word) in topWords.enumerated() {
            vocabulary[word] = index
        }

        // Compute IDF scores
        let docCount = Float(max(notes.count, 1))
        idfScores = [:]
        for (word, count) in wordDocCount {
            idfScores[word] = log(docCount / Float(max(count, 1))) + 1.0
        }

        vocabularyBuilt = true
        logger.info("Vocabulary built: \(self.vocabulary.count) words")
    }

    private func tokenize(_ text: String) -> [String] {
        let lowered = text.lowercased()
        let cleaned = lowered.components(separatedBy: CharacterSet.alphanumerics.inverted)
        return cleaned.filter { $0.count > 2 && $0.count < 30 }
    }

    // MARK: - Index All Notes

    func indexAllNotes(context: NSManagedObjectContext) async {
        await MainActor.run {
            isIndexing = true
        }

        let notes = await context.perform {
            let request = NoteEntity.fetchRequest() as! NSFetchRequest<NoteEntity>
            request.predicate = NSPredicate(format: "isArchived == NO")
            request.sortDescriptors = [NSSortDescriptor(key: "updatedAt", ascending: false)]
            return (try? context.fetch(request)) ?? []
        }

        await MainActor.run {
            totalCount = notes.count
        }

        // Build vocabulary for local TF-IDF embeddings (fallback)
        buildVocabulary(from: notes)

        // Determine provider for embeddings
        let provider = AIProviderRouter.provider(for: .embedding)

        var indexed = 0
        for note in notes {
            guard let noteId = note.id else { continue }

            let text = note.title + " " + note.contentPlainText
            let hash = text.hashValue

            // Skip if already up to date
            if let existing = embeddings[noteId.uuidString], existing.textHash == hash {
                indexed += 1
                await MainActor.run { indexedCount = indexed }
                continue
            }

            // Generate embedding based on router decision
            var vector: [Float]
            var isLocal = false

            switch provider {
            case .local:
                // Try NLEmbedding first, then TF-IDF fallback
                if let nlVector = LocalAIService.shared.generateEmbedding(text: text) {
                    vector = nlVector
                    isLocal = true
                } else {
                    vector = generateLocalEmbedding(text: text)
                    isLocal = true
                    if vector.isEmpty { continue }
                }
            case .api:
                do {
                    vector = try await generateEmbedding(text: text)
                } catch {
                    // Fallback to local
                    if let nlVector = LocalAIService.shared.generateEmbedding(text: text) {
                        vector = nlVector
                        isLocal = true
                    } else {
                        vector = generateLocalEmbedding(text: text)
                        isLocal = true
                        if vector.isEmpty { continue }
                    }
                }
            }

            embeddings[noteId.uuidString] = NoteEmbedding(
                noteId: noteId,
                vector: vector,
                updatedAt: Date(),
                textHash: hash,
                isLocal: isLocal
            )

            indexed += 1
            await MainActor.run { indexedCount = indexed }

            // Rate limiting for API calls only
            if provider == .api && !isLocal {
                try? await Task.sleep(nanoseconds: 100_000_000) // 100ms between API calls
            }
        }

        saveEmbeddings()

        await MainActor.run {
            isIndexing = false
            indexedCount = embeddings.count
        }

        logger.info("Indexing complete: \(self.embeddings.count) notes indexed")
    }

    // MARK: - Index Single Note

    func indexNote(_ note: NoteEntity) async {
        guard let noteId = note.id else { return }

        let text = note.title + " " + note.contentPlainText
        let hash = text.hashValue

        if let existing = embeddings[noteId.uuidString], existing.textHash == hash {
            return // Already up to date
        }

        var vector: [Float]
        var isLocal = false
        let provider = AIProviderRouter.provider(for: .embedding)

        switch provider {
        case .local:
            if let nlVector = LocalAIService.shared.generateEmbedding(text: text) {
                vector = nlVector
                isLocal = true
            } else {
                vector = generateLocalEmbedding(text: text)
                isLocal = true
                if vector.isEmpty { return }
            }
        case .api:
            do {
                vector = try await generateEmbedding(text: text)
            } catch {
                if let nlVector = LocalAIService.shared.generateEmbedding(text: text) {
                    vector = nlVector
                    isLocal = true
                } else {
                    vector = generateLocalEmbedding(text: text)
                    isLocal = true
                    if vector.isEmpty { return }
                }
            }
        }

        embeddings[noteId.uuidString] = NoteEmbedding(
            noteId: noteId,
            vector: vector,
            updatedAt: Date(),
            textHash: hash,
            isLocal: isLocal
        )

        await MainActor.run {
            indexedCount = embeddings.count
        }

        saveEmbeddings()
    }

    // MARK: - Find Similar Notes

    func findSimilar(to note: NoteEntity, context: NSManagedObjectContext, limit: Int = 10) -> [(note: NoteEntity, similarity: Float)] {
        guard let noteId = note.id,
              let sourceEmbedding = embeddings[noteId.uuidString] else {
            return []
        }

        var results: [(noteId: UUID, similarity: Float)] = []

        for (idString, embedding) in embeddings {
            guard idString != noteId.uuidString else { continue }
            let sim = cosineSimilarity(sourceEmbedding.vector, embedding.vector)
            if sim > 0.1 {
                results.append((noteId: embedding.noteId, similarity: sim))
            }
        }

        results.sort { $0.similarity > $1.similarity }
        let topResults = Array(results.prefix(limit))

        // Fetch NoteEntity objects
        var noteResults: [(note: NoteEntity, similarity: Float)] = []
        for result in topResults {
            let request = NoteEntity.fetchRequest() as! NSFetchRequest<NoteEntity>
            request.predicate = NSPredicate(format: "id == %@", result.noteId as CVarArg)
            request.fetchLimit = 1
            if let fetchedNote = try? context.fetch(request).first {
                noteResults.append((note: fetchedNote, similarity: result.similarity))
            }
        }

        return noteResults
    }

    // MARK: - Semantic Search

    func semanticSearch(query: String, context: NSManagedObjectContext, limit: Int = 20) async -> [(note: NoteEntity, similarity: Float)] {
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else { return [] }

        // Generate embedding for query using router
        var queryVector: [Float]
        let provider = AIProviderRouter.provider(for: .embedding)

        switch provider {
        case .local:
            if let nlVector = LocalAIService.shared.generateEmbedding(text: query) {
                queryVector = nlVector
            } else {
                queryVector = generateLocalEmbedding(text: query)
                if queryVector.isEmpty { return [] }
            }
        case .api:
            do {
                queryVector = try await generateEmbedding(text: query)
            } catch {
                if let nlVector = LocalAIService.shared.generateEmbedding(text: query) {
                    queryVector = nlVector
                } else {
                    queryVector = generateLocalEmbedding(text: query)
                    if queryVector.isEmpty { return [] }
                }
            }
        }

        // Compare against all embeddings
        var results: [(noteId: UUID, similarity: Float)] = []

        for (_, embedding) in embeddings {
            let sim = cosineSimilarity(queryVector, embedding.vector)
            if sim > 0.05 {
                results.append((noteId: embedding.noteId, similarity: sim))
            }
        }

        results.sort { $0.similarity > $1.similarity }
        let topResults = Array(results.prefix(limit))

        // Fetch NoteEntity objects
        return await context.perform {
            var noteResults: [(note: NoteEntity, similarity: Float)] = []
            for result in topResults {
                let request = NoteEntity.fetchRequest() as! NSFetchRequest<NoteEntity>
                request.predicate = NSPredicate(format: "id == %@ AND isArchived == NO", result.noteId as CVarArg)
                request.fetchLimit = 1
                if let fetchedNote = try? context.fetch(request).first {
                    noteResults.append((note: fetchedNote, similarity: result.similarity))
                }
            }
            return noteResults
        }
    }

    // MARK: - Cosine Similarity

    private func cosineSimilarity(_ a: [Float], _ b: [Float]) -> Float {
        guard !a.isEmpty, !b.isEmpty else { return 0 }

        // Handle mismatched dimensions by using the smaller size
        let count = min(a.count, b.count)
        guard count > 0 else { return 0 }

        var dot: Float = 0
        var normA: Float = 0
        var normB: Float = 0

        for i in 0..<count {
            dot += a[i] * b[i]
            normA += a[i] * a[i]
            normB += b[i] * b[i]
        }

        let denominator = sqrt(normA) * sqrt(normB)
        guard denominator > 0 else { return 0 }

        return dot / denominator
    }

    // MARK: - Utility

    func removeEmbedding(for noteId: UUID) {
        embeddings.removeValue(forKey: noteId.uuidString)
        saveEmbeddings()
        Task { @MainActor in
            indexedCount = embeddings.count
        }
    }

    func clearAllEmbeddings() {
        embeddings.removeAll()
        vocabularyBuilt = false
        vocabulary.removeAll()
        idfScores.removeAll()
        saveEmbeddings()
        Task { @MainActor in
            indexedCount = 0
        }
    }

    var hasEmbeddings: Bool {
        !embeddings.isEmpty
    }
}
