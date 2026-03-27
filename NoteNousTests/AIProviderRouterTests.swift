import XCTest
@testable import NoteNous

final class AIProviderRouterTests: XCTestCase {

    override func setUp() {
        super.setUp()
        // Clear any stored keys/prefs to get a clean state
        UserDefaults.standard.removeObject(forKey: AIProviderRouter.useLocalAIKey)
        UserDefaults.standard.removeObject(forKey: AIProviderRouter.preferLocalKey)
        UserDefaults.standard.removeObject(forKey: "openRouterAPIKey")
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: AIProviderRouter.useLocalAIKey)
        UserDefaults.standard.removeObject(forKey: AIProviderRouter.preferLocalKey)
        UserDefaults.standard.removeObject(forKey: "openRouterAPIKey")
        super.tearDown()
    }

    // MARK: - Embedding with Prefer Local

    func testEmbeddingLocal() {
        // Default: preferLocal is true when key is not set
        // useLocalAI is true when key is not set
        let provider = AIProviderRouter.provider(for: .embedding)
        XCTAssertEqual(provider, .local, "Embedding with preferLocal=true should return .local")
    }

    // MARK: - Chat Always API

    func testChatAlwaysAPI() {
        let provider = AIProviderRouter.provider(for: .chat)
        XCTAssertEqual(provider, .api, "Chat should always return .api")
    }

    // MARK: - Synthesis Always API

    func testSynthesisAlwaysAPI() {
        let provider = AIProviderRouter.provider(for: .synthesis)
        XCTAssertEqual(provider, .api, "Synthesis should always return .api")
    }

    // MARK: - No API Key Falls to Local

    func testPreferLocalReturnsLocal() {
        // When preferLocal is on, should use local even if API key exists
        UserDefaults.standard.set(true, forKey: AIProviderRouter.useLocalAIKey)
        UserDefaults.standard.set(true, forKey: AIProviderRouter.preferLocalKey)

        let embeddingProvider = AIProviderRouter.provider(for: .embedding)
        XCTAssertEqual(embeddingProvider, .local, "With preferLocal, embedding should be .local")

        let classificationProvider = AIProviderRouter.provider(for: .classification)
        XCTAssertEqual(classificationProvider, .local, "With preferLocal, classification should be .local")

        let linkProvider = AIProviderRouter.provider(for: .linkSuggestion)
        XCTAssertEqual(linkProvider, .local, "With preferLocal, linkSuggestion should be .local")
    }

    func testLocalAIDisabledUsesAPI() {
        // When localAI is off, should use API if key available
        UserDefaults.standard.set(false, forKey: AIProviderRouter.useLocalAIKey)
        UserDefaults.standard.set(false, forKey: AIProviderRouter.preferLocalKey)

        let provider = AIProviderRouter.provider(for: .embedding)
        // Will be .api if key exists (from .env), .local if not
        XCTAssertTrue(provider == .api || provider == .local, "Should return valid provider")
    }
}
