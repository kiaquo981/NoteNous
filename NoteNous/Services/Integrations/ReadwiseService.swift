import Foundation
import CoreData
import os.log

/// Manages Readwise API v2 integration — fetches books and highlights, creates Sources and Literature Notes.
final class ReadwiseService: ObservableObject {

    // MARK: - API Models

    struct ReadwiseHighlight: Codable, Identifiable {
        let id: Int
        let text: String
        let note: String?
        let location: Int?
        let location_type: String?
        let url: String?
        let color: String?
        let updated: String
        let book_id: Int
        let tags: [ReadwiseTag]?

        struct ReadwiseTag: Codable {
            let name: String
        }
    }

    struct ReadwiseBook: Codable, Identifiable {
        let id: Int
        let title: String
        let author: String?
        let category: String
        let source: String?
        let num_highlights: Int
        let cover_image_url: String?
        let source_url: String?
        let updated: String
    }

    struct ImportStats {
        let booksImported: Int
        let highlightsImported: Int
        let notesCreated: Int
        let sourcesCreated: Int
    }

    // MARK: - Published State

    @Published var isImporting: Bool = false
    @Published var lastSyncDate: Date?
    @Published var importStats: ImportStats?

    // MARK: - Private

    private let baseURL = "https://readwise.io/api/v2"
    private let logger = Logger(subsystem: "com.notenous.app", category: "ReadwiseService")
    private let session: URLSession

    /// Tracks Readwise highlight IDs that have already been imported to prevent duplicates.
    private static let importedHighlightIDsKey = "readwiseImportedHighlightIDs"

    private var importedHighlightIDs: Set<Int> {
        get {
            let array = UserDefaults.standard.array(forKey: Self.importedHighlightIDsKey) as? [Int] ?? []
            return Set(array)
        }
        set {
            UserDefaults.standard.set(Array(newValue), forKey: Self.importedHighlightIDsKey)
        }
    }

    // MARK: - Configuration

    /// API key stored in UserDefaults. On macOS, UserDefaults is sandboxed to the app container
    /// and protected by the file system sandbox, which is acceptable for a local-only app.
    /// For higher security requirements, consider migrating to Keychain or .env-based storage
    /// (similar to OpenRouterClient's EnvLoader approach).
    var apiKey: String? {
        get { UserDefaults.standard.string(forKey: "readwiseAPIKey") }
        set { UserDefaults.standard.set(newValue, forKey: "readwiseAPIKey") }
    }

    var isConfigured: Bool { apiKey != nil && !(apiKey?.isEmpty ?? true) }

    var autoSyncEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: "readwiseAutoSync") }
        set { UserDefaults.standard.set(newValue, forKey: "readwiseAutoSync") }
    }

    init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        self.session = URLSession(configuration: config)

        if let stored = UserDefaults.standard.object(forKey: "readwiseLastSync") as? Date {
            lastSyncDate = stored
        }
    }

    // MARK: - API Calls

    func testConnection() async throws -> Bool {
        let request = try authorizedRequest(path: "/auth")
        let (_, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { return false }
        return http.statusCode == 204
    }

    func fetchBooks() async throws -> [ReadwiseBook] {
        var allBooks: [ReadwiseBook] = []
        var nextURL: String? = "\(baseURL)/books/?page_size=100"

        while let urlString = nextURL {
            let request = try authorizedRequest(fullURL: urlString)
            let (data, response) = try await session.data(for: request)
            try validateResponse(response)

            let page = try JSONDecoder().decode(PaginatedResponse<ReadwiseBook>.self, from: data)
            allBooks.append(contentsOf: page.results)
            nextURL = page.next
        }

        logger.info("Fetched \(allBooks.count) books from Readwise")
        return allBooks
    }

    func fetchHighlights(bookId: Int) async throws -> [ReadwiseHighlight] {
        var allHighlights: [ReadwiseHighlight] = []
        var nextURL: String? = "\(baseURL)/highlights/?book_id=\(bookId)&page_size=100"

        while let urlString = nextURL {
            let request = try authorizedRequest(fullURL: urlString)
            let (data, response) = try await session.data(for: request)
            try validateResponse(response)

            let page = try JSONDecoder().decode(PaginatedResponse<ReadwiseHighlight>.self, from: data)
            allHighlights.append(contentsOf: page.results)
            nextURL = page.next
        }

        logger.info("Fetched \(allHighlights.count) highlights for book \(bookId)")
        return allHighlights
    }

    func fetchNewHighlights(since: Date?) async throws -> [ReadwiseHighlight] {
        var urlString = "\(baseURL)/highlights/?page_size=100"
        if let since = since {
            let formatter = ISO8601DateFormatter()
            urlString += "&updated__gt=\(formatter.string(from: since))"
        }

        var allHighlights: [ReadwiseHighlight] = []
        var nextURL: String? = urlString

        while let current = nextURL {
            let request = try authorizedRequest(fullURL: current)
            let (data, response) = try await session.data(for: request)
            try validateResponse(response)

            let page = try JSONDecoder().decode(PaginatedResponse<ReadwiseHighlight>.self, from: data)
            allHighlights.append(contentsOf: page.results)
            nextURL = page.next
        }

        return allHighlights
    }

    // MARK: - Import

    @MainActor
    func importAll(
        sourceService: SourceService,
        noteService: NoteService,
        tagService: TagService,
        context: NSManagedObjectContext
    ) async throws -> ImportStats {
        guard isConfigured else {
            throw ReadwiseError.notConfigured
        }

        isImporting = true
        defer { isImporting = false }

        let books = try await fetchBooks()
        var totalHighlights = 0
        var totalNotes = 0
        var totalSources = 0
        var importedIDs = importedHighlightIDs

        for book in books {
            let sourceType = mapCategory(book.category)
            let dateConsumed = parseDate(book.updated) ?? Date()

            // Check for existing source with same title + author to prevent duplicates
            let existingSource = sourceService.sources.first {
                $0.title == book.title && $0.author == book.author
            }
            let source = existingSource ?? sourceService.addSource(
                title: book.title,
                author: book.author,
                sourceType: sourceType,
                url: book.source_url,
                dateConsumed: dateConsumed,
                notes: "Imported from Readwise (\(book.category))"
            )
            if existingSource == nil { totalSources += 1 }

            let highlights = try await fetchHighlights(bookId: book.id)
            for highlight in highlights {
                // Skip already-imported highlights to prevent duplicates
                guard !importedIDs.contains(highlight.id) else { continue }

                var content = "> \(highlight.text)"
                if let userNote = highlight.note, !userNote.isEmpty {
                    content += "\n\n**Note:** \(userNote)"
                }
                if let location = highlight.location {
                    content += "\n\n*Location: \(location)*"
                }

                let note = noteService.createNote(
                    title: "[\(book.title)] Highlight",
                    content: content,
                    paraCategory: .resource
                )
                note.noteType = .literature
                note.sourceURL = book.source_url ?? highlight.url
                note.sourceTitle = book.title
                note.updatedAt = Date()

                // Tag with readwise + category
                let readwiseTag = tagService.findOrCreate(name: "readwise")
                tagService.addTag(readwiseTag, to: note)

                let categoryTag = tagService.findOrCreate(name: book.category)
                tagService.addTag(categoryTag, to: note)

                if let hlTags = highlight.tags {
                    for hlTag in hlTags {
                        let tag = tagService.findOrCreate(name: hlTag.name)
                        tagService.addTag(tag, to: note)
                    }
                }

                // Link note to source
                if let noteId = note.id {
                    sourceService.linkNote(noteId: noteId, to: source.id)
                }

                importedIDs.insert(highlight.id)
                totalNotes += 1
                totalHighlights += 1
            }
        }

        // Persist imported highlight IDs
        importedHighlightIDs = importedIDs

        let stats = ImportStats(
            booksImported: books.count,
            highlightsImported: totalHighlights,
            notesCreated: totalNotes,
            sourcesCreated: totalSources
        )

        self.importStats = stats
        self.lastSyncDate = Date()
        UserDefaults.standard.set(Date(), forKey: "readwiseLastSync")

        logger.info("Import complete: \(stats.booksImported) books, \(stats.highlightsImported) highlights, \(stats.notesCreated) notes")
        return stats
    }

    @MainActor
    func importBook(
        bookId: Int,
        sourceService: SourceService,
        noteService: NoteService,
        tagService: TagService,
        context: NSManagedObjectContext
    ) async throws -> ImportStats {
        guard isConfigured else {
            throw ReadwiseError.notConfigured
        }

        isImporting = true
        defer { isImporting = false }

        let books = try await fetchBooks()
        guard let book = books.first(where: { $0.id == bookId }) else {
            throw ReadwiseError.bookNotFound
        }

        let sourceType = mapCategory(book.category)
        let dateConsumed = parseDate(book.updated) ?? Date()

        // Check for existing source with same title + author to prevent duplicates
        let existingSource = sourceService.sources.first {
            $0.title == book.title && $0.author == book.author
        }
        let source = existingSource ?? sourceService.addSource(
            title: book.title,
            author: book.author,
            sourceType: sourceType,
            url: book.source_url,
            dateConsumed: dateConsumed,
            notes: "Imported from Readwise (\(book.category))"
        )

        let highlights = try await fetchHighlights(bookId: bookId)
        var totalNotes = 0
        var importedIDs = importedHighlightIDs

        for highlight in highlights {
            // Skip already-imported highlights to prevent duplicates
            guard !importedIDs.contains(highlight.id) else { continue }

            var content = "> \(highlight.text)"
            if let userNote = highlight.note, !userNote.isEmpty {
                content += "\n\n**Note:** \(userNote)"
            }

            let note = noteService.createNote(
                title: "[\(book.title)] Highlight",
                content: content,
                paraCategory: .resource
            )
            note.noteType = .literature
            note.sourceURL = book.source_url ?? highlight.url
            note.sourceTitle = book.title
            note.updatedAt = Date()

            let readwiseTag = tagService.findOrCreate(name: "readwise")
            tagService.addTag(readwiseTag, to: note)

            let categoryTag = tagService.findOrCreate(name: book.category)
            tagService.addTag(categoryTag, to: note)

            if let noteId = note.id {
                sourceService.linkNote(noteId: noteId, to: source.id)
            }

            importedIDs.insert(highlight.id)
            totalNotes += 1
        }

        // Persist imported highlight IDs
        importedHighlightIDs = importedIDs

        let stats = ImportStats(
            booksImported: 1,
            highlightsImported: totalNotes,
            notesCreated: totalNotes,
            sourcesCreated: existingSource == nil ? 1 : 0
        )

        self.importStats = stats
        logger.info("Imported book '\(book.title)': \(highlights.count) highlights")
        return stats
    }

    // MARK: - Helpers

    private func authorizedRequest(path: String) throws -> URLRequest {
        try authorizedRequest(fullURL: "\(baseURL)\(path)")
    }

    private func authorizedRequest(fullURL: String) throws -> URLRequest {
        guard let key = apiKey, !key.isEmpty else {
            throw ReadwiseError.notConfigured
        }
        guard let url = URL(string: fullURL) else {
            throw ReadwiseError.invalidURL
        }
        var request = URLRequest(url: url)
        request.setValue("Token \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        return request
    }

    private func validateResponse(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else {
            throw ReadwiseError.invalidResponse
        }
        switch http.statusCode {
        case 200...299: return
        case 401: throw ReadwiseError.unauthorized
        case 429: throw ReadwiseError.rateLimited
        default: throw ReadwiseError.httpError(http.statusCode)
        }
    }

    private func mapCategory(_ category: String) -> SourceType {
        switch category.lowercased() {
        case "books": return .book
        case "articles": return .article
        case "tweets": return .tweet
        case "podcasts": return .podcast
        default: return .other
        }
    }

    private func parseDate(_ dateString: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: dateString) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: dateString)
    }

    // MARK: - Pagination Model

    private struct PaginatedResponse<T: Codable>: Codable {
        let count: Int
        let next: String?
        let previous: String?
        let results: [T]
    }

    // MARK: - Errors

    enum ReadwiseError: LocalizedError {
        case notConfigured
        case invalidURL
        case invalidResponse
        case unauthorized
        case rateLimited
        case bookNotFound
        case httpError(Int)

        var errorDescription: String? {
            switch self {
            case .notConfigured: return "Readwise API key not configured"
            case .invalidURL: return "Invalid URL"
            case .invalidResponse: return "Invalid response from server"
            case .unauthorized: return "Invalid API key"
            case .rateLimited: return "Rate limited — try again later"
            case .bookNotFound: return "Book not found"
            case .httpError(let code): return "HTTP error \(code)"
            }
        }
    }
}
