import XCTest
import CoreData
@testable import NoteNous

final class ChatServiceTests: NoteNousTestCase {

    private var sut: ChatService!

    override func setUp() {
        super.setUp()
        MainActor.assumeIsolated {
            sut = ChatService()
        }
    }

    override func tearDown() {
        sut = nil
        super.tearDown()
    }

    // MARK: - retrieveRelevantNotes

    @MainActor
    func testRetrieveRelevantNotes() {
        // Create notes with specific keywords
        createNote(title: "Swift Concurrency", content: "async await patterns in Swift")
        createNote(title: "Python Basics", content: "introduction to Python programming")
        createNote(title: "Swift UI Guide", content: "building interfaces with SwiftUI framework")

        let results = sut.retrieveRelevantNotes(query: "Swift concurrency async", context: context, limit: 10)

        XCTAssertFalse(results.isEmpty, "Should find notes matching keywords")
        // The note about Swift Concurrency should be in results
        let titles = results.map { $0.title }
        XCTAssertTrue(titles.contains("Swift Concurrency"), "Should find the Swift Concurrency note")
    }

    // MARK: - Keyword Extraction

    @MainActor
    func testKeywordExtraction() {
        // Test via retrieveRelevantNotes with stopwords — searching for "the" and "is" should yield nothing
        // but "architecture" should find notes
        createNote(title: "Architecture Patterns", content: "software architecture design patterns")

        let resultsStopwords = sut.retrieveRelevantNotes(query: "the is a an", context: context, limit: 10)
        XCTAssertTrue(resultsStopwords.isEmpty, "Stopwords-only query should return no results")

        let resultsReal = sut.retrieveRelevantNotes(query: "architecture patterns", context: context, limit: 10)
        XCTAssertFalse(resultsReal.isEmpty, "Real keywords should find matching notes")
    }

    // MARK: - buildRAGPrompt

    @MainActor
    func testBuildRAGPrompt() {
        let note1 = createNote(title: "Test Note Alpha", content: "Alpha content about testing")
        let note2 = createNote(title: "Test Note Beta", content: "Beta content about development")

        let prompt = sut.buildRAGPrompt(notes: [note1, note2])

        XCTAssertTrue(prompt.contains("NoteNous AI"), "Prompt should include system identity")
        XCTAssertTrue(prompt.contains("Test Note Alpha"), "Prompt should include first note title")
        XCTAssertTrue(prompt.contains("Test Note Beta"), "Prompt should include second note title")
        XCTAssertTrue(prompt.contains("Alpha content"), "Prompt should include note content")
    }

    @MainActor
    func testBuildRAGPromptEmpty() {
        let prompt = sut.buildRAGPrompt(notes: [])
        XCTAssertTrue(prompt.contains("No relevant notes found"), "Empty notes should produce fallback message")
    }

    // MARK: - Empty Query

    @MainActor
    func testEmptyQuery() {
        createNote(title: "Some Note", content: "Some content")

        let results = sut.retrieveRelevantNotes(query: "", context: context, limit: 10)
        XCTAssertTrue(results.isEmpty, "Empty query should return empty results")

        let resultsWhitespace = sut.retrieveRelevantNotes(query: "   ", context: context, limit: 10)
        XCTAssertTrue(resultsWhitespace.isEmpty, "Whitespace-only query should return empty results")
    }
}
