import CoreData
import os.log

final class CoreDataStack: ObservableObject {
    static let shared = CoreDataStack()

    private let logger = Logger(subsystem: "com.notenous.app", category: "CoreData")

    lazy var persistentContainer: NSPersistentContainer = {
        let container = NSPersistentContainer(name: "NoteNous", managedObjectModel: Self.model)

        let description = NSPersistentStoreDescription()
        description.url = Self.storeURL
        description.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
        description.setOption(true as NSNumber, forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)
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
        container.viewContext.undoManager = UndoManager()

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

    // MARK: - Programmatic Model

    static let model: NSManagedObjectModel = {
        let model = NSManagedObjectModel()

        // --- Note Entity ---
        let noteEntity = NSEntityDescription()
        noteEntity.name = "NoteEntity"
        noteEntity.managedObjectClassName = "NoteEntity"

        let noteId = NSAttributeDescription.attribute(name: "id", type: .UUIDAttributeType)
        let zettelId = NSAttributeDescription.attribute(name: "zettelId", type: .stringAttributeType)
        let title = NSAttributeDescription.attribute(name: "title", type: .stringAttributeType, defaultValue: "")
        let content = NSAttributeDescription.attribute(name: "content", type: .stringAttributeType, defaultValue: "")
        let contentPlainText = NSAttributeDescription.attribute(name: "contentPlainText", type: .stringAttributeType, defaultValue: "")
        let paraCategory = NSAttributeDescription.attribute(name: "paraCategoryRaw", type: .integer16AttributeType, defaultValue: Int16(0))
        let codeStage = NSAttributeDescription.attribute(name: "codeStageRaw", type: .integer16AttributeType, defaultValue: Int16(0))
        let noteType = NSAttributeDescription.attribute(name: "noteTypeRaw", type: .integer16AttributeType, defaultValue: Int16(0))
        let sourceURL = NSAttributeDescription.optionalAttribute(name: "sourceURL", type: .stringAttributeType)
        let sourceTitle = NSAttributeDescription.optionalAttribute(name: "sourceTitle", type: .stringAttributeType)
        let aiClassified = NSAttributeDescription.attribute(name: "aiClassified", type: .booleanAttributeType, defaultValue: false)
        let aiConfidence = NSAttributeDescription.attribute(name: "aiConfidence", type: .floatAttributeType, defaultValue: Float(0))
        let positionX = NSAttributeDescription.attribute(name: "positionX", type: .doubleAttributeType, defaultValue: Double(0))
        let positionY = NSAttributeDescription.attribute(name: "positionY", type: .doubleAttributeType, defaultValue: Double(0))
        let colorHex = NSAttributeDescription.optionalAttribute(name: "colorHex", type: .stringAttributeType)
        let isPinned = NSAttributeDescription.attribute(name: "isPinned", type: .booleanAttributeType, defaultValue: false)
        let isArchived = NSAttributeDescription.attribute(name: "isArchived", type: .booleanAttributeType, defaultValue: false)
        let createdAt = NSAttributeDescription.attribute(name: "createdAt", type: .dateAttributeType)
        let updatedAt = NSAttributeDescription.attribute(name: "updatedAt", type: .dateAttributeType)
        let archivedAt = NSAttributeDescription.optionalAttribute(name: "archivedAt", type: .dateAttributeType)

        noteEntity.properties = [
            noteId, zettelId, title, content, contentPlainText,
            paraCategory, codeStage, noteType,
            sourceURL, sourceTitle,
            aiClassified, aiConfidence,
            positionX, positionY, colorHex,
            isPinned, isArchived,
            createdAt, updatedAt, archivedAt
        ]

        // --- Tag Entity ---
        let tagEntity = NSEntityDescription()
        tagEntity.name = "TagEntity"
        tagEntity.managedObjectClassName = "TagEntity"

        let tagId = NSAttributeDescription.attribute(name: "id", type: .UUIDAttributeType)
        let tagName = NSAttributeDescription.attribute(name: "name", type: .stringAttributeType)
        let tagColorHex = NSAttributeDescription.optionalAttribute(name: "colorHex", type: .stringAttributeType)
        let tagUsageCount = NSAttributeDescription.attribute(name: "usageCount", type: .integer32AttributeType, defaultValue: Int32(0))
        let tagCreatedAt = NSAttributeDescription.attribute(name: "createdAt", type: .dateAttributeType)

        tagEntity.properties = [tagId, tagName, tagColorHex, tagUsageCount, tagCreatedAt]

        // --- Concept Entity ---
        let conceptEntity = NSEntityDescription()
        conceptEntity.name = "ConceptEntity"
        conceptEntity.managedObjectClassName = "ConceptEntity"

        let conceptId = NSAttributeDescription.attribute(name: "id", type: .UUIDAttributeType)
        let conceptName = NSAttributeDescription.attribute(name: "name", type: .stringAttributeType)
        let conceptDef = NSAttributeDescription.optionalAttribute(name: "definition", type: .stringAttributeType)
        let conceptUsage = NSAttributeDescription.attribute(name: "usageCount", type: .integer32AttributeType, defaultValue: Int32(0))
        let conceptCreatedAt = NSAttributeDescription.attribute(name: "createdAt", type: .dateAttributeType)

        conceptEntity.properties = [conceptId, conceptName, conceptDef, conceptUsage, conceptCreatedAt]

        // --- NoteLink Entity ---
        let linkEntity = NSEntityDescription()
        linkEntity.name = "NoteLinkEntity"
        linkEntity.managedObjectClassName = "NoteLinkEntity"

        let linkId = NSAttributeDescription.attribute(name: "id", type: .UUIDAttributeType)
        let linkTypeAttr = NSAttributeDescription.attribute(name: "linkTypeRaw", type: .integer16AttributeType, defaultValue: Int16(0))
        let linkContext = NSAttributeDescription.optionalAttribute(name: "context", type: .stringAttributeType)
        let linkStrength = NSAttributeDescription.attribute(name: "strength", type: .floatAttributeType, defaultValue: Float(0.5))
        let linkAISuggested = NSAttributeDescription.attribute(name: "isAISuggested", type: .booleanAttributeType, defaultValue: false)
        let linkConfirmed = NSAttributeDescription.attribute(name: "isConfirmed", type: .booleanAttributeType, defaultValue: false)
        let linkCreatedAt = NSAttributeDescription.attribute(name: "createdAt", type: .dateAttributeType)

        linkEntity.properties = [linkId, linkTypeAttr, linkContext, linkStrength, linkAISuggested, linkConfirmed, linkCreatedAt]

        // --- Project Entity ---
        let projectEntity = NSEntityDescription()
        projectEntity.name = "ProjectEntity"
        projectEntity.managedObjectClassName = "ProjectEntity"

        let projId = NSAttributeDescription.attribute(name: "id", type: .UUIDAttributeType)
        let projName = NSAttributeDescription.attribute(name: "name", type: .stringAttributeType)
        let projDesc = NSAttributeDescription.optionalAttribute(name: "desc", type: .stringAttributeType)
        let projStatus = NSAttributeDescription.attribute(name: "statusRaw", type: .integer16AttributeType, defaultValue: Int16(0))
        let projDeadline = NSAttributeDescription.optionalAttribute(name: "deadline", type: .dateAttributeType)
        let projSort = NSAttributeDescription.attribute(name: "sortOrder", type: .integer32AttributeType, defaultValue: Int32(0))
        let projCreatedAt = NSAttributeDescription.attribute(name: "createdAt", type: .dateAttributeType)
        let projCompletedAt = NSAttributeDescription.optionalAttribute(name: "completedAt", type: .dateAttributeType)

        projectEntity.properties = [projId, projName, projDesc, projStatus, projDeadline, projSort, projCreatedAt, projCompletedAt]

        // --- Area Entity ---
        let areaEntity = NSEntityDescription()
        areaEntity.name = "AreaEntity"
        areaEntity.managedObjectClassName = "AreaEntity"

        let areaId = NSAttributeDescription.attribute(name: "id", type: .UUIDAttributeType)
        let areaName = NSAttributeDescription.attribute(name: "name", type: .stringAttributeType)
        let areaDesc = NSAttributeDescription.optionalAttribute(name: "desc", type: .stringAttributeType)
        let areaIcon = NSAttributeDescription.optionalAttribute(name: "iconName", type: .stringAttributeType)
        let areaSort = NSAttributeDescription.attribute(name: "sortOrder", type: .integer32AttributeType, defaultValue: Int32(0))
        let areaCreatedAt = NSAttributeDescription.attribute(name: "createdAt", type: .dateAttributeType)

        areaEntity.properties = [areaId, areaName, areaDesc, areaIcon, areaSort, areaCreatedAt]

        // --- AIRequest Entity ---
        let aiRequestEntity = NSEntityDescription()
        aiRequestEntity.name = "AIRequestEntity"
        aiRequestEntity.managedObjectClassName = "AIRequestEntity"

        let aiReqId = NSAttributeDescription.attribute(name: "id", type: .UUIDAttributeType)
        let aiReqType = NSAttributeDescription.attribute(name: "requestTypeRaw", type: .integer16AttributeType, defaultValue: Int16(0))
        let aiReqStatus = NSAttributeDescription.attribute(name: "statusRaw", type: .integer16AttributeType, defaultValue: Int16(0))
        let aiReqPayload = NSAttributeDescription.optionalAttribute(name: "requestPayload", type: .binaryDataAttributeType)
        let aiReqResponse = NSAttributeDescription.optionalAttribute(name: "responsePayload", type: .binaryDataAttributeType)
        let aiReqModel = NSAttributeDescription.optionalAttribute(name: "model", type: .stringAttributeType)
        let aiReqTokens = NSAttributeDescription.attribute(name: "tokensUsed", type: .integer32AttributeType, defaultValue: Int32(0))
        let aiReqCost = NSAttributeDescription.attribute(name: "costCents", type: .floatAttributeType, defaultValue: Float(0))
        let aiReqError = NSAttributeDescription.optionalAttribute(name: "errorMessage", type: .stringAttributeType)
        let aiReqRetry = NSAttributeDescription.attribute(name: "retryCount", type: .integer16AttributeType, defaultValue: Int16(0))
        let aiReqCreatedAt = NSAttributeDescription.attribute(name: "createdAt", type: .dateAttributeType)
        let aiReqCompletedAt = NSAttributeDescription.optionalAttribute(name: "completedAt", type: .dateAttributeType)

        aiRequestEntity.properties = [
            aiReqId, aiReqType, aiReqStatus, aiReqPayload, aiReqResponse,
            aiReqModel, aiReqTokens, aiReqCost, aiReqError, aiReqRetry,
            aiReqCreatedAt, aiReqCompletedAt
        ]

        // --- Relationships ---

        // Note <-> Tag (many-to-many)
        let noteTagsRel = NSRelationshipDescription()
        noteTagsRel.name = "tags"
        noteTagsRel.destinationEntity = tagEntity
        noteTagsRel.isOptional = true
        noteTagsRel.maxCount = 0 // to-many
        noteTagsRel.deleteRule = .nullifyDeleteRule

        let tagNotesRel = NSRelationshipDescription()
        tagNotesRel.name = "notes"
        tagNotesRel.destinationEntity = noteEntity
        tagNotesRel.isOptional = true
        tagNotesRel.maxCount = 0
        tagNotesRel.deleteRule = .nullifyDeleteRule

        noteTagsRel.inverseRelationship = tagNotesRel
        tagNotesRel.inverseRelationship = noteTagsRel

        // Note <-> Concept (many-to-many)
        let noteConceptsRel = NSRelationshipDescription()
        noteConceptsRel.name = "concepts"
        noteConceptsRel.destinationEntity = conceptEntity
        noteConceptsRel.isOptional = true
        noteConceptsRel.maxCount = 0
        noteConceptsRel.deleteRule = .nullifyDeleteRule

        let conceptNotesRel = NSRelationshipDescription()
        conceptNotesRel.name = "notes"
        conceptNotesRel.destinationEntity = noteEntity
        conceptNotesRel.isOptional = true
        conceptNotesRel.maxCount = 0
        conceptNotesRel.deleteRule = .nullifyDeleteRule

        noteConceptsRel.inverseRelationship = conceptNotesRel
        conceptNotesRel.inverseRelationship = noteConceptsRel

        // Concept <-> Concept (many-to-many, self-referential)
        let conceptRelatedRel = NSRelationshipDescription()
        conceptRelatedRel.name = "relatedConcepts"
        conceptRelatedRel.destinationEntity = conceptEntity
        conceptRelatedRel.isOptional = true
        conceptRelatedRel.maxCount = 0
        conceptRelatedRel.deleteRule = .nullifyDeleteRule

        let conceptRelatedByRel = NSRelationshipDescription()
        conceptRelatedByRel.name = "relatedBy"
        conceptRelatedByRel.destinationEntity = conceptEntity
        conceptRelatedByRel.isOptional = true
        conceptRelatedByRel.maxCount = 0
        conceptRelatedByRel.deleteRule = .nullifyDeleteRule

        conceptRelatedRel.inverseRelationship = conceptRelatedByRel
        conceptRelatedByRel.inverseRelationship = conceptRelatedRel

        // Note -> NoteLink (outgoing)
        let noteOutLinksRel = NSRelationshipDescription()
        noteOutLinksRel.name = "outgoingLinks"
        noteOutLinksRel.destinationEntity = linkEntity
        noteOutLinksRel.isOptional = true
        noteOutLinksRel.maxCount = 0
        noteOutLinksRel.deleteRule = .cascadeDeleteRule

        let linkSourceRel = NSRelationshipDescription()
        linkSourceRel.name = "sourceNote"
        linkSourceRel.destinationEntity = noteEntity
        linkSourceRel.isOptional = false
        linkSourceRel.maxCount = 1
        linkSourceRel.deleteRule = .nullifyDeleteRule

        noteOutLinksRel.inverseRelationship = linkSourceRel
        linkSourceRel.inverseRelationship = noteOutLinksRel

        // Note -> NoteLink (incoming)
        let noteInLinksRel = NSRelationshipDescription()
        noteInLinksRel.name = "incomingLinks"
        noteInLinksRel.destinationEntity = linkEntity
        noteInLinksRel.isOptional = true
        noteInLinksRel.maxCount = 0
        noteInLinksRel.deleteRule = .cascadeDeleteRule

        let linkTargetRel = NSRelationshipDescription()
        linkTargetRel.name = "targetNote"
        linkTargetRel.destinationEntity = noteEntity
        linkTargetRel.isOptional = false
        linkTargetRel.maxCount = 1
        linkTargetRel.deleteRule = .nullifyDeleteRule

        noteInLinksRel.inverseRelationship = linkTargetRel
        linkTargetRel.inverseRelationship = noteInLinksRel

        // Note -> Project
        let noteProjectRel = NSRelationshipDescription()
        noteProjectRel.name = "project"
        noteProjectRel.destinationEntity = projectEntity
        noteProjectRel.isOptional = true
        noteProjectRel.maxCount = 1
        noteProjectRel.deleteRule = .nullifyDeleteRule

        let projectNotesRel = NSRelationshipDescription()
        projectNotesRel.name = "notes"
        projectNotesRel.destinationEntity = noteEntity
        projectNotesRel.isOptional = true
        projectNotesRel.maxCount = 0
        projectNotesRel.deleteRule = .nullifyDeleteRule

        noteProjectRel.inverseRelationship = projectNotesRel
        projectNotesRel.inverseRelationship = noteProjectRel

        // Note -> Area
        let noteAreaRel = NSRelationshipDescription()
        noteAreaRel.name = "area"
        noteAreaRel.destinationEntity = areaEntity
        noteAreaRel.isOptional = true
        noteAreaRel.maxCount = 1
        noteAreaRel.deleteRule = .nullifyDeleteRule

        let areaNotesRel = NSRelationshipDescription()
        areaNotesRel.name = "notes"
        areaNotesRel.destinationEntity = noteEntity
        areaNotesRel.isOptional = true
        areaNotesRel.maxCount = 0
        areaNotesRel.deleteRule = .nullifyDeleteRule

        noteAreaRel.inverseRelationship = areaNotesRel
        areaNotesRel.inverseRelationship = noteAreaRel

        // Project -> Area
        let projAreaRel = NSRelationshipDescription()
        projAreaRel.name = "area"
        projAreaRel.destinationEntity = areaEntity
        projAreaRel.isOptional = true
        projAreaRel.maxCount = 1
        projAreaRel.deleteRule = .nullifyDeleteRule

        let areaProjectsRel = NSRelationshipDescription()
        areaProjectsRel.name = "projects"
        areaProjectsRel.destinationEntity = projectEntity
        areaProjectsRel.isOptional = true
        areaProjectsRel.maxCount = 0
        areaProjectsRel.deleteRule = .nullifyDeleteRule

        projAreaRel.inverseRelationship = areaProjectsRel
        areaProjectsRel.inverseRelationship = projAreaRel

        // Note -> AIRequest
        let noteAIReqRel = NSRelationshipDescription()
        noteAIReqRel.name = "aiRequests"
        noteAIReqRel.destinationEntity = aiRequestEntity
        noteAIReqRel.isOptional = true
        noteAIReqRel.maxCount = 0
        noteAIReqRel.deleteRule = .cascadeDeleteRule

        let aiReqNoteRel = NSRelationshipDescription()
        aiReqNoteRel.name = "note"
        aiReqNoteRel.destinationEntity = noteEntity
        aiReqNoteRel.isOptional = false
        aiReqNoteRel.maxCount = 1
        aiReqNoteRel.deleteRule = .nullifyDeleteRule

        noteAIReqRel.inverseRelationship = aiReqNoteRel
        aiReqNoteRel.inverseRelationship = noteAIReqRel

        // Assign all relationships
        noteEntity.properties.append(contentsOf: [
            noteTagsRel, noteConceptsRel, noteOutLinksRel, noteInLinksRel,
            noteProjectRel, noteAreaRel, noteAIReqRel
        ])
        tagEntity.properties.append(tagNotesRel)
        conceptEntity.properties.append(contentsOf: [conceptNotesRel, conceptRelatedRel, conceptRelatedByRel])
        linkEntity.properties.append(contentsOf: [linkSourceRel, linkTargetRel])
        projectEntity.properties.append(contentsOf: [projectNotesRel, projAreaRel])
        areaEntity.properties.append(contentsOf: [areaNotesRel, areaProjectsRel])
        aiRequestEntity.properties.append(aiReqNoteRel)

        model.entities = [noteEntity, tagEntity, conceptEntity, linkEntity, projectEntity, areaEntity, aiRequestEntity]

        return model
    }()
}

// MARK: - NSAttributeDescription Helpers

extension NSAttributeDescription {
    static func attribute(name: String, type: NSAttributeType, defaultValue: Any? = nil) -> NSAttributeDescription {
        let attr = NSAttributeDescription()
        attr.name = name
        attr.attributeType = type
        attr.isOptional = false
        attr.defaultValue = defaultValue
        return attr
    }

    static func optionalAttribute(name: String, type: NSAttributeType) -> NSAttributeDescription {
        let attr = NSAttributeDescription()
        attr.name = name
        attr.attributeType = type
        attr.isOptional = true
        return attr
    }
}
