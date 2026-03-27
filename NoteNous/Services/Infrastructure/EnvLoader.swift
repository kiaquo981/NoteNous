import Foundation
import os.log

/// Reads environment variables directly from .env file.
/// No Keychain, no prompts, no friction.
struct EnvLoader {
    private static let logger = Logger(subsystem: "com.notenous.app", category: "EnvLoader")
    private static var cachedVars: [String: String]?

    /// Load .env on startup — caches in memory.
    static func loadIfNeeded() {
        guard cachedVars == nil else { return }

        guard let envPath = findEnvFile() else {
            logger.info("No .env file found — configure API key in Settings")
            cachedVars = [:]
            return
        }

        guard let contents = try? String(contentsOfFile: envPath, encoding: .utf8) else {
            logger.warning("Failed to read .env file")
            cachedVars = [:]
            return
        }

        cachedVars = parseEnv(contents)
        logger.info("Loaded \(cachedVars?.count ?? 0) env vars from .env")
    }

    /// Get the OpenRouter API key (from .env or UserDefaults fallback).
    static var apiKey: String? {
        if cachedVars == nil { loadIfNeeded() }
        let key = cachedVars?["OPENROUTER_API_KEY"]
        if let key, !key.isEmpty { return key }
        return UserDefaults.standard.string(forKey: "openRouterAPIKey")
    }

    /// Get any env var by name.
    static func get(_ name: String) -> String? {
        if cachedVars == nil { loadIfNeeded() }
        return cachedVars?[name]
    }

    /// Force reload (when .env changes).
    static func forceReload() {
        cachedVars = nil
        loadIfNeeded()
    }

    // MARK: - Private

    private static func findEnvFile() -> String? {
        let candidates = [
            Bundle.main.bundlePath + "/../../../../.env",
            Bundle.main.bundlePath + "/../../../.env",
            FileManager.default.currentDirectoryPath + "/.env",
            NSHomeDirectory() + "/code/NoteNous/.env"
        ]

        for path in candidates {
            let resolved = (path as NSString).standardizingPath
            if FileManager.default.fileExists(atPath: resolved) {
                logger.info("Found .env at: \(resolved)")
                return resolved
            }
        }

        return nil
    }

    private static func parseEnv(_ contents: String) -> [String: String] {
        var result: [String: String] = [:]
        for line in contents.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty, !trimmed.hasPrefix("#") else { continue }
            let parts = trimmed.split(separator: "=", maxSplits: 1)
            guard parts.count == 2 else { continue }
            let key = String(parts[0]).trimmingCharacters(in: .whitespaces)
            let value = String(parts[1]).trimmingCharacters(in: .whitespaces)
                .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
            result[key] = value
        }
        return result
    }
}
