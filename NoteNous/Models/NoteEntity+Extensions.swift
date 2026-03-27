import CoreData

@objc(NoteEntity)
public class NoteEntity: NSManagedObject {
    @NSManaged public var id: UUID?
    @NSManaged public var zettelId: String?
    @NSManaged public var title: String
    @NSManaged public var content: String
    @NSManaged public var contentPlainText: String
    @NSManaged public var paraCategoryRaw: Int16
    @NSManaged public var codeStageRaw: Int16
    @NSManaged public var noteTypeRaw: Int16
    @NSManaged public var sourceURL: String?
    @NSManaged public var sourceTitle: String?
    @NSManaged public var aiClassified: Bool
    @NSManaged public var aiConfidence: Float
    @NSManaged public var positionX: Double
    @NSManaged public var positionY: Double
    @NSManaged public var colorHex: String?
    @NSManaged public var isPinned: Bool
    @NSManaged public var isArchived: Bool
    @NSManaged public var createdAt: Date?
    @NSManaged public var updatedAt: Date?
    @NSManaged public var archivedAt: Date?
    @NSManaged public var contextNote: String?

    @NSManaged public var tags: NSSet?
    @NSManaged public var concepts: NSSet?
    @NSManaged public var outgoingLinks: NSSet?
    @NSManaged public var incomingLinks: NSSet?
    @NSManaged public var project: ProjectEntity?
    @NSManaged public var area: AreaEntity?
    @NSManaged public var aiRequests: NSSet?

    var paraCategory: PARACategory {
        get { PARACategory(rawValue: paraCategoryRaw) ?? .inbox }
        set { paraCategoryRaw = newValue.rawValue }
    }

    var codeStage: CODEStage {
        get { CODEStage(rawValue: codeStageRaw) ?? .captured }
        set { codeStageRaw = newValue.rawValue }
    }

    var noteType: NoteType {
        get { NoteType(rawValue: noteTypeRaw) ?? .fleeting }
        set { noteTypeRaw = newValue.rawValue }
    }

    var tagsArray: [TagEntity] {
        (tags?.allObjects as? [TagEntity]) ?? []
    }

    var conceptsArray: [ConceptEntity] {
        (concepts?.allObjects as? [ConceptEntity]) ?? []
    }

    var outgoingLinksArray: [NoteLinkEntity] {
        (outgoingLinks?.allObjects as? [NoteLinkEntity]) ?? []
    }

    var incomingLinksArray: [NoteLinkEntity] {
        (incomingLinks?.allObjects as? [NoteLinkEntity]) ?? []
    }

    var totalLinkCount: Int {
        outgoingLinksArray.count + incomingLinksArray.count
    }
}

@objc(TagEntity)
public class TagEntity: NSManagedObject {
    @NSManaged public var id: UUID?
    @NSManaged public var name: String?
    @NSManaged public var colorHex: String?
    @NSManaged public var usageCount: Int32
    @NSManaged public var createdAt: Date?
    @NSManaged public var notes: NSSet?
}

@objc(ConceptEntity)
public class ConceptEntity: NSManagedObject {
    @NSManaged public var id: UUID?
    @NSManaged public var name: String?
    @NSManaged public var definition: String?
    @NSManaged public var usageCount: Int32
    @NSManaged public var createdAt: Date?
    @NSManaged public var notes: NSSet?
    @NSManaged public var relatedConcepts: NSSet?
    @NSManaged public var relatedBy: NSSet?
}

@objc(NoteLinkEntity)
public class NoteLinkEntity: NSManagedObject {
    @NSManaged public var id: UUID?
    @NSManaged public var linkTypeRaw: Int16
    @NSManaged public var context: String?
    @NSManaged public var strength: Float
    @NSManaged public var isAISuggested: Bool
    @NSManaged public var isConfirmed: Bool
    @NSManaged public var createdAt: Date?
    @NSManaged public var sourceNote: NoteEntity?
    @NSManaged public var targetNote: NoteEntity?

    var linkType: LinkType {
        get { LinkType(rawValue: linkTypeRaw) ?? .reference }
        set { linkTypeRaw = newValue.rawValue }
    }
}

@objc(ProjectEntity)
public class ProjectEntity: NSManagedObject {
    @NSManaged public var id: UUID?
    @NSManaged public var name: String?
    @NSManaged public var desc: String?
    @NSManaged public var statusRaw: Int16
    @NSManaged public var deadline: Date?
    @NSManaged public var sortOrder: Int32
    @NSManaged public var createdAt: Date?
    @NSManaged public var completedAt: Date?
    @NSManaged public var notes: NSSet?
    @NSManaged public var area: AreaEntity?
}

@objc(AreaEntity)
public class AreaEntity: NSManagedObject {
    @NSManaged public var id: UUID?
    @NSManaged public var name: String?
    @NSManaged public var desc: String?
    @NSManaged public var iconName: String?
    @NSManaged public var sortOrder: Int32
    @NSManaged public var createdAt: Date?
    @NSManaged public var notes: NSSet?
    @NSManaged public var projects: NSSet?
}

@objc(AIRequestEntity)
public class AIRequestEntity: NSManagedObject {
    @NSManaged public var id: UUID?
    @NSManaged public var requestTypeRaw: Int16
    @NSManaged public var statusRaw: Int16
    @NSManaged public var requestPayload: Data?
    @NSManaged public var responsePayload: Data?
    @NSManaged public var model: String?
    @NSManaged public var tokensUsed: Int32
    @NSManaged public var costCents: Float
    @NSManaged public var errorMessage: String?
    @NSManaged public var retryCount: Int16
    @NSManaged public var createdAt: Date?
    @NSManaged public var completedAt: Date?
    @NSManaged public var note: NoteEntity?
}
