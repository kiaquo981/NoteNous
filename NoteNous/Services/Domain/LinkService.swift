import CoreData
import os.log

final class LinkService {
    private let context: NSManagedObjectContext
    private let logger = Logger(subsystem: "com.notenous.app", category: "LinkService")

    init(context: NSManagedObjectContext) {
        self.context = context
    }

    @discardableResult
    func createLink(
        from source: NoteEntity,
        to target: NoteEntity,
        type: LinkType = .reference,
        context linkContext: String? = nil,
        strength: Float = 0.5,
        isAISuggested: Bool = false
    ) -> NoteLinkEntity? {
        guard source.objectID != target.objectID else {
            logger.warning("Cannot link note to itself")
            return nil
        }

        if linkExists(from: source, to: target) {
            logger.info("Link already exists")
            return nil
        }

        let link = NoteLinkEntity(context: context)
        link.id = UUID()
        link.sourceNote = source
        link.targetNote = target
        link.linkType = type
        link.context = linkContext
        link.strength = strength
        link.isAISuggested = isAISuggested
        link.isConfirmed = !isAISuggested
        link.createdAt = Date()

        save()
        logger.info("Created link: \(source.zettelId ?? "?") -> \(target.zettelId ?? "?")")
        return link
    }

    func confirmLink(_ link: NoteLinkEntity) {
        link.isConfirmed = true
        save()
    }

    func rejectLink(_ link: NoteLinkEntity) {
        context.delete(link)
        save()
    }

    func linkExists(from source: NoteEntity, to target: NoteEntity) -> Bool {
        let request = NoteLinkEntity.fetchRequest() as! NSFetchRequest<NoteLinkEntity>
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            NSPredicate(format: "sourceNote == %@", source),
            NSPredicate(format: "targetNote == %@", target)
        ])
        request.fetchLimit = 1
        return ((try? context.count(for: request)) ?? 0) > 0
    }

    func backlinks(for note: NoteEntity) -> [NoteLinkEntity] {
        let request = NoteLinkEntity.fetchRequest() as! NSFetchRequest<NoteLinkEntity>
        request.predicate = NSPredicate(format: "targetNote == %@ AND isConfirmed == YES", note)
        request.sortDescriptors = [NSSortDescriptor(key: "strength", ascending: false)]
        return (try? context.fetch(request)) ?? []
    }

    func suggestedLinks(for note: NoteEntity) -> [NoteLinkEntity] {
        let request = NoteLinkEntity.fetchRequest() as! NSFetchRequest<NoteLinkEntity>
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            NSPredicate(format: "sourceNote == %@ OR targetNote == %@", note, note),
            NSPredicate(format: "isAISuggested == YES AND isConfirmed == NO")
        ])
        request.sortDescriptors = [NSSortDescriptor(key: "strength", ascending: false)]
        return (try? context.fetch(request)) ?? []
    }

    private func save() {
        guard context.hasChanges else { return }
        try? context.save()
    }
}
