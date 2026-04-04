import Foundation

enum Constants {
    static let appName = "NoteNous"
    static let bundleId = "com.notenous.app"

    enum AI {
        static let debounceInterval: TimeInterval = 2.0
        static let maxBatchSize = 10
        static let maxRequestsPerMinute = 30
        static let defaultDailyBudget: Double = 0.50
        static let autoLinkThreshold: Float = 0.9
        static let suggestLinkThreshold: Float = 0.7
    }

    enum LocalAI {
        static let maxLocalConfidence: Double = 0.6
        static let nlEmbeddingDimension = 512
        static let maxTagsPerNote = 5
        static let maxConceptsPerNote = 3
        static let maxLinkSuggestions = 5
        static let summarySentenceCount = 3
    }

    enum Search {
        static let maxResults = 50
        static let debounceInterval: TimeInterval = 0.3
        static let semanticDebounceInterval: TimeInterval = 0.5
        static let similarNotesLimit = 5
        static let semanticSearchLimit = 20
    }

    /// Zettelkasten auto-title: extracts a descriptive title from note content.
    /// Priority: first markdown heading > first sentence > first N words > timestamp.
    static func autoTitle(from content: String, fallback: String = "Capture") -> String {
        let lines = content.components(separatedBy: .newlines)

        // 1. First markdown heading
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("#") {
                let clean = trimmed.drop(while: { $0 == "#" || $0 == " " })
                if !clean.isEmpty { return String(clean.prefix(80)) }
            }
        }

        // 2. First meaningful line
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            if trimmed == "---" { continue }
            if trimmed.unicodeScalars.allSatisfy({ !CharacterSet.letters.contains($0) }) { continue }

            if let dot = trimmed.range(of: ". ") {
                let sentence = String(trimmed[trimmed.startIndex..<dot.lowerBound])
                if sentence.count >= 8 { return String(sentence.prefix(80)) }
            } else if trimmed.hasSuffix(".") && trimmed.count >= 9 {
                return String(trimmed.dropLast().prefix(80))
            }
            return String(trimmed.prefix(80))
        }

        // 3. Timestamp fallback
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd HH:mm"
        return "\(fallback) — \(fmt.string(from: Date()))"
    }
}
