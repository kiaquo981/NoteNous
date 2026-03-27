import Foundation
import CoreData
import SQLite3
import os.log

/// Manages VoiceInk integration — reads transcriptions from VoiceInk's SQLite database
/// and imports them into NoteNous as fleeting notes. Read-only access to VoiceInk DB.
final class VoiceInkService: ObservableObject {

    static let shared = VoiceInkService()

    // MARK: - Models

    struct VoiceInkTranscription: Identifiable {
        let id: Int  // Z_PK
        let uuid: UUID?
        let timestamp: Date
        let duration: TimeInterval
        let rawText: String
        let enhancedText: String?
        let powerMode: String?
        let promptName: String?
        let audioFileURL: String?
        let modelName: String?

        var bestText: String { enhancedText ?? rawText }
        var durationFormatted: String {
            let mins = Int(duration) / 60
            let secs = Int(duration) % 60
            return "\(mins)m \(secs)s"
        }

        var firstSentence: String {
            let text = bestText
            let delimiters = CharacterSet(charactersIn: ".!?\n")
            if let range = text.rangeOfCharacter(from: delimiters) {
                let sentence = String(text[text.startIndex..<range.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
                if sentence.count > 5 { return sentence }
            }
            return String(text.prefix(60)).trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    struct SyncStats {
        let totalTranscriptions: Int
        let newSinceLastSync: Int
        let notesCreated: Int
        let notesUpdated: Int
        let totalDuration: TimeInterval
    }

    // MARK: - Published State

    @Published var isAvailable: Bool = false
    @Published var isSyncing: Bool = false
    @Published var lastSyncDate: Date?
    @Published var transcriptionCount: Int = 0
    @Published var syncStats: SyncStats?

    private let logger = Logger(subsystem: "com.notenous.app", category: "VoiceInk")

    // MARK: - UserDefaults Keys

    private static let lastSyncKey = "voiceInkLastSyncDate"
    private static let importedPKsKey = "voiceInkImportedPKs"

    // MARK: - Database Path

    private var voiceInkDBPath: String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return "\(home)/Library/Application Support/com.prakashjoshipax.VoiceInk/default.store"
    }

    // MARK: - Init

    init() {
        checkAvailability()
        if isAvailable {
            let stats = getStats()
            transcriptionCount = stats.count
        }
        lastSyncDate = UserDefaults.standard.object(forKey: Self.lastSyncKey) as? Date
    }

    // MARK: - Availability

    func checkAvailability() {
        isAvailable = FileManager.default.fileExists(atPath: voiceInkDBPath)
        if isAvailable {
            logger.info("VoiceInk database found at \(self.voiceInkDBPath)")
        } else {
            logger.info("VoiceInk database not found")
        }
    }

    // MARK: - Fetch Transcriptions

    func fetchTranscriptions(since: Date? = nil) -> [VoiceInkTranscription] {
        guard isAvailable else { return [] }

        var db: OpaquePointer?
        guard sqlite3_open_v2(voiceInkDBPath, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
            logger.error("Failed to open VoiceInk database")
            return []
        }
        defer { sqlite3_close(db) }

        var query = """
            SELECT Z_PK, ZTIMESTAMP, ZDURATION, ZTEXT, ZENHANCEDTEXT,
                   ZPOWERMODENAME, ZPROMPTNAME, ZAUDIOFILEURL,
                   ZTRANSCRIPTIONMODELNAME, ZID
            FROM ZTRANSCRIPTION
            """

        if let since = since {
            let refDate = since.timeIntervalSinceReferenceDate
            query += " WHERE ZTIMESTAMP >= \(refDate)"
        }

        query += " ORDER BY ZTIMESTAMP DESC"

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, query, -1, &stmt, nil) == SQLITE_OK else {
            logger.error("Failed to prepare query: \(String(cString: sqlite3_errmsg(db!)))")
            return []
        }
        defer { sqlite3_finalize(stmt) }

        var transcriptions: [VoiceInkTranscription] = []

        while sqlite3_step(stmt) == SQLITE_ROW {
            let pk = Int(sqlite3_column_int(stmt, 0))
            let timestamp = sqlite3_column_double(stmt, 1)
            let duration = sqlite3_column_double(stmt, 2)
            let rawText = columnText(stmt, index: 3) ?? ""
            let enhancedText = columnText(stmt, index: 4)
            let powerMode = columnText(stmt, index: 5)
            let promptName = columnText(stmt, index: 6)
            let audioFileURL = columnText(stmt, index: 7)
            let modelName = columnText(stmt, index: 8)

            // Parse UUID from BLOB column
            var uuid: UUID?
            if sqlite3_column_type(stmt, 9) == SQLITE_BLOB,
               let blobPtr = sqlite3_column_blob(stmt, 9) {
                let blobSize = sqlite3_column_bytes(stmt, 9)
                if blobSize == 16 {
                    let data = Data(bytes: blobPtr, count: Int(blobSize))
                    uuid = data.withUnsafeBytes { buffer -> UUID in
                        let tuple = buffer.load(as: uuid_t.self)
                        return UUID(uuid: tuple)
                    }
                }
            } else if let uuidString = columnText(stmt, index: 9) {
                uuid = UUID(uuidString: uuidString)
            }

            // Convert Core Data timestamp (reference date = Jan 1 2001)
            let date = Date(timeIntervalSinceReferenceDate: timestamp)

            transcriptions.append(VoiceInkTranscription(
                id: pk,
                uuid: uuid,
                timestamp: date,
                duration: duration,
                rawText: rawText,
                enhancedText: enhancedText,
                powerMode: powerMode,
                promptName: promptName,
                audioFileURL: audioFileURL,
                modelName: modelName
            ))
        }

        return transcriptions
    }

    func fetchTranscription(pk: Int) -> VoiceInkTranscription? {
        guard isAvailable else { return nil }

        var db: OpaquePointer?
        guard sqlite3_open_v2(voiceInkDBPath, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_close(db) }

        let query = """
            SELECT Z_PK, ZTIMESTAMP, ZDURATION, ZTEXT, ZENHANCEDTEXT,
                   ZPOWERMODENAME, ZPROMPTNAME, ZAUDIOFILEURL,
                   ZTRANSCRIPTIONMODELNAME, ZID
            FROM ZTRANSCRIPTION WHERE Z_PK = ?
            """

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, query, -1, &stmt, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_int(stmt, 1, Int32(pk))

        guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }

        let timestamp = sqlite3_column_double(stmt, 1)
        let duration = sqlite3_column_double(stmt, 2)
        let rawText = columnText(stmt, index: 3) ?? ""
        let enhancedText = columnText(stmt, index: 4)
        let powerMode = columnText(stmt, index: 5)
        let promptName = columnText(stmt, index: 6)
        let audioFileURL = columnText(stmt, index: 7)
        let modelName = columnText(stmt, index: 8)

        return VoiceInkTranscription(
            id: pk,
            uuid: nil,
            timestamp: Date(timeIntervalSinceReferenceDate: timestamp),
            duration: duration,
            rawText: rawText,
            enhancedText: enhancedText,
            powerMode: powerMode,
            promptName: promptName,
            audioFileURL: audioFileURL,
            modelName: modelName
        )
    }

    // MARK: - Stats

    func getStats() -> (count: Int, totalDuration: TimeInterval, oldestDate: Date?, newestDate: Date?) {
        guard isAvailable else { return (0, 0, nil, nil) }

        var db: OpaquePointer?
        guard sqlite3_open_v2(voiceInkDBPath, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
            return (0, 0, nil, nil)
        }
        defer { sqlite3_close(db) }

        let query = "SELECT COUNT(*), COALESCE(SUM(ZDURATION), 0), MIN(ZTIMESTAMP), MAX(ZTIMESTAMP) FROM ZTRANSCRIPTION"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, query, -1, &stmt, nil) == SQLITE_OK else {
            return (0, 0, nil, nil)
        }
        defer { sqlite3_finalize(stmt) }

        guard sqlite3_step(stmt) == SQLITE_ROW else { return (0, 0, nil, nil) }

        let count = Int(sqlite3_column_int(stmt, 0))
        let totalDuration = sqlite3_column_double(stmt, 1)
        let oldestTimestamp = sqlite3_column_double(stmt, 2)
        let newestTimestamp = sqlite3_column_double(stmt, 3)

        let oldest = count > 0 ? Date(timeIntervalSinceReferenceDate: oldestTimestamp) : nil
        let newest = count > 0 ? Date(timeIntervalSinceReferenceDate: newestTimestamp) : nil

        return (count, totalDuration, oldest, newest)
    }

    // MARK: - Imported PKs Management

    private var importedPKs: Set<Int> {
        get {
            let array = UserDefaults.standard.array(forKey: Self.importedPKsKey) as? [Int] ?? []
            return Set(array)
        }
        set {
            UserDefaults.standard.set(Array(newValue), forKey: Self.importedPKsKey)
        }
    }

    func isImported(pk: Int) -> Bool {
        importedPKs.contains(pk)
    }

    var unimportedCount: Int {
        let all = fetchTranscriptions()
        let imported = importedPKs
        return all.filter { !imported.contains($0.id) && $0.duration >= 2 && $0.bestText.count >= 10 }.count
    }

    // MARK: - Sync (Basic Import)

    @MainActor
    func sync(context: NSManagedObjectContext) async -> SyncStats {
        guard !isSyncing else {
            return SyncStats(totalTranscriptions: 0, newSinceLastSync: 0, notesCreated: 0, notesUpdated: 0, totalDuration: 0)
        }

        isSyncing = true
        defer { isSyncing = false }

        let transcriptions = fetchTranscriptions(since: lastSyncDate)
        var imported = importedPKs
        var notesCreated = 0
        var totalDuration: TimeInterval = 0

        let noteService = NoteService(context: context)
        let tagService = TagService(context: context)

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"

        for transcription in transcriptions {
            // Skip noise
            guard transcription.duration >= 2 else { continue }
            guard transcription.bestText.count >= 10 else { continue }
            // Skip already imported
            guard !imported.contains(transcription.id) else { continue }

            // Create note
            let title = transcription.firstSentence
            let content = transcription.bestText

            let note = noteService.createNote(title: title, content: content, paraCategory: .inbox)
            note.noteType = .fleeting
            note.codeStage = .captured
            note.contextNote = "Voice capture via VoiceInk | Duration: \(transcription.durationFormatted) | Mode: \(transcription.powerMode ?? "default")"

            // Tag with voiceink + date
            let voiceinkTag = tagService.findOrCreate(name: "voiceink")
            tagService.addTag(voiceinkTag, to: note)

            let dateTag = tagService.findOrCreate(name: dateFormatter.string(from: transcription.timestamp))
            tagService.addTag(dateTag, to: note)

            if let promptName = transcription.promptName, !promptName.isEmpty {
                let promptTag = tagService.findOrCreate(name: "voiceink-\(promptName.lowercased())")
                tagService.addTag(promptTag, to: note)
            }

            imported.insert(transcription.id)
            notesCreated += 1
            totalDuration += transcription.duration
        }

        // Save Core Data context after all note modifications
        if context.hasChanges {
            try? context.save()
        }

        // Save imported PKs and sync date
        importedPKs = imported
        lastSyncDate = Date()
        UserDefaults.standard.set(lastSyncDate, forKey: Self.lastSyncKey)

        let stats = SyncStats(
            totalTranscriptions: transcriptions.count,
            newSinceLastSync: transcriptions.count,
            notesCreated: notesCreated,
            notesUpdated: 0,
            totalDuration: totalDuration
        )
        syncStats = stats

        // Update count
        let dbStats = getStats()
        transcriptionCount = dbStats.count

        logger.info("VoiceInk sync complete: \(notesCreated) notes created from \(transcriptions.count) transcriptions")
        return stats
    }

    // MARK: - Smart Sync (AI-powered)

    @MainActor
    func smartSync(context: NSManagedObjectContext) async -> SyncStats {
        guard !isSyncing else {
            return SyncStats(totalTranscriptions: 0, newSinceLastSync: 0, notesCreated: 0, notesUpdated: 0, totalDuration: 0)
        }

        isSyncing = true
        defer { isSyncing = false }

        let transcriptions = fetchTranscriptions(since: lastSyncDate)
        var imported = importedPKs

        // Filter valid, unimported transcriptions
        let validTranscriptions = transcriptions.filter { t in
            t.duration >= 2 && t.bestText.count >= 10 && !imported.contains(t.id)
        }

        guard !validTranscriptions.isEmpty else {
            isSyncing = false
            return SyncStats(totalTranscriptions: transcriptions.count, newSinceLastSync: 0, notesCreated: 0, notesUpdated: 0, totalDuration: 0)
        }

        // Group by session (within 5 minutes of each other)
        let groups = groupTranscriptions(validTranscriptions)

        let noteService = NoteService(context: context)
        let tagService = TagService(context: context)
        let classificationEngine = ClassificationEngine()

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"

        var notesCreated = 0
        var totalDuration: TimeInterval = 0

        for group in groups {
            if group.count == 1 {
                // Single transcription — create note and classify
                let t = group[0]
                let note = noteService.createNote(title: t.firstSentence, content: t.bestText, paraCategory: .inbox)
                note.noteType = .fleeting
                note.codeStage = .captured
                note.contextNote = "Voice capture via VoiceInk | Duration: \(t.durationFormatted) | Mode: \(t.powerMode ?? "default")"

                // AI classify
                if let result = try? await classificationEngine.classify(title: t.firstSentence, content: t.bestText) {
                    note.paraCategory = result.paraCategory
                    note.noteType = result.noteType
                    note.codeStage = result.codeStage
                    note.aiClassified = true
                    note.aiConfidence = Float(result.confidence)
                    for tagName in result.tags {
                        let tag = tagService.findOrCreate(name: tagName)
                        tagService.addTag(tag, to: note)
                    }
                }

                let voiceinkTag = tagService.findOrCreate(name: "voiceink")
                tagService.addTag(voiceinkTag, to: note)
                let dateTag = tagService.findOrCreate(name: dateFormatter.string(from: t.timestamp))
                tagService.addTag(dateTag, to: note)

                imported.insert(t.id)
                notesCreated += 1
                totalDuration += t.duration
            } else {
                // Multiple transcriptions in a session — merge
                let mergedText = group.map { $0.bestText }.joined(separator: "\n\n")
                let sessionDuration = group.reduce(0) { $0 + $1.duration }
                let sessionStart = group.first?.timestamp ?? Date()

                // Use AI to generate a proper title from merged content
                let client = OpenRouterClient()
                var mergedTitle = group.first?.firstSentence ?? "Voice Session"

                if client.isConfigured {
                    if let (titleResponse, _) = try? await client.send(
                        system: "Generate a concise, proposition-style title (max 80 chars) for the following voice transcription. Respond with ONLY the title, nothing else.",
                        user: String(mergedText.prefix(2000))
                    ) {
                        mergedTitle = titleResponse.trimmingCharacters(in: .whitespacesAndNewlines)
                            .replacingOccurrences(of: "\"", with: "")
                    }
                }

                let note = noteService.createNote(title: mergedTitle, content: mergedText, paraCategory: .inbox)
                note.noteType = .fleeting
                note.codeStage = .captured
                note.contextNote = "Voice session via VoiceInk | \(group.count) fragments | Duration: \(Int(sessionDuration / 60))m \(Int(sessionDuration) % 60)s | Mode: \(group.first?.powerMode ?? "default")"

                // AI classify the merged note
                if let result = try? await classificationEngine.classify(title: mergedTitle, content: mergedText) {
                    note.paraCategory = result.paraCategory
                    note.noteType = result.noteType
                    note.codeStage = result.codeStage
                    note.aiClassified = true
                    note.aiConfidence = Float(result.confidence)
                    for tagName in result.tags {
                        let tag = tagService.findOrCreate(name: tagName)
                        tagService.addTag(tag, to: note)
                    }
                }

                let voiceinkTag = tagService.findOrCreate(name: "voiceink")
                tagService.addTag(voiceinkTag, to: note)
                let sessionTag = tagService.findOrCreate(name: "voiceink-session")
                tagService.addTag(sessionTag, to: note)
                let dateTag = tagService.findOrCreate(name: dateFormatter.string(from: sessionStart))
                tagService.addTag(dateTag, to: note)

                for t in group {
                    imported.insert(t.id)
                    totalDuration += t.duration
                }
                notesCreated += 1
            }
        }

        // Save Core Data context after all note modifications
        if context.hasChanges {
            try? context.save()
        }

        // Save state
        importedPKs = imported
        lastSyncDate = Date()
        UserDefaults.standard.set(lastSyncDate, forKey: Self.lastSyncKey)

        let stats = SyncStats(
            totalTranscriptions: transcriptions.count,
            newSinceLastSync: validTranscriptions.count,
            notesCreated: notesCreated,
            notesUpdated: 0,
            totalDuration: totalDuration
        )
        syncStats = stats

        let dbStats = getStats()
        transcriptionCount = dbStats.count

        logger.info("VoiceInk smart sync complete: \(notesCreated) notes from \(validTranscriptions.count) transcriptions (\(groups.count) groups)")
        return stats
    }

    // MARK: - Grouping

    func groupTranscriptions(_ transcriptions: [VoiceInkTranscription]) -> [[VoiceInkTranscription]] {
        guard !transcriptions.isEmpty else { return [] }

        // Sort by timestamp ascending
        let sorted = transcriptions.sorted { $0.timestamp < $1.timestamp }
        var groups: [[VoiceInkTranscription]] = []
        var currentGroup: [VoiceInkTranscription] = [sorted[0]]

        for i in 1..<sorted.count {
            let prev = sorted[i - 1]
            let current = sorted[i]
            let gap = current.timestamp.timeIntervalSince(prev.timestamp)

            // Group if within 5 minutes and same mode/prompt
            let sameMode = prev.powerMode == current.powerMode
            if gap <= 300 && sameMode {
                currentGroup.append(current)
            } else {
                groups.append(currentGroup)
                currentGroup = [current]
            }
        }
        groups.append(currentGroup)

        return groups
    }

    // MARK: - Import Selected

    @MainActor
    func importTranscriptions(_ transcriptions: [VoiceInkTranscription], context: NSManagedObjectContext) -> Int {
        var imported = importedPKs
        var count = 0

        let noteService = NoteService(context: context)
        let tagService = TagService(context: context)

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"

        for t in transcriptions {
            guard !imported.contains(t.id) else { continue }
            guard t.duration >= 2, t.bestText.count >= 10 else { continue }

            let note = noteService.createNote(title: t.firstSentence, content: t.bestText, paraCategory: .inbox)
            note.noteType = .fleeting
            note.codeStage = .captured
            note.contextNote = "Voice capture via VoiceInk | Duration: \(t.durationFormatted) | Mode: \(t.powerMode ?? "default")"

            let voiceinkTag = tagService.findOrCreate(name: "voiceink")
            tagService.addTag(voiceinkTag, to: note)
            let dateTag = tagService.findOrCreate(name: dateFormatter.string(from: t.timestamp))
            tagService.addTag(dateTag, to: note)

            imported.insert(t.id)
            count += 1
        }

        // Save Core Data context after all note modifications
        if context.hasChanges {
            try? context.save()
        }

        importedPKs = imported
        return count
    }

    // MARK: - SQLite Helpers

    private func columnText(_ stmt: OpaquePointer?, index: Int32) -> String? {
        guard let cString = sqlite3_column_text(stmt, index) else { return nil }
        return String(cString: cString)
    }
}
