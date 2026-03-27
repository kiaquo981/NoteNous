import Foundation

// MARK: - AI Provider Router

/// Smart router that decides whether to use local (on-device) or API-based AI.
/// Rules:
/// - No API key configured -> always local
/// - "Prefer Local" setting on -> local for embedding/classification/linkSuggestion
/// - Chat and Synthesis always require API (need LLM reasoning)
/// - Offline (NetworkMonitor) -> local
/// - Otherwise -> API
final class AIProviderRouter {

    enum Provider {
        case local
        case api
    }

    enum Task {
        case embedding
        case classification
        case linkSuggestion
        case chat        // always API — needs LLM
        case synthesis   // always API — needs LLM
    }

    // MARK: - Settings Keys

    static let useLocalAIKey = "useLocalAI"
    static let preferLocalKey = "preferLocalOverAPI"

    // MARK: - Settings

    static var useLocalAI: Bool {
        // Default to true if key not set
        if UserDefaults.standard.object(forKey: useLocalAIKey) == nil {
            return true
        }
        return UserDefaults.standard.bool(forKey: useLocalAIKey)
    }

    static var preferLocal: Bool {
        // Default to true if key not set
        if UserDefaults.standard.object(forKey: preferLocalKey) == nil {
            return true
        }
        return UserDefaults.standard.bool(forKey: preferLocalKey)
    }

    // MARK: - Routing

    static func provider(for task: Task) -> Provider {
        switch task {
        case .chat, .synthesis:
            // These always need an LLM — require API
            if hasAPIKey && isOnline {
                return .api
            }
            // If no API, still return .api — caller must handle the error
            return .api

        case .embedding, .classification, .linkSuggestion:
            // If Local AI disabled, use API
            guard useLocalAI else {
                return hasAPIKey ? .api : .local // Fallback to local if no API
            }

            // If prefer local, use local
            if preferLocal {
                return .local
            }

            // If no API key, use local
            guard hasAPIKey else {
                return .local
            }

            // If offline, use local
            guard isOnline else {
                return .local
            }

            // Default: API when available and not preferring local
            return .api
        }
    }

    // MARK: - Helpers

    static var hasAPIKey: Bool {
        let key = EnvLoader.apiKey ?? UserDefaults.standard.string(forKey: "openRouterAPIKey")
        return key != nil && !(key?.isEmpty ?? true)
    }

    static var isOnline: Bool {
        NetworkMonitor.shared.isConnected
    }
}
