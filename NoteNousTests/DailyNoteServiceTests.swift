import XCTest
import CoreData
@testable import NoteNous

final class DailyNoteServiceTests: NoteNousTestCase {

    private var service: DailyNoteService!

    override func setUp() {
        super.setUp()
        service = DailyNoteService(context: context)
    }

    override func tearDown() {
        service = nil
        super.tearDown()
    }

    // MARK: - Create Daily Note

    func testCreateDailyNote() {
        let note = service.todayNote()

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        let expectedTitle = formatter.string(from: Date())

        XCTAssertEqual(note.title, expectedTitle, "Daily note title should be today's date in yyyy-MM-dd format")
    }

    // MARK: - Idempotent

    func testTodayNoteIdempotent() {
        let first = service.todayNote()
        let second = service.todayNote()
        XCTAssertEqual(first.objectID, second.objectID, "Calling todayNote() twice should return the same note")
    }

    // MARK: - Template Content

    func testDailyNoteTemplate() {
        let note = service.todayNote()
        XCTAssertTrue(note.content.contains("# Daily Note"), "Daily note should contain template header")
        XCTAssertTrue(note.content.contains("## Captures"), "Daily note should contain Captures section")
        XCTAssertTrue(note.content.contains("## Tasks"), "Daily note should contain Tasks section")
        XCTAssertTrue(note.content.contains("## Reflections"), "Daily note should contain Reflections section")
    }

    // MARK: - Tagged with "daily"

    func testDailyNoteTagged() {
        let note = service.todayNote()
        let tagNames = note.tagsArray.compactMap { $0.name }
        XCTAssertTrue(tagNames.contains("daily"), "Daily note should be tagged with 'daily'")
    }
}
