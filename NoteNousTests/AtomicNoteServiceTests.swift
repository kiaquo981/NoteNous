import XCTest
import CoreData
@testable import NoteNous

final class AtomicNoteServiceTests: NoteNousTestCase {

    private var sut: AtomicNoteService!

    override func setUp() {
        super.setUp()
        sut = AtomicNoteService(context: context)
    }

    override func tearDown() {
        sut = nil
        super.tearDown()
    }

    // MARK: - Helpers

    private func makePermanentNote(title: String, content: String) -> NoteEntity {
        let service = NoteService(context: context)
        let note = service.createNote(title: title, content: content)
        note.noteType = .permanent
        note.contentPlainText = content
        try? context.save()
        return note
    }

    private func makeLiteratureNote(title: String, content: String) -> NoteEntity {
        let service = NoteService(context: context)
        let note = service.createNote(title: title, content: content)
        note.noteType = .literature
        note.contentPlainText = content
        try? context.save()
        return note
    }

    // MARK: - Atomic Note (no issues)

    func testAtomicNote_noIssues() {
        // ~100 words, good title (4+ words), has outgoing link
        let content = words(100)
        let note = makePermanentNote(title: "Knowledge requires justified belief", content: content)

        // Add an outgoing link to avoid noOutgoingLinks issue
        let target = createNote(title: "Target")
        let linkService = LinkService(context: context)
        _ = linkService.createLink(from: note, to: target)

        let report = sut.analyze(note: note)

        XCTAssertTrue(report.isAtomic)
        XCTAssertTrue(report.issues.isEmpty)
    }

    // MARK: - tooShort

    func testTooShort() {
        let content = words(20)
        let note = makePermanentNote(title: "Short note about things", content: content)

        let report = sut.analyze(note: note)

        XCTAssertTrue(report.issues.contains(where: {
            if case .tooShort = $0 { return true }
            return false
        }))
    }

    // MARK: - tooLong

    func testTooLong() {
        let content = words(500)
        let note = makePermanentNote(title: "Very long note about things", content: content)

        let report = sut.analyze(note: note)

        XCTAssertTrue(report.issues.contains(where: {
            if case .tooLong = $0 { return true }
            return false
        }))
    }

    // MARK: - multipleHeadings

    func testMultipleHeadings() {
        let content = "# First heading\nSome text\n# Second heading\nMore text\n# Third heading\nEven more"
        let note = makePermanentNote(title: "Note with many headings here", content: content)
        // Override contentPlainText to have enough words
        note.contentPlainText = words(100)
        try? context.save()

        let report = sut.analyze(note: note)

        XCTAssertTrue(report.issues.contains(where: {
            if case .multipleHeadings = $0 { return true }
            return false
        }))
    }

    // MARK: - topicTitle

    func testTopicTitle_twoWords() {
        let note = makePermanentNote(title: "AI Ethics", content: words(100))

        let report = sut.analyze(note: note)

        XCTAssertTrue(report.issues.contains(where: {
            if case .topicTitle = $0 { return true }
            return false
        }))
    }

    func testPropositionTitle_noIssue() {
        let content = words(100)
        let note = makePermanentNote(title: "AI systems should be transparent and accountable", content: content)

        // Add an outgoing link to avoid noOutgoingLinks issue
        let target = createNote(title: "Target")
        let linkService = LinkService(context: context)
        _ = linkService.createLink(from: note, to: target)

        let report = sut.analyze(note: note)

        XCTAssertFalse(report.issues.contains(where: {
            if case .topicTitle = $0 { return true }
            return false
        }))
    }

    // MARK: - noOutgoingLinks

    func testNoOutgoingLinks() {
        let note = makePermanentNote(title: "Isolated permanent note here", content: words(100))

        let report = sut.analyze(note: note)

        XCTAssertTrue(report.issues.contains(where: {
            if case .noOutgoingLinks = $0 { return true }
            return false
        }))
    }

    // MARK: - missingSource

    func testMissingSource() {
        let note = makeLiteratureNote(title: "Literature without source", content: words(100))
        // Ensure no source fields
        note.sourceURL = nil
        note.sourceTitle = nil
        try? context.save()

        let report = sut.analyze(note: note)

        XCTAssertTrue(report.issues.contains(where: {
            if case .missingSource = $0 { return true }
            return false
        }))
    }

    func testLiteratureWithSource_noMissingSourceIssue() {
        let note = makeLiteratureNote(title: "Literature with source data", content: words(100))
        note.sourceTitle = "Some Book"
        try? context.save()

        let report = sut.analyze(note: note)

        XCTAssertFalse(report.issues.contains(where: {
            if case .missingSource = $0 { return true }
            return false
        }))
    }

    // MARK: - Fleeting notes skip atomicity checks

    func testFleetingNote_noAtomicityIssues() {
        let note = createNote(title: "F", content: words(20), type: .fleeting)

        let report = sut.analyze(note: note)

        // Fleeting notes should not have tooShort/tooLong/etc
        XCTAssertTrue(report.isAtomic)
    }
}
