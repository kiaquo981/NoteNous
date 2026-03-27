import Foundation
import NaturalLanguage
import os.log

// MARK: - Local AI Service

/// Central local AI service that provides offline alternatives to every API-dependent feature.
/// Uses Apple's NaturalLanguage framework (built into macOS 14+) — no model downloads needed.
final class LocalAIService: ObservableObject {
    static let shared = LocalAIService()

    private let logger = Logger(subsystem: "com.notenous.app", category: "LocalAI")

    @Published var isAvailable: Bool = true

    // Cached embeddings
    private var sentenceEmbedding: NLEmbedding?
    private var wordEmbedding: NLEmbedding?

    // Performance tracking
    @Published var averageEmbeddingTimeMs: Double = 0
    @Published var averageClassificationTimeMs: Double = 0
    private var embeddingTimeSamples: [Double] = []
    private var classificationTimeSamples: [Double] = []

    // MARK: - Init

    init() {
        loadEmbeddings()
    }

    private func loadEmbeddings() {
        sentenceEmbedding = NLEmbedding.sentenceEmbedding(for: .english)
        wordEmbedding = NLEmbedding.wordEmbedding(for: .english)

        if sentenceEmbedding == nil {
            logger.warning("NLEmbedding.sentenceEmbedding not available for English")
        }
        if wordEmbedding == nil {
            logger.warning("NLEmbedding.wordEmbedding not available for English")
        }

        logger.info("LocalAI initialized — sentence: \(self.sentenceEmbedding != nil), word: \(self.wordEmbedding != nil)")
    }

    // MARK: - Embedding Language

    var supportedLanguages: [(language: NLLanguage, hasSentence: Bool, hasWord: Bool)] {
        let languages: [NLLanguage] = [.english, .portuguese, .spanish, .french, .german]
        return languages.map { lang in
            (
                language: lang,
                hasSentence: NLEmbedding.sentenceEmbedding(for: lang) != nil,
                hasWord: NLEmbedding.wordEmbedding(for: lang) != nil
            )
        }
    }

    func setEmbeddingLanguage(_ language: NLLanguage) {
        sentenceEmbedding = NLEmbedding.sentenceEmbedding(for: language)
        wordEmbedding = NLEmbedding.wordEmbedding(for: language)
        logger.info("Embedding language set to \(language.rawValue)")
    }

    // MARK: - Embeddings (NLEmbedding)

    /// Generate sentence embedding using Apple's NLEmbedding.
    /// Returns a vector (dimension depends on Apple's model, typically 512).
    func generateEmbedding(text: String) -> [Float]? {
        let start = CFAbsoluteTimeGetCurrent()
        defer { trackEmbeddingTime(start) }

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        // Try sentence embedding first
        if let embedding = sentenceEmbedding,
           let vector = embedding.vector(for: trimmed) {
            return vector.map { Float($0) }
        }

        // Fallback: average word embeddings
        guard let wordEmbed = wordEmbedding else { return nil }

        let words = trimmed.split(separator: " ").map(String.init)
        guard !words.isEmpty else { return nil }

        var vectors: [[Double]] = []
        for word in words {
            if let vec = wordEmbed.vector(for: word.lowercased()) {
                vectors.append(vec)
            }
        }

        guard !vectors.isEmpty else { return nil }

        // Average all word vectors
        let dim = vectors[0].count
        var averaged = Array(repeating: 0.0, count: dim)
        for vec in vectors {
            for i in 0..<min(dim, vec.count) {
                averaged[i] += vec[i]
            }
        }
        let count = Double(vectors.count)
        for i in 0..<dim {
            averaged[i] /= count
        }

        // L2 normalize
        let norm = sqrt(averaged.reduce(0.0) { $0 + $1 * $1 })
        if norm > 0 {
            for i in 0..<dim {
                averaged[i] /= norm
            }
        }

        return averaged.map { Float($0) }
    }

    /// Find similar notes using NLEmbedding distance.
    func findSimilarNotes(to text: String, notes: [NoteEntity], limit: Int = 10) -> [(note: NoteEntity, distance: Double)] {
        guard let sourceVector = generateEmbedding(text: text) else { return [] }

        var results: [(note: NoteEntity, distance: Double)] = []

        for note in notes {
            let noteText = note.title + " " + note.contentPlainText
            guard let noteVector = generateEmbedding(text: noteText) else { continue }

            let similarity = cosineSimilarity(sourceVector, noteVector)
            if similarity > 0.1 {
                results.append((note: note, distance: Double(similarity)))
            }
        }

        results.sort { $0.distance > $1.distance }
        return Array(results.prefix(limit))
    }

    // MARK: - Classification (NLTagger + Heuristics)

    /// Classify note into PARA category using NLTagger + heuristics.
    func classifyPARA(title: String, content: String) -> PARACategory {
        let text = "\(title) \(content)".lowercased()

        let projectWords = ["todo", "task", "deadline", "sprint", "milestone", "deliver", "ship",
                            "prazo", "entregar", "tarefa", "objetivo", "meta"]
        let areaWords = ["ongoing", "responsibility", "routine", "maintain", "process", "standard",
                         "rotina", "manter", "processo", "responsabilidade", "health", "finance"]
        let resourceWords = ["reference", "source", "article", "book", "paper", "tutorial",
                             "according to", "from:", "http", "www", "referencia", "artigo", "livro"]

        let projectScore = projectWords.reduce(0) { $0 + (text.contains($1) ? 1 : 0) }
        let areaScore = areaWords.reduce(0) { $0 + (text.contains($1) ? 1 : 0) }
        let resourceScore = resourceWords.reduce(0) { $0 + (text.contains($1) ? 1 : 0) }

        let maxScore = max(projectScore, areaScore, resourceScore)

        if maxScore == 0 {
            return content.count < 50 ? .inbox : .inbox
        }

        if projectScore == maxScore { return .project }
        if areaScore == maxScore { return .area }
        if resourceScore == maxScore { return .resource }

        return .inbox
    }

    /// Classify note type (fleeting/literature/permanent) using heuristics.
    func classifyNoteType(title: String, content: String, sourceURL: String?) -> NoteType {
        if let url = sourceURL, !url.isEmpty {
            return .literature
        }

        let text = "\(title) \(content)"

        if text.contains("Source:") || text.contains("According to") || text.contains("Fonte:") {
            return .literature
        }

        if content.count < 100 && !content.contains("[[") {
            return .fleeting
        }

        let lineCount = content.components(separatedBy: "\n").count
        let hasLinks = content.contains("[[")
        let hasStructure = lineCount > 5 || content.contains("## ") || content.contains("- ")

        if content.count > 100 && (hasLinks || hasStructure) {
            return .permanent
        }

        return .fleeting
    }

    /// Classify CODE stage using content analysis.
    func classifyCODEStage(content: String, linkCount: Int) -> CODEStage {
        let length = content.count
        let lineCount = content.components(separatedBy: "\n").count
        let hasHeaders = content.contains("## ") || content.contains("### ")
        let hasHighlights = content.contains("**") || content.contains("==")
        let hasSummary = content.lowercased().contains("summary") || content.lowercased().contains("conclusion") ||
                         content.lowercased().contains("resumo") || content.lowercased().contains("conclus")

        // Expressed: has been shared/published, many links, well-structured
        if linkCount >= 3 && hasHeaders && length > 500 && hasSummary {
            return .expressed
        }

        // Distilled: has highlights, condensed, structured
        if hasHighlights && hasHeaders && length > 200 {
            return .distilled
        }

        // Organized: has some structure, tags, or links
        if (lineCount > 5 || linkCount > 0 || hasHeaders) && length > 100 {
            return .organized
        }

        return .captured
    }

    /// Extract tags using NLTagger (nouns + named entities).
    func extractTags(from text: String, limit: Int = 5) -> [String] {
        let start = CFAbsoluteTimeGetCurrent()
        defer { trackClassificationTime(start) }

        var tags: [String: Int] = [:]

        // Extract nouns
        let nounTagger = NLTagger(tagSchemes: [.lexicalClass])
        nounTagger.string = text
        nounTagger.enumerateTags(in: text.startIndex..<text.endIndex, unit: .word, scheme: .lexicalClass) { tag, range in
            if tag == .noun {
                let word = String(text[range]).lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
                if word.count > 2 && word.count < 30 && !Self.stopwords.contains(word) {
                    tags[word, default: 0] += 1
                }
            }
            return true
        }

        // Extract named entities
        let entityTagger = NLTagger(tagSchemes: [.nameType])
        entityTagger.string = text
        entityTagger.enumerateTags(in: text.startIndex..<text.endIndex, unit: .word, scheme: .nameType) { tag, range in
            if tag == .personalName || tag == .placeName || tag == .organizationName {
                let entity = String(text[range]).lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
                if entity.count > 1 {
                    tags[entity, default: 0] += 3 // Weight entities higher
                }
            }
            return true
        }

        return tags.sorted { $0.value > $1.value }
            .prefix(limit)
            .map { $0.key }
    }

    /// Extract key concepts using NLTagger.
    func extractConcepts(from text: String, limit: Int = 3) -> [String] {
        // Use noun phrases as concepts — extract consecutive nouns/adjectives
        let tagger = NLTagger(tagSchemes: [.lexicalClass])
        tagger.string = text

        var concepts: [String: Int] = [:]
        var currentPhrase: [String] = []

        tagger.enumerateTags(in: text.startIndex..<text.endIndex, unit: .word, scheme: .lexicalClass) { tag, range in
            let word = String(text[range]).trimmingCharacters(in: .whitespacesAndNewlines)
            if tag == .noun || tag == .adjective {
                if !word.isEmpty {
                    currentPhrase.append(word)
                }
            } else {
                if currentPhrase.count >= 2 {
                    let phrase = currentPhrase.joined(separator: " ").lowercased()
                    if !Self.stopwords.contains(phrase) {
                        concepts[phrase, default: 0] += 1
                    }
                }
                currentPhrase = []
            }
            return true
        }

        // Flush last phrase
        if currentPhrase.count >= 2 {
            let phrase = currentPhrase.joined(separator: " ").lowercased()
            concepts[phrase, default: 0] += 1
        }

        return concepts.sorted { $0.value > $1.value }
            .prefix(limit)
            .map { $0.key }
    }

    // MARK: - Link Suggestions (Local)

    /// Suggest links based on NLEmbedding similarity + shared concepts.
    func suggestLinks(for note: NoteEntity, candidates: [NoteEntity], limit: Int = 5) -> [(note: NoteEntity, score: Double, reason: String)] {
        let noteText = note.title + " " + note.contentPlainText
        let noteKeywords = Set(extractTags(from: noteText, limit: 10))
        let noteEmbedding = generateEmbedding(text: noteText)

        var results: [(note: NoteEntity, score: Double, reason: String)] = []

        for candidate in candidates {
            guard candidate.id != note.id else { continue }

            var score: Double = 0
            var reasons: [String] = []

            let candidateText = candidate.title + " " + candidate.contentPlainText

            // Embedding similarity (60% weight)
            if let srcEmb = noteEmbedding,
               let tgtEmb = generateEmbedding(text: candidateText) {
                let similarity = Double(cosineSimilarity(srcEmb, tgtEmb))
                if similarity > 0.1 {
                    score += similarity * 0.6
                    reasons.append("Content similarity: \(Int(similarity * 100))%")
                }
            }

            // Shared keywords (40% weight)
            let candidateKeywords = Set(extractTags(from: candidateText, limit: 10))
            let shared = noteKeywords.intersection(candidateKeywords)
            if !shared.isEmpty {
                let keywordScore = Double(shared.count) / Double(max(noteKeywords.count, 1))
                score += keywordScore * 0.4
                reasons.append("Shared topics: \(shared.prefix(3).joined(separator: ", "))")
            }

            if score > 0.1 {
                let reason = reasons.joined(separator: "; ")
                results.append((note: candidate, score: min(score, 1.0), reason: reason))
            }
        }

        results.sort { $0.score > $1.score }
        return Array(results.prefix(limit))
    }

    // MARK: - Text Analysis

    /// Detect language of text.
    func detectLanguage(text: String) -> String? {
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)
        return recognizer.dominantLanguage?.rawValue
    }

    /// Extract named entities (people, places, organizations).
    func extractEntities(from text: String) -> [(entity: String, type: NLTag)] {
        let tagger = NLTagger(tagSchemes: [.nameType])
        tagger.string = text

        var entities: [(entity: String, type: NLTag)] = []
        tagger.enumerateTags(in: text.startIndex..<text.endIndex, unit: .word, scheme: .nameType) { tag, range in
            if let tag = tag, tag != .otherWord {
                let entity = String(text[range]).trimmingCharacters(in: .whitespacesAndNewlines)
                if !entity.isEmpty {
                    entities.append((entity: entity, type: tag))
                }
            }
            return true
        }

        return entities
    }

    /// Sentiment analysis.
    func analyzeSentiment(text: String) -> Double {
        let tagger = NLTagger(tagSchemes: [.sentimentScore])
        tagger.string = text

        var totalScore: Double = 0
        var count = 0

        tagger.enumerateTags(in: text.startIndex..<text.endIndex, unit: .sentence, scheme: .sentimentScore) { tag, _ in
            if let tag = tag, let score = Double(tag.rawValue) {
                totalScore += score
                count += 1
            }
            return true
        }

        guard count > 0 else { return 0 }
        return totalScore / Double(count)
    }

    /// Keyword extraction (TF-based, no IDF needed for single doc).
    func extractKeywords(from text: String, limit: Int = 10) -> [String] {
        let tagger = NLTagger(tagSchemes: [.lexicalClass])
        tagger.string = text

        var wordCounts: [String: Int] = [:]

        tagger.enumerateTags(in: text.startIndex..<text.endIndex, unit: .word, scheme: .lexicalClass) { tag, range in
            if tag == .noun || tag == .verb || tag == .adjective {
                let word = String(text[range]).lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
                if word.count > 2 && !Self.stopwords.contains(word) {
                    wordCounts[word, default: 0] += 1
                }
            }
            return true
        }

        return wordCounts.sorted { $0.value > $1.value }
            .prefix(limit)
            .map { $0.key }
    }

    /// Summarize text (extractive: pick top sentences by keyword density).
    func summarize(text: String, sentenceCount: Int = 3) -> String {
        let sentences = splitSentences(text)
        guard sentences.count > sentenceCount else { return text }

        // Get top keywords from the full text
        let keywords = Set(extractKeywords(from: text, limit: 20))

        // Score each sentence by keyword density
        let scored = sentences.enumerated().map { (index, sentence) -> (index: Int, sentence: String, score: Double) in
            let words = sentence.lowercased().split(separator: " ").map(String.init)
            guard !words.isEmpty else { return (index, sentence, 0) }

            let keywordCount = words.filter { keywords.contains($0) }.count
            let density = Double(keywordCount) / Double(words.count)

            // Boost first and last sentences slightly
            let positionBoost = (index == 0 || index == sentences.count - 1) ? 0.1 : 0.0

            return (index, sentence, density + positionBoost)
        }

        // Pick top N sentences, then sort by original order
        let topSentences = scored.sorted { $0.score > $1.score }
            .prefix(sentenceCount)
            .sorted { $0.index < $1.index }
            .map { $0.sentence }

        return topSentences.joined(separator: " ")
    }

    // MARK: - Full Classification (combines all heuristics)

    /// Run full local classification returning a ClassificationResult.
    func classifyLocally(
        title: String,
        content: String,
        sourceURL: String? = nil,
        linkCount: Int = 0
    ) -> ClassificationResult {
        let start = CFAbsoluteTimeGetCurrent()
        defer { trackClassificationTime(start) }

        let para = classifyPARA(title: title, content: content)
        let noteType = classifyNoteType(title: title, content: content, sourceURL: sourceURL)
        let codeStage = classifyCODEStage(content: content, linkCount: linkCount)

        let fullText = "\(title) \(content)"
        let tags = extractTags(from: fullText, limit: 5)
        let concepts = extractConcepts(from: fullText, limit: 3)

        return ClassificationResult(
            para_category: para.label.lowercased() == "inbox" ? "inbox" : {
                switch para {
                case .project: return "project"
                case .area: return "area"
                case .resource: return "resource"
                case .archive: return "archive"
                case .inbox: return "inbox"
                }
            }(),
            note_type: {
                switch noteType {
                case .fleeting: return "fleeting"
                case .literature: return "literature"
                case .permanent: return "permanent"
                case .structure: return "structure"
                }
            }(),
            code_stage: {
                switch codeStage {
                case .captured: return "captured"
                case .organized: return "organized"
                case .distilled: return "distilled"
                case .expressed: return "expressed"
                }
            }(),
            tags: tags,
            concepts: concepts,
            suggested_links: [],
            confidence: 0.6 // Local classification caps at 0.6
        )
    }

    // MARK: - Private Helpers

    private func cosineSimilarity(_ a: [Float], _ b: [Float]) -> Float {
        guard !a.isEmpty, !b.isEmpty else { return 0 }
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

    private func splitSentences(_ text: String) -> [String] {
        let tokenizer = NLTokenizer(unit: .sentence)
        tokenizer.string = text

        var sentences: [String] = []
        tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
            let sentence = String(text[range]).trimmingCharacters(in: .whitespacesAndNewlines)
            if !sentence.isEmpty {
                sentences.append(sentence)
            }
            return true
        }

        return sentences
    }

    private func trackEmbeddingTime(_ start: CFAbsoluteTime) {
        let elapsed = (CFAbsoluteTimeGetCurrent() - start) * 1000
        embeddingTimeSamples.append(elapsed)
        if embeddingTimeSamples.count > 100 { embeddingTimeSamples.removeFirst() }
        Task { @MainActor in
            averageEmbeddingTimeMs = embeddingTimeSamples.reduce(0, +) / Double(embeddingTimeSamples.count)
        }
    }

    private func trackClassificationTime(_ start: CFAbsoluteTime) {
        let elapsed = (CFAbsoluteTimeGetCurrent() - start) * 1000
        classificationTimeSamples.append(elapsed)
        if classificationTimeSamples.count > 100 { classificationTimeSamples.removeFirst() }
        Task { @MainActor in
            averageClassificationTimeMs = classificationTimeSamples.reduce(0, +) / Double(classificationTimeSamples.count)
        }
    }

    // MARK: - Stopwords

    private static let stopwords: Set<String> = [
        // English
        "the", "this", "that", "with", "from", "they", "been", "have", "were",
        "about", "which", "when", "their", "will", "each", "make", "would",
        "could", "should", "there", "where", "what", "than", "then", "also",
        "just", "more", "some", "very", "into", "over", "such", "only",
        "other", "after", "before", "between", "under", "does", "being",
        // Portuguese
        "como", "para", "mais", "pode", "sobre", "entre", "quando", "isso",
        "esta", "esse", "pela", "pelo", "cada", "seus", "suas", "uma",
        "dos", "das", "nos", "nas", "com", "que", "por", "ser", "ter"
    ]
}
