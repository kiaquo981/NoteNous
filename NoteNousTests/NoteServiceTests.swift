import XCTest
import CoreData
@testable import NoteNous

final class NoteServiceTests: NoteNousTestCase {

    private var sut: NoteService!

    override func setUp() {
        super.setUp()
        sut = NoteService(context: context)
    }

    override func tearDown() {
        sut = nil
        super.tearDown()
    }

    // MARK: - createNote

    func testCreateNote_hasRequiredFields() {
        let note = sut.createNote(title: "My Note", content: "Some content")

        XCTAssertNotNil(note.id)
        XCTAssertNotNil(note.zettelId)
        XCTAssertEqual(note.title, "My Note")
        XCTAssertEqual(note.content, "Some content")
        XCTAssertNotNil(note.createdAt)
        XCTAssertNotNil(note.updatedAt)
        XCTAssertFalse(note.isPinned)
        XCTAssertFalse(note.isArchived)
        XCTAssertEqual(note.paraCategory, .inbox)
        XCTAssertEqual(note.codeStage, .captured)
        XCTAssertEqual(note.noteType, .fleeting)
    }

    func testCreateNote_stripsMarkdownForPlainText() {
        let note = sut.createNote(title: "T", content: "**bold** and [link](url)")
        // Markdown chars removed from plaintext
        XCTAssertFalse(note.contentPlainText.contains("*"))
        XCTAssertFalse(note.contentPlainText.contains("["))
        XCTAssertFalse(note.contentPlainText.contains("]"))
    }

    // MARK: - updateNote

    func testUpdateNote_changesFields() {
        let note = sut.createNote(title: "Old", content: "Old content")
        let originalUpdatedAt = note.updatedAt

        // Small delay to ensure updatedAt changes
        RunLoop.current.run(until: Date().addingTimeInterval(0.01))

        sut.updateNote(note, title: "New", content: "New content")

        XCTAssertEqual(note.title, "New")
        XCTAssertEqual(note.content, "New content")
        XCTAssertNotEqual(note.updatedAt, originalUpdatedAt)
    }

    func testUpdateNote_partialUpdate() {
        let note = sut.createNote(title: "Title", content: "Content")
        sut.updateNote(note, title: "Updated Title")

        XCTAssertEqual(note.title, "Updated Title")
        XCTAssertEqual(note.content, "Content") // unchanged
    }

    // MARK: - archiveNote

    func testArchiveNote() {
        let note = sut.createNote(title: "Test")
        sut.archiveNote(note)

        XCTAssertTrue(note.isArchived)
        XCTAssertEqual(note.paraCategory, .archive)
        XCTAssertNotNil(note.archivedAt)
    }

    // MARK: - deleteNote

    func testDeleteNote() {
        let note = sut.createNote(title: "To Delete")
        let objectID = note.objectID

        sut.deleteNote(note)

        let fetched = try? context.existingObject(with: objectID)
        XCTAssertTrue(fetched == nil || fetched!.isDeleted)
    }

    // MARK: - togglePin

    func testTogglePin() {
        let note = sut.createNote(title: "Test")
        XCTAssertFalse(note.isPinned)

        sut.togglePin(note)
        XCTAssertTrue(note.isPinned)

        sut.togglePin(note)
        XCTAssertFalse(note.isPinned)
    }

    // MARK: - fetchNotes

    func testFetchNotes_filtersByPARA() {
        let note1 = sut.createNote(title: "Inbox Note", paraCategory: .inbox)
        let note2 = sut.createNote(title: "Project Note", paraCategory: .project)

        let inboxNotes = sut.fetchNotes(para: .inbox)
        let projectNotes = sut.fetchNotes(para: .project)

        XCTAssertTrue(inboxNotes.contains(where: { $0.objectID == note1.objectID }))
        XCTAssertFalse(inboxNotes.contains(where: { $0.objectID == note2.objectID }))
        XCTAssertTrue(projectNotes.contains(where: { $0.objectID == note2.objectID }))
    }

    func testFetchNotes_excludesArchivedByDefault() {
        let note = sut.createNote(title: "Active")
        let archived = sut.createNote(title: "Archived")
        sut.archiveNote(archived)

        let results = sut.fetchNotes()
        XCTAssertTrue(results.contains(where: { $0.objectID == note.objectID }))
        XCTAssertFalse(results.contains(where: { $0.objectID == archived.objectID }))
    }

    func testFetchNotes_filtersByNoteType() {
        let fleeting = sut.createNote(title: "Fleeting")
        fleeting.noteType = .fleeting
        let permanent = sut.createNote(title: "Permanent")
        permanent.noteType = .permanent
        try? context.save()

        let results = sut.fetchNotes(noteType: .permanent)
        XCTAssertTrue(results.contains(where: { $0.objectID == permanent.objectID }))
        XCTAssertFalse(results.contains(where: { $0.objectID == fleeting.objectID }))
    }

    // MARK: - searchNotes

    func testSearchNotes_findsByTitle() {
        let note = sut.createNote(title: "Unique Title Here", content: "blah")
        let results = sut.searchNotes(query: "Unique")
        XCTAssertTrue(results.contains(where: { $0.objectID == note.objectID }))
    }

    func testSearchNotes_findsByContent() {
        let note = sut.createNote(title: "T", content: "special keyword inside")
        let results = sut.searchNotes(query: "special keyword")
        XCTAssertTrue(results.contains(where: { $0.objectID == note.objectID }))
    }

    func testSearchNotes_findsByZettelId() {
        let note = sut.createNote(title: "T")
        let zettelId = note.zettelId!
        let results = sut.searchNotes(query: zettelId)
        XCTAssertTrue(results.contains(where: { $0.objectID == note.objectID }))
    }

    // MARK: - countNotes

    func testCountNotes() {
        _ = sut.createNote(title: "A")
        _ = sut.createNote(title: "B")
        let archived = sut.createNote(title: "C")
        sut.archiveNote(archived)

        let count = sut.countNotes()
        XCTAssertEqual(count, 2) // excludes archived
    }

    // MARK: - findByZettelId

    func testFindByZettelId() {
        let note = sut.createNote(title: "Test")
        let zettelId = note.zettelId!

        let found = sut.findByZettelId(zettelId)
        XCTAssertEqual(found?.objectID, note.objectID)
    }

    func testFindByZettelId_notFound() {
        let found = sut.findByZettelId("nonexistent-id")
        XCTAssertNil(found)
    }
}
