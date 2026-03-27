import Foundation
import os.log

struct OpenRouterConfig {
    static let baseURL = "https://openrouter.ai/api/v1/chat/completions"
    static let primaryModel = "google/gemini-2.0-flash-exp"
    static let fallbackModel = "anthropic/claude-3.5-haiku-20241022"
    static let maxInputTokens = 4096
    static let maxOutputTokens = 2048
    static let requestTimeout: TimeInterval = 30
    static let maxRetries = 2
}

struct ChatMessage: Codable {
    let role: String
    let content: String
}

struct ChatRequest: Codable {
    let model: String
    let messages: [ChatMessage]
    let max_tokens: Int
    let temperature: Double
}

struct ChatResponse: Codable {
    struct Choice: Codable {
        struct Message: Codable {
            let content: String
        }
        let message: Message
    }
    struct Usage: Codable {
        let prompt_tokens: Int
        let completion_tokens: Int
        let total_tokens: Int
    }
    let choices: [Choice]
    let usage: Usage?
}

final class OpenRouterClient {
    private let logger = Logger(subsystem: "com.notenous.app", category: "OpenRouter")

    private var apiKey: String? {
        KeychainManager.load(key: "openrouter_api_key")
    }

    var isConfigured: Bool {
        apiKey != nil && !(apiKey?.isEmpty ?? true)
    }

    func send(
        system: String,
        user: String,
        model: String = OpenRouterConfig.primaryModel,
        temperature: Double = 0.3
    ) async throws -> (content: String, tokensUsed: Int) {
        guard let apiKey = apiKey, !apiKey.isEmpty else {
            throw OpenRouterError.noAPIKey
        }

        let request = ChatRequest(
            model: model,
            messages: [
                ChatMessage(role: "system", content: system),
                ChatMessage(role: "user", content: user)
            ],
            max_tokens: OpenRouterConfig.maxOutputTokens,
            temperature: temperature
        )

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

    func sendWithFallback(system: String, user: String) async throws -> (content: String, tokensUsed: Int) {
        // Try primary model
        for attempt in 0...OpenRouterConfig.maxRetries {
            do {
                return try await send(system: system, user: user, model: OpenRouterConfig.primaryModel)
            } catch OpenRouterError.httpError(let code) where code == 429 || code >= 500 {
                if attempt < OpenRouterConfig.maxRetries {
                    logger.info("Retry \(attempt + 1) for primary model")
                    try await Task.sleep(for: .seconds(1))
                    continue
                }
            } catch {
                break
            }
        }

        // Fallback to secondary model
        logger.info("Falling back to \(OpenRouterConfig.fallbackModel)")
        return try await send(system: system, user: user, model: OpenRouterConfig.fallbackModel)
    }
}

enum OpenRouterError: LocalizedError {
    case noAPIKey
    case invalidResponse
    case httpError(Int)
    case emptyResponse
    case decodingError

    var errorDescription: String? {
        switch self {
        case .noAPIKey: "OpenRouter API key not configured"
        case .invalidResponse: "Invalid response from OpenRouter"
        case .httpError(let code): "HTTP error \(code)"
        case .emptyResponse: "Empty response from OpenRouter"
        case .decodingError: "Failed to decode AI response"
        }
    }
}
