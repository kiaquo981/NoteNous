import Foundation
import os.log

/// Loads environment variables from a .env file at the project root
/// and stores secrets in Keychain for secure access at runtime.
struct EnvLoader {
    private static let logger = Logger(subsystem: "com.notenous.app", category: "EnvLoader")

    /// Load .env file and populate Keychain with API keys.
    /// Called once at app startup.
    static func loadIfNeeded() {
        // Only load if Keychain doesn't already have the key
        if KeychainManager.load(key: "openrouter_api_key") != nil {
            logger.info("OpenRouter API key already in Keychain")
            return
        }

        guard let envPath = findEnvFile() else {
            logger.info("No .env file found — configure API key in Settings")
            return
        }

        guard let contents = try? String(contentsOfFile: envPath, encoding: .utf8) else {
            logger.warning("Failed to read .env file")
            return
        }

        let vars = parseEnv(contents)

        if let apiKey = vars["OPENROUTER_API_KEY"], !apiKey.isEmpty {
            let saved = KeychainManager.save(key: "openrouter_api_key", value: apiKey)
            if saved {
                logger.info("OpenRouter API key loaded from .env into Keychain")
            } else {
                logger.error("Failed to save API key to Keychain")
            }
        }
    }

    /// Force reload from .env (useful when key changes)
    static func forceReload() {
        KeychainManager.delete(key: "openrouter_api_key")
        loadIfNeeded()
    }

    // MARK: - Private

    private static func findEnvFile() -> String? {
        // Look relative to the app bundle first (dev builds), then common locations
        let candidates = [
            Bundle.main.bundlePath + "/../../../../.env",  // DerivedData → project root
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
