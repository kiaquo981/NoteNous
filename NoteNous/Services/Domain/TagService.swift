import CoreData
import os.log

final class TagService {
    private let context: NSManagedObjectContext
    private let logger = Logger(subsystem: "com.notenous.app", category: "TagService")

    init(context: NSManagedObjectContext) {
        self.context = context
    }

    func findOrCreate(name: String) -> TagEntity {
        let normalized = name.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)

        if let existing = find(name: normalized) {
            return existing
        }

        let tag = TagEntity(context: context)
        tag.id = UUID()
        tag.name = normalized
        tag.usageCount = 0
        tag.createdAt = Date()
        save()
        return tag
    }

    func find(name: String) -> TagEntity? {
        let request = TagEntity.fetchRequest() as! NSFetchRequest<TagEntity>
        request.predicate = NSPredicate(format: "name == %@", name.lowercased())
        request.fetchLimit = 1
        return try? context.fetch(request).first
    }

    func addTag(_ tag: TagEntity, to note: NoteEntity) {
        let mutable = note.mutableSetValue(forKey: "tags")
        mutable.add(tag)
        tag.usageCount += 1
        note.updatedAt = Date()
        save()
    }

    func removeTag(_ tag: TagEntity, from note: NoteEntity) {
        let mutable = note.mutableSetValue(forKey: "tags")
        mutable.remove(tag)
        tag.usageCount = max(0, tag.usageCount - 1)
        note.updatedAt = Date()
        save()
    }

    func topTags(limit: Int = 20) -> [TagEntity] {
        let request = TagEntity.fetchRequest() as! NSFetchRequest<TagEntity>
        request.sortDescriptors = [NSSortDescriptor(key: "usageCount", ascending: false)]
        request.fetchLimit = limit
        return (try? context.fetch(request)) ?? []
    }

    func searchTags(prefix: String) -> [TagEntity] {
        let request = TagEntity.fetchRequest() as! NSFetchRequest<TagEntity>
        request.predicate = NSPredicate(format: "name BEGINSWITH[cd] %@", prefix)
        request.sortDescriptors = [NSSortDescriptor(key: "usageCount", ascending: false)]
        request.fetchLimit = 10
        return (try? context.fetch(request)) ?? []
    }

    private func save() {
        guard context.hasChanges else { return }
        try? context.save()
    }
}
