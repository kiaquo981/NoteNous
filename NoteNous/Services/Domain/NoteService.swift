import CoreData
import os.log

final class NoteService {
    private let context: NSManagedObjectContext
    private let logger = Logger(subsystem: "com.notenous.app", category: "NoteService")

    init(context: NSManagedObjectContext) {
        self.context = context
    }

    @discardableResult
    func createNote(title: String = "", content: String = "", paraCategory: PARACategory = .inbox) -> NoteEntity {
        let note = NoteEntity(context: context)
        note.id = UUID()
        note.zettelId = ZettelIDGenerator.generate()
        note.title = title
        note.content = content
        note.contentPlainText = content.replacingOccurrences(of: #"[#*_`\[\]()]"#, with: "", options: .regularExpression)
        note.paraCategory = paraCategory
        note.codeStage = .captured
        note.noteType = .fleeting
        note.aiClassified = false
        note.aiConfidence = 0
        note.isPinned = false
        note.isArchived = false
        note.createdAt = Date()
        note.updatedAt = Date()

        save()
        logger.info("Created note: \(note.zettelId ?? "unknown")")
        return note
    }

    func updateNote(_ note: NoteEntity, title: String? = nil, content: String? = nil) {
        if let title = title { note.title = title }
        if let content = content {
            note.content = content
            note.contentPlainText = content.replacingOccurrences(of: #"[#*_`\[\]()]"#, with: "", options: .regularExpression)
        }
        note.updatedAt = Date()
        save()
    }

    func archiveNote(_ note: NoteEntity) {
        note.isArchived = true
        note.paraCategory = .archive
        note.archivedAt = Date()
        note.updatedAt = Date()
        save()
    }

    func deleteNote(_ note: NoteEntity) {
        context.delete(note)
        save()
    }

    func togglePin(_ note: NoteEntity) {
        note.isPinned.toggle()
        note.updatedAt = Date()
        save()
    }

    // MARK: - Queries

    func fetchNotes(
        para: PARACategory? = nil,
        codeStage: CODEStage? = nil,
        noteType: NoteType? = nil,
        includeArchived: Bool = false,
        limit: Int = 100,
        offset: Int = 0
    ) -> [NoteEntity] {
        let request = NoteEntity.fetchRequest() as! NSFetchRequest<NoteEntity>
        request.fetchBatchSize = 20
        request.fetchLimit = limit
        request.fetchOffset = offset
        request.sortDescriptors = [
            NSSortDescriptor(key: "isPinned", ascending: false),
            NSSortDescriptor(key: "updatedAt", ascending: false)
        ]

        var predicates: [NSPredicate] = []

        if !includeArchived {
            predicates.append(NSPredicate(format: "isArchived == NO"))
        }
        if let para = para {
            predicates.append(NSPredicate(format: "paraCategoryRaw == %d", para.rawValue))
        }
        if let codeStage = codeStage {
            predicates.append(NSPredicate(format: "codeStageRaw == %d", codeStage.rawValue))
        }
        if let noteType = noteType {
            predicates.append(NSPredicate(format: "noteTypeRaw == %d", noteType.rawValue))
        }

        if !predicates.isEmpty {
            request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: predicates)
        }

        do {
            return try context.fetch(request)
        } catch {
            logger.error("Failed to fetch notes: \(error.localizedDescription)")
            return []
        }
    }

    func searchNotes(query: String) -> [NoteEntity] {
        guard !query.isEmpty else { return fetchNotes() }

        let request = NoteEntity.fetchRequest() as! NSFetchRequest<NoteEntity>
        request.fetchBatchSize = 20
        request.fetchLimit = 50
        request.sortDescriptors = [NSSortDescriptor(key: "updatedAt", ascending: false)]
        request.predicate = NSCompoundPredicate(orPredicateWithSubpredicates: [
            NSPredicate(format: "title CONTAINS[cd] %@", query),
            NSPredicate(format: "contentPlainText CONTAINS[cd] %@", query),
            NSPredicate(format: "zettelId CONTAINS[cd] %@", query)
        ])

        do {
            return try context.fetch(request)
        } catch {
            logger.error("Search failed: \(error.localizedDescription)")
            return []
        }
    }

    func countNotes(para: PARACategory? = nil, codeStage: CODEStage? = nil, noteType: NoteType? = nil) -> Int {
        let request = NoteEntity.fetchRequest() as! NSFetchRequest<NoteEntity>
        var predicates = [NSPredicate(format: "isArchived == NO")]

        if let para = para {
            predicates.append(NSPredicate(format: "paraCategoryRaw == %d", para.rawValue))
        }
        if let codeStage = codeStage {
            predicates.append(NSPredicate(format: "codeStageRaw == %d", codeStage.rawValue))
        }
        if let noteType = noteType {
            predicates.append(NSPredicate(format: "noteTypeRaw == %d", noteType.rawValue))
        }

        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: predicates)

        do {
            return try context.count(for: request)
        } catch {
            return 0
        }
    }

    func findByZettelId(_ zettelId: String) -> NoteEntity? {
        let request = NoteEntity.fetchRequest() as! NSFetchRequest<NoteEntity>
        request.predicate = NSPredicate(format: "zettelId == %@", zettelId)
        request.fetchLimit = 1
        return try? context.fetch(request).first
    }

    // MARK: - Private

    private func save() {
        guard context.hasChanges else { return }
        do {
            try context.save()
        } catch {
            logger.error("Save failed: \(error.localizedDescription)")
        }
    }
}
