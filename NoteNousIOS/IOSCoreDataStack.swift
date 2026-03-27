import CoreData
import os.log

final class IOSCoreDataStack: ObservableObject {
    static let shared = IOSCoreDataStack()

    private let logger = Logger(subsystem: "com.notenous.ios", category: "CoreData")

    lazy var persistentContainer: NSPersistentCloudKitContainer = {
        let container = NSPersistentCloudKitContainer(name: "NoteNous", managedObjectModel: CoreDataStack.model)

        let description = NSPersistentStoreDescription()
        description.url = Self.storeURL
        description.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
        description.setOption(true as NSNumber, forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)

        // CloudKit configuration
        description.cloudKitContainerOptions = NSPersistentCloudKitContainerOptions(
            containerIdentifier: "iCloud.com.notenous.app"
        )

        container.persistentStoreDescriptions = [description]

        container.loadPersistentStores { description, error in
            if let error = error as NSError? {
                self.logger.error("Core Data store failed to load: \(error.localizedDescription)")
                fatalError("Core Data store failed: \(error)")
            }
            self.logger.info("Core Data store loaded at \(description.url?.absoluteString ?? "unknown")")
        }

        container.viewContext.automaticallyMergesChangesFromParent = true
        container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy

        return container
    }()

    var viewContext: NSManagedObjectContext {
        persistentContainer.viewContext
    }

    func newBackgroundContext() -> NSManagedObjectContext {
        let context = persistentContainer.newBackgroundContext()
        context.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        return context
    }

    func save() {
        let context = viewContext
        guard context.hasChanges else { return }
        do {
            try context.save()
        } catch {
            logger.error("Failed to save context: \(error.localizedDescription)")
        }
    }

    // MARK: - Store URL

    private static var storeURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("NoteNous", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("NoteNous.sqlite")
    }
}
