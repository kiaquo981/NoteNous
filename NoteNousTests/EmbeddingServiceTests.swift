import XCTest
import CoreData
@testable import NoteNous

final class EmbeddingServiceTests: NoteNousTestCase {

    private var service: EmbeddingService!

    override func setUp() {
        super.setUp()
        service = EmbeddingService()
    }

    override func tearDown() {
        service = nil
        super.tearDown()
    }

    // MARK: - Stable Hash

    func testStableHash() {
        // Same text must always produce the same hash
        let text = "The quick brown fox jumps over the lazy dog"
        let hash1 = stableHash(text)
        let hash2 = stableHash(text)
        XCTAssertEqual(hash1, hash2, "stableHash should be deterministic")
    }

    func testStableHashDifferent() {
        let hashA = stableHash("Hello world")
        let hashB = stableHash("Goodbye world")
        XCTAssertNotEqual(hashA, hashB, "Different texts should produce different hashes")
    }

    // MARK: - Cosine Similarity

    func testCosineSimilarity() {
        // Known vectors: (1,0) and (1,1) -> cos = 1/sqrt(2) ~ 0.707
        let a: [Float] = [1, 0]
        let b: [Float] = [1, 1]
        let similarity = cosineSimilarity(a, b)
        XCTAssertEqual(similarity, 1.0 / sqrt(2.0), accuracy: 0.001)
    }

    func testCosineSimilarityIdentical() {
        let v: [Float] = [0.5, 0.3, 0.8, 0.1]
        let similarity = cosineSimilarity(v, v)
        XCTAssertEqual(similarity, 1.0, accuracy: 0.001, "Identical vectors should have similarity 1.0")
    }

    func testCosineSimilarityOrthogonal() {
        let a: [Float] = [1, 0, 0]
        let b: [Float] = [0, 1, 0]
        let similarity = cosineSimilarity(a, b)
        XCTAssertEqual(similarity, 0.0, accuracy: 0.001, "Orthogonal vectors should have similarity 0.0")
    }

    // MARK: - Local TF-IDF

    func testLocalTFIDFGeneration() {
        // Build vocabulary from some notes first
        let note1 = createNote(title: "Machine learning basics", content: "Neural networks are used in deep learning applications for pattern recognition")
        let note2 = createNote(title: "Data structures", content: "Trees and graphs are fundamental data structures used in computer science algorithms")
        let note3 = createNote(title: "Web development", content: "JavaScript frameworks like React and Angular are used for building web applications")

        service.buildVocabulary(from: [note1, note2, note3])

        let vector = service.generateLocalEmbedding(text: "Neural networks for deep learning pattern recognition")
        XCTAssertFalse(vector.isEmpty, "Should generate a non-empty vector")

        let hasNonZero = vector.contains { $0 != 0 }
        XCTAssertTrue(hasNonZero, "Vector should have at least one non-zero element")
    }

    func testLocalTFIDFDifferentTexts() {
        let note1 = createNote(title: "Cooking recipes", content: "Baking bread requires flour water yeast and salt mixed together")
        let note2 = createNote(title: "Astronomy facts", content: "Stars galaxies planets and nebulae populate the vast universe beyond earth")

        service.buildVocabulary(from: [note1, note2])

        let vec1 = service.generateLocalEmbedding(text: "Baking bread with flour and water")
        let vec2 = service.generateLocalEmbedding(text: "Stars and galaxies in the universe")

        XCTAssertFalse(vec1.isEmpty)
        XCTAssertFalse(vec2.isEmpty)
        XCTAssertNotEqual(vec1, vec2, "Different texts should produce different vectors")
    }

    // MARK: - Private helpers (reimplemented for testing)

    /// Mirror of the private stableHash in EmbeddingService (DJB2)
    private func stableHash(_ text: String) -> Int {
        var hash = 5381
        for char in text.utf8 {
            hash = ((hash << 5) &+ hash) &+ Int(char)
        }
        return hash
    }

    /// Mirror of the private cosineSimilarity in EmbeddingService
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
}
