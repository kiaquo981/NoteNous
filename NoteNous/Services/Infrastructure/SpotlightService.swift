import CoreData
import CoreSpotlight
import os.log

final class SpotlightService {
    static let shared = SpotlightService()

    private let logger = Logger(subsystem: "com.notenous.app", category: "SpotlightService")
    static let domainIdentifier = "com.notenous.app.notes"

    private init() {}

    // MARK: - Index All

    func indexAllNotes(context: NSManagedObjectContext) {
        let request = NoteEntity.fetchRequest() as! NSFetchRequest<NoteEntity>
        request.predicate = NSPredicate(format: "isArchived == NO")

        do {
            let notes = try context.fetch(request)
            let items = notes.compactMap { searchableItem(for: $0) }
            CSSearchableIndex.default().indexSearchableItems(items) { error in
                if let error = error {
                    self.logger.error("Spotlight indexAll failed: \(error.localizedDescription)")
                } else {
                    self.logger.info("Spotlight indexed \(items.count) notes")
                }
            }
        } catch {
            logger.error("Failed to fetch notes for Spotlight: \(error.localizedDescription)")
        }
    }

    // MARK: - Index Single Note

    func indexNote(_ note: NoteEntity) {
        guard !note.isArchived, let item = searchableItem(for: note) else {
            removeNote(note)
            return
        }
        CSSearchableIndex.default().indexSearchableItems([item]) { error in
            if let error = error {
                self.logger.error("Spotlight index note failed: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Remove Note

    func removeNote(_ note: NoteEntity) {
        guard let noteId = note.id?.uuidString else { return }
        CSSearchableIndex.default().deleteSearchableItems(withIdentifiers: [noteId]) { error in
            if let error = error {
                self.logger.error("Spotlight remove failed: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Remove All

    func removeAllNotes() {
        CSSearchableIndex.default().deleteSearchableItems(withDomainIdentifiers: [Self.domainIdentifier]) { error in
            if let error = error {
                self.logger.error("Spotlight removeAll failed: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Handle Spotlight Result

    /// Returns the note UUID string from a Spotlight user activity, or nil.
    static func noteIdentifier(from userActivity: NSUserActivity) -> String? {
        guard userActivity.activityType == CSSearchableItemActionType else { return nil }
        return userActivity.userInfo?[CSSearchableItemActivityIdentifier] as? String
    }

    // MARK: - Private

    private func searchableItem(for note: NoteEntity) -> CSSearchableItem? {
        guard let noteId = note.id?.uuidString else { return nil }

        let attributes = CSSearchableItemAttributeSet(contentType: .text)
        attributes.title = note.title
        attributes.contentDescription = note.contentPlainText
        attributes.identifier = noteId

        // Custom metadata
        if let zettelId = note.zettelId {
            attributes.keywords = [zettelId]
        }

        // Add tags as keywords
        let tagNames = note.tagsArray.compactMap { $0.name }
        attributes.keywords = (attributes.keywords ?? []) + tagNames

        let item = CSSearchableItem(
            uniqueIdentifier: noteId,
            domainIdentifier: Self.domainIdentifier,
            attributeSet: attributes
        )
        return item
    }
}
