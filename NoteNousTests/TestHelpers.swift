import XCTest
import CoreData
@testable import NoteNous

class NoteNousTestCase: XCTestCase {
    var context: NSManagedObjectContext!

    override func setUp() {
        super.setUp()
        let container = NSPersistentContainer(name: "NoteNous", managedObjectModel: CoreDataStack.model)
        let description = NSPersistentStoreDescription()
        description.type = NSInMemoryStoreType
        container.persistentStoreDescriptions = [description]
        container.loadPersistentStores { _, error in
            XCTAssertNil(error)
        }
        context = container.viewContext
    }

    override func tearDown() {
        context = nil
        super.tearDown()
    }

    // Helper to create a test note with save
    @discardableResult
    func createNote(title: String = "Test", content: String = "Content", type: NoteType = .fleeting) -> NoteEntity {
        let service = NoteService(context: context)
        let note = service.createNote(title: title, content: content)
        note.noteType = type
        try? context.save()
        return note
    }

    // Helper to generate filler text with a specific word count
    func words(_ count: Int) -> String {
        Array(repeating: "word", count: count).joined(separator: " ")
    }
}
