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

    enum Search {
        static let maxResults = 50
        static let debounceInterval: TimeInterval = 0.3
        static let semanticDebounceInterval: TimeInterval = 0.5
        static let similarNotesLimit = 5
        static let semanticSearchLimit = 20
    }
}
