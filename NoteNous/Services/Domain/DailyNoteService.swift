import CoreData
import os.log

final class DailyNoteService {
    private let context: NSManagedObjectContext
    private let logger = Logger(subsystem: "com.notenous.app", category: "DailyNoteService")

    private static let titleDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()

    private static let dailyTemplate = """
    # Daily Note

    ## Captures

    ## Tasks

    ## Reflections

    """

    init(context: NSManagedObjectContext) {
        self.context = context
    }

    /// Returns today's daily note, creating it if it doesn't exist.
    @discardableResult
    func todayNote() -> NoteEntity {
        let todayTitle = Self.titleDateFormatter.string(from: Date())
        return noteForDate(title: todayTitle)
    }

    /// Returns the daily note for a specific date title (YYYY-MM-DD).
    private func noteForDate(title: String) -> NoteEntity {
        // Try to find existing
        if let existing = findDailyNote(title: title) {
            return existing
        }

        // Create new daily note
        let noteService = NoteService(context: context)
        let note = noteService.createNote(
            title: title,
            content: Self.dailyTemplate,
            paraCategory: .area
        )

        // Tag with "daily"
        let tagService = TagService(context: context)
        let dailyTag = tagService.findOrCreate(name: "daily")
        tagService.addTag(dailyTag, to: note)

        logger.info("Created daily note: \(title)")
        return note
    }

    private func findDailyNote(title: String) -> NoteEntity? {
        let request = NoteEntity.fetchRequest() as! NSFetchRequest<NoteEntity>
        request.predicate = NSPredicate(format: "title == %@", title)
        request.fetchLimit = 1

        do {
            return try context.fetch(request).first
        } catch {
            logger.error("Failed to find daily note: \(error.localizedDescription)")
            return nil
        }
    }

    /// Returns today's date number as a string (e.g., "26").
    static var todayDateNumber: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "d"
        return formatter.string(from: Date())
    }
}
