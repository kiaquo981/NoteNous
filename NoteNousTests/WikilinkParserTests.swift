import XCTest
import CoreData
@testable import NoteNous

final class WikilinkParserTests: NoteNousTestCase {

    private var sut: WikilinkParser!

    override func setUp() {
        super.setUp()
        sut = WikilinkParser(context: context)
    }

    override func tearDown() {
        sut = nil
        super.tearDown()
    }

    // MARK: - extractWikilinks

    func testExtractWikilinks_twoMatches() {
        let text = "text [[Note A]] and [[Note B|alias]]"
        let matches = sut.extractWikilinks(from: text)

        XCTAssertEqual(matches.count, 2)
        XCTAssertEqual(matches[0].targetTitle, "Note A")
        XCTAssertNil(matches[0].displayText)
        XCTAssertEqual(matches[1].targetTitle, "Note B")
        XCTAssertEqual(matches[1].displayText, "alias")
    }

    func testExtractWithPipeSyntax() {
        let text = "see [[target|display text here]]"
        let matches = sut.extractWikilinks(from: text)

        XCTAssertEqual(matches.count, 1)
        XCTAssertEqual(matches[0].targetTitle, "target")
        XCTAssertEqual(matches[0].displayText, "display text here")
    }

    func testNestedBracketsIgnored() {
        let text = "[[valid]] and [not valid]"
        let matches = sut.extractWikilinks(from: text)

        XCTAssertEqual(matches.count, 1)
        XCTAssertEqual(matches[0].targetTitle, "valid")
    }

    func testEmptyBrackets() {
        let text = "[[]]"
        let matches = sut.extractWikilinks(from: text)

        XCTAssertEqual(matches.count, 0)
    }

    func testExtractWikilinks_noMatchesInPlainText() {
        let text = "just some plain text without links"
        let matches = sut.extractWikilinks(from: text)
        XCTAssertTrue(matches.isEmpty)
    }

    // MARK: - Resolution

    func testResolveExistingNote() {
        let note = createNote(title: "Test Note")
        let text = "reference to [[Test Note]]"

        let resolutions = sut.resolveWikilinks(in: text)

        XCTAssertEqual(resolutions.count, 1)
        XCTAssertFalse(resolutions[0].isBroken)
        XCTAssertEqual(resolutions[0].resolvedNote?.objectID, note.objectID)
    }

    func testResolveCaseInsensitive() {
        let note = createNote(title: "Test Note")
        let text = "reference to [[test note]]"

        let resolutions = sut.resolveWikilinks(in: text)

        XCTAssertEqual(resolutions.count, 1)
        XCTAssertFalse(resolutions[0].isBroken)
        XCTAssertEqual(resolutions[0].resolvedNote?.objectID, note.objectID)
    }

    // MARK: - Broken Links

    func testBrokenLinks_nonExistentNote() {
        let text = "reference to [[NonExistent]]"
        let broken = sut.brokenLinks(in: text)

        XCTAssertEqual(broken.count, 1)
        XCTAssertEqual(broken[0].targetTitle, "NonExistent")
    }

    func testCreateFromBrokenLink() {
        let text = "reference to [[New Note From Link]]"
        let broken = sut.brokenLinks(in: text)
        XCTAssertEqual(broken.count, 1)

        let createdNote = sut.createNoteFromBrokenLink(broken[0])

        XCTAssertEqual(createdNote.title, "New Note From Link")
        XCTAssertNotNil(createdNote.id)
        XCTAssertNotNil(createdNote.zettelId)

        // Now resolving should find it
        let resolved = sut.resolveWikilinks(in: text)
        XCTAssertEqual(resolved.count, 1)
        XCTAssertFalse(resolved[0].isBroken)
    }

    // MARK: - syncLinks

    func testSyncLinks_createsLinkEntities() {
        let source = createNote(title: "Source", content: "see [[Target A]] and [[Target B]]")
        let targetA = createNote(title: "Target A")
        let targetB = createNote(title: "Target B")

        sut.syncLinks(for: source)

        let outgoing = source.outgoingLinksArray
        XCTAssertEqual(outgoing.count, 2)

        let targetIDs = Set(outgoing.compactMap { $0.targetNote?.objectID })
        XCTAssertTrue(targetIDs.contains(targetA.objectID))
        XCTAssertTrue(targetIDs.contains(targetB.objectID))
    }

    func testSyncLinks_doesNotDuplicateExistingLinks() {
        let source = createNote(title: "Source", content: "see [[Target]]")
        _ = createNote(title: "Target")

        sut.syncLinks(for: source)
        let countAfterFirst = source.outgoingLinksArray.count

        sut.syncLinks(for: source)
        let countAfterSecond = source.outgoingLinksArray.count

        XCTAssertEqual(countAfterFirst, countAfterSecond)
    }
}
