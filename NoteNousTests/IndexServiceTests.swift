import XCTest
@testable import NoteNous

final class IndexServiceTests: XCTestCase {

    private var service: IndexService!

    override func setUp() {
        super.setUp()
        service = IndexService()
        // Clear any leftover entries
        for entry in service.entries {
            service.removeEntry(keyword: entry.keyword)
        }
    }

    override func tearDown() {
        // Cleanup
        for entry in service.entries {
            service.removeEntry(keyword: entry.keyword)
        }
        service = nil
        super.tearDown()
    }

    // MARK: - Add Entry

    func testAddEntry() {
        let noteId = UUID()
        let result = service.addEntry(keyword: "epistemology", noteId: noteId)
        XCTAssertTrue(result)

        let entry = service.entry(for: "epistemology")
        XCTAssertNotNil(entry)
        XCTAssertEqual(entry?.entryNoteIds.count, 1)
        XCTAssertEqual(entry?.entryNoteIds.first, noteId)
    }

    func testAddEntryExistingKeyword() {
        let noteId1 = UUID()
        let noteId2 = UUID()
        service.addEntry(keyword: "philosophy", noteId: noteId1)
        service.addEntry(keyword: "philosophy", noteId: noteId2)

        let entry = service.entry(for: "philosophy")
        XCTAssertEqual(entry?.entryNoteIds.count, 2)
        XCTAssertTrue(entry?.entryNoteIds.contains(noteId1) ?? false)
        XCTAssertTrue(entry?.entryNoteIds.contains(noteId2) ?? false)
    }

    // MARK: - Max Entry Notes

    func testMaxEntryNotes() {
        let keyword = "testmax"
        service.addEntry(keyword: keyword, noteId: UUID())
        service.addEntry(keyword: keyword, noteId: UUID())
        service.addEntry(keyword: keyword, noteId: UUID())

        // 4th note should be rejected
        let fourthResult = service.addEntry(keyword: keyword, noteId: UUID())
        XCTAssertFalse(fourthResult, "4th note should be rejected when max is 3")
        XCTAssertEqual(service.entry(for: keyword)?.entryNoteIds.count, 3)
    }

    func testForceOverride() {
        let keyword = "testforce"
        service.addEntry(keyword: keyword, noteId: UUID())
        service.addEntry(keyword: keyword, noteId: UUID())
        service.addEntry(keyword: keyword, noteId: UUID())

        let fourthId = UUID()
        let result = service.addEntry(keyword: keyword, noteId: fourthId, force: true)
        XCTAssertTrue(result, "4th note should be accepted with force=true")
        XCTAssertEqual(service.entry(for: keyword)?.entryNoteIds.count, 4)
        XCTAssertTrue(service.entry(for: keyword)?.entryNoteIds.contains(fourthId) ?? false)
    }

    // MARK: - Remove Entry

    func testRemoveEntry() {
        service.addEntry(keyword: "toremove", noteId: UUID())
        XCTAssertNotNil(service.entry(for: "toremove"))

        service.removeEntry(keyword: "toremove")
        XCTAssertNil(service.entry(for: "toremove"))
    }

    func testRemoveNoteFromEntry() {
        let noteId1 = UUID()
        let noteId2 = UUID()
        service.addEntry(keyword: "partial", noteId: noteId1)
        service.addEntry(keyword: "partial", noteId: noteId2)

        service.removeNoteFromEntry(keyword: "partial", noteId: noteId1)

        let entry = service.entry(for: "partial")
        XCTAssertNotNil(entry, "Keyword should still exist with remaining notes")
        XCTAssertEqual(entry?.entryNoteIds.count, 1)
        XCTAssertFalse(entry?.entryNoteIds.contains(noteId1) ?? true)
        XCTAssertTrue(entry?.entryNoteIds.contains(noteId2) ?? false)
    }

    func testRemoveLastNote() {
        let noteId = UUID()
        service.addEntry(keyword: "singleton", noteId: noteId)
        service.removeNoteFromEntry(keyword: "singleton", noteId: noteId)

        XCTAssertNil(service.entry(for: "singleton"), "Keyword should be auto-deleted when last note is removed")
    }

    // MARK: - Search Keywords

    func testSearchKeywords() {
        service.addEntry(keyword: "philosophy", noteId: UUID())
        service.addEntry(keyword: "physics", noteId: UUID())
        service.addEntry(keyword: "biology", noteId: UUID())

        let results = service.searchKeywords(prefix: "ph")
        XCTAssertEqual(results.count, 2)
        XCTAssertTrue(results.contains { $0.keyword == "philosophy" })
        XCTAssertTrue(results.contains { $0.keyword == "physics" })
    }

    // MARK: - Add Empty Entry

    func testAddEmptyEntry() {
        service.addEmptyEntry(keyword: "placeholder")
        let entry = service.entry(for: "placeholder")
        XCTAssertNotNil(entry)
        XCTAssertEqual(entry?.entryNoteIds.count, 0)
    }

    // MARK: - Persistence

    func testPersistence() {
        let noteId = UUID()
        service.addEntry(keyword: "persistent", noteId: noteId)

        // Create a new instance which loads from disk
        let service2 = IndexService()
        let entry = service2.entry(for: "persistent")
        XCTAssertNotNil(entry, "Entry should survive reload")
        XCTAssertEqual(entry?.entryNoteIds.first, noteId)

        // Cleanup
        service2.removeEntry(keyword: "persistent")
    }
}
