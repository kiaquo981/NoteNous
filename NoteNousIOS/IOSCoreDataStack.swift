import CoreData
import os.log

final class IOSCoreDataStack: ObservableObject {
    static let shared = IOSCoreDataStack()

    private let logger = Logger(subsystem: "com.notenous.ios", category: "CoreData")
    @Published var loadError: String?

    lazy var persistentContainer: NSPersistentCloudKitContainer = {
        let container = NSPersistentCloudKitContainer(name: "NoteNous", managedObjectModel: CoreDataStack.model)

        let cloudKitDescription = NSPersistentStoreDescription()
        cloudKitDescription.url = Self.storeURL
        cloudKitDescription.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
        cloudKitDescription.setOption(true as NSNumber, forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)

        // CloudKit configuration
        cloudKitDescription.cloudKitContainerOptions = NSPersistentCloudKitContainerOptions(
            containerIdentifier: "iCloud.com.notenous.app"
        )

        // Fallback local-only description (no CloudKit)
        let localDescription = NSPersistentStoreDescription()
        localDescription.url = Self.storeURL
        localDescription.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
        localDescription.cloudKitContainerOptions = nil

        container.persistentStoreDescriptions = [cloudKitDescription]

        container.loadPersistentStores { [weak self] description, error in
            guard let self = self else { return }
            if let error = error as NSError? {
                self.logger.error("Core Data CloudKit store failed to load: \(error.localizedDescription)")

                // Retry with local-only fallback (no CloudKit)
                self.logger.info("Retrying with local-only store (no CloudKit)...")
                container.persistentStoreDescriptions = [localDescription]
                container.loadPersistentStores { fallbackDescription, fallbackError in
                    if let fallbackError = fallbackError as NSError? {
                        self.logger.error("Local-only Core Data store also failed: \(fallbackError.localizedDescription)")
                        DispatchQueue.main.async {
                            self.loadError = "Core Data failed to load: \(fallbackError.localizedDescription)"
                        }
                    } else {
                        self.logger.info("Local-only Core Data store loaded at \(fallbackDescription.url?.absoluteString ?? "unknown")")
                    }
                }
                return
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
