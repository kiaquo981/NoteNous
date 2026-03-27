import XCTest
@testable import NoteNous

final class LocalAIServiceTests: NoteNousTestCase {

    private var service: LocalAIService!

    override func setUp() {
        super.setUp()
        service = LocalAIService()
    }

    override func tearDown() {
        service = nil
        super.tearDown()
    }

    // MARK: - PARA Classification

    func testClassifyPARA_project() {
        let result = service.classifyPARA(title: "Sprint plan", content: "We have a deadline to deliver by Friday")
        XCTAssertEqual(result, .project, "Text with 'deadline' and 'deliver' should classify as project")
    }

    func testClassifyPARA_resource() {
        let result = service.classifyPARA(title: "Useful reference", content: "According to the article from http://example.com this is important source material")
        XCTAssertEqual(result, .resource, "Text with 'reference', 'article', 'http', 'source' should classify as resource")
    }

    func testClassifyPARA_inbox() {
        let result = service.classifyPARA(title: "Quick note", content: "Random thought")
        XCTAssertEqual(result, .inbox, "Short generic text should classify as inbox")
    }

    // MARK: - Note Type Classification

    func testClassifyNoteType_fleeting() {
        let result = service.classifyNoteType(title: "Idea", content: "Short note", sourceURL: nil)
        XCTAssertEqual(result, .fleeting, "Short text with no source should be fleeting")
    }

    func testClassifyNoteType_literature() {
        let result = service.classifyNoteType(title: "Book notes", content: "Some content", sourceURL: "https://example.com/article")
        XCTAssertEqual(result, .literature, "Note with sourceURL should be literature")
    }

    func testClassifyNoteType_permanent() {
        let longContent = """
        This is a comprehensive analysis of epistemological frameworks and their application.
        It connects multiple ideas from different sources into a unified theory.
        ## Key Arguments
        The first argument states that knowledge is constructed.
        The second argument builds on the first.
        - Point one relates to [[previous note]]
        - Point two extends the argument further
        The implications are significant for the field.
        """
        let result = service.classifyNoteType(title: "Knowledge Construction Theory", content: longContent, sourceURL: nil)
        XCTAssertEqual(result, .permanent, "Long text with links and structure should be permanent")
    }

    // MARK: - Tag Extraction

    func testExtractTags() {
        let tags = service.extractTags(from: "Machine learning algorithms are transforming computer science research in artificial intelligence", limit: 5)
        XCTAssertFalse(tags.isEmpty, "Should extract at least some tags from meaningful text")
        // Tags should be lowercase
        for tag in tags {
            XCTAssertEqual(tag, tag.lowercased(), "Tags should be lowercased")
        }
    }

    // MARK: - Keyword Extraction

    func testExtractKeywords() {
        let keywords = service.extractKeywords(from: "The neural network architecture processes data through multiple hidden layers to produce accurate classification results", limit: 5)
        XCTAssertFalse(keywords.isEmpty, "Should extract keywords from meaningful text")
        XCTAssertLessThanOrEqual(keywords.count, 5, "Should respect the limit parameter")
    }

    // MARK: - Summarization

    func testSummarize() {
        let text = "Machine learning is a subset of artificial intelligence. It focuses on building systems that learn from data. Neural networks are inspired by biological neurons. Deep learning uses multiple layers of neural networks. Natural language processing enables computers to understand human language. Computer vision allows machines to interpret visual information."
        let summary = service.summarize(text: text, sentenceCount: 2)

        // The summary should be shorter than the original
        XCTAssertLessThan(summary.count, text.count, "Summary should be shorter than the original text")
    }

    // MARK: - Language Detection

    func testDetectLanguage() {
        let enResult = service.detectLanguage(text: "Hello world, this is a test of the language detection system")
        XCTAssertEqual(enResult, "en", "Should detect English")

        let ptResult = service.detectLanguage(text: "Ola mundo, este e um teste do sistema de deteccao de idioma em portugues")
        XCTAssertEqual(ptResult, "pt", "Should detect Portuguese")
    }
}
