import XCTest
import CoreData
@testable import NoteNous

final class LinkServiceTests: NoteNousTestCase {

    private var sut: LinkService!

    override func setUp() {
        super.setUp()
        sut = LinkService(context: context)
    }

    override func tearDown() {
        sut = nil
        super.tearDown()
    }

    // MARK: - createLink

    func testCreateLink_success() {
        let source = createNote(title: "Source")
        let target = createNote(title: "Target")

        let link = sut.createLink(from: source, to: target, type: .reference, strength: 0.8)

        XCTAssertNotNil(link)
        XCTAssertEqual(link?.sourceNote?.objectID, source.objectID)
        XCTAssertEqual(link?.targetNote?.objectID, target.objectID)
        XCTAssertEqual(link?.linkType, .reference)
        XCTAssertEqual(link?.strength, 0.8)
        XCTAssertTrue(link?.isConfirmed ?? false)
        XCTAssertFalse(link?.isAISuggested ?? true)
    }

    func testCreateLink_aiSuggestedNotConfirmed() {
        let source = createNote(title: "Source")
        let target = createNote(title: "Target")

        let link = sut.createLink(from: source, to: target, isAISuggested: true)

        XCTAssertNotNil(link)
        XCTAssertTrue(link?.isAISuggested ?? false)
        XCTAssertFalse(link?.isConfirmed ?? true)
    }

    // MARK: - Prevent self-link

    func testPreventSelfLink() {
        let note = createNote(title: "Self")
        let link = sut.createLink(from: note, to: note)

        XCTAssertNil(link)
    }

    // MARK: - Prevent duplicate

    func testPreventDuplicateLink() {
        let source = createNote(title: "Source")
        let target = createNote(title: "Target")

        let first = sut.createLink(from: source, to: target)
        let second = sut.createLink(from: source, to: target)

        XCTAssertNotNil(first)
        XCTAssertNil(second)
    }

    // MARK: - backlinks

    func testBacklinks() {
        let noteA = createNote(title: "A")
        let noteB = createNote(title: "B")
        let noteC = createNote(title: "C")

        _ = sut.createLink(from: noteB, to: noteA) // confirmed
        _ = sut.createLink(from: noteC, to: noteA) // confirmed

        let backlinks = sut.backlinks(for: noteA)

        XCTAssertEqual(backlinks.count, 2)
        let sourceIDs = Set(backlinks.compactMap { $0.sourceNote?.objectID })
        XCTAssertTrue(sourceIDs.contains(noteB.objectID))
        XCTAssertTrue(sourceIDs.contains(noteC.objectID))
    }

    // MARK: - suggestedLinks

    func testSuggestedLinks() {
        let noteA = createNote(title: "A")
        let noteB = createNote(title: "B")

        _ = sut.createLink(from: noteA, to: noteB, isAISuggested: true)

        let suggested = sut.suggestedLinks(for: noteA)

        XCTAssertEqual(suggested.count, 1)
        XCTAssertTrue(suggested[0].isAISuggested)
        XCTAssertFalse(suggested[0].isConfirmed)
    }

    // MARK: - confirmLink

    func testConfirmLink() {
        let noteA = createNote(title: "A")
        let noteB = createNote(title: "B")
        let link = sut.createLink(from: noteA, to: noteB, isAISuggested: true)!

        XCTAssertFalse(link.isConfirmed)

        sut.confirmLink(link)

        XCTAssertTrue(link.isConfirmed)
    }

    // MARK: - rejectLink

    func testRejectLink() {
        let noteA = createNote(title: "A")
        let noteB = createNote(title: "B")
        let link = sut.createLink(from: noteA, to: noteB)!
        let linkID = link.objectID

        sut.rejectLink(link)

        let fetched = try? context.existingObject(with: linkID)
        XCTAssertTrue(fetched == nil || fetched!.isDeleted)
    }
}
