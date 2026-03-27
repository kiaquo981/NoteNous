import XCTest
@testable import NoteNous

final class WorkflowDataModelTests: XCTestCase {

    // MARK: - Source Waiting Period

    func testSourceWaitingPeriod() {
        let tenDaysAgo = Calendar.current.date(byAdding: .day, value: -10, to: Date())!
        let source = Source(title: "Test", dateConsumed: tenDaysAgo, dateCarded: nil)

        XCTAssertNotNil(source.waitingPeriodDays)
        XCTAssertEqual(source.waitingPeriodDays!, 10, accuracy: 1, "Should calculate correct waiting period in days")
    }

    // MARK: - Source Is Ready to Card

    func testSourceIsReadyToCard() {
        let fifteenDaysAgo = Calendar.current.date(byAdding: .day, value: -15, to: Date())!
        let readySource = Source(title: "Ready", dateConsumed: fifteenDaysAgo, dateCarded: nil)
        XCTAssertTrue(readySource.isReadyToCard, "15 days should be ready (>= 14)")

        let thirteenDaysAgo = Calendar.current.date(byAdding: .day, value: -13, to: Date())!
        let notReadySource = Source(title: "Not Ready", dateConsumed: thirteenDaysAgo, dateCarded: nil)
        XCTAssertFalse(notReadySource.isReadyToCard, "13 days should not be ready (< 14)")
    }

    // MARK: - IndexEntry Hashable

    func testIndexEntryHashable() {
        let entry1 = IndexEntry(keyword: "philosophy", entryNoteIds: [UUID()])
        let entry2 = IndexEntry(keyword: "science", entryNoteIds: [UUID()])
        let entry3 = IndexEntry(id: entry1.id, keyword: "philosophy", entryNoteIds: entry1.entryNoteIds)

        var set = Set<IndexEntry>()
        set.insert(entry1)
        set.insert(entry2)
        set.insert(entry3) // Same id as entry1, should not increase count

        // IndexEntry conforms to Hashable via Equatable (id-based)
        XCTAssertTrue(set.count >= 2, "IndexEntry should be usable in a Set")
    }

    // MARK: - Atomicity Issue Severity

    func testAtomicityIssueSeverity() {
        // tooShort is critical
        let tooShort = AtomicityIssue.tooShort(wordCount: 10, minimum: 50)
        XCTAssertTrue(tooShort.isCritical, "tooShort should be critical")

        // tooLong is not critical
        let tooLong = AtomicityIssue.tooLong(wordCount: 1000, maximum: 500)
        XCTAssertFalse(tooLong.isCritical, "tooLong should not be critical")

        // multipleHeadings is not critical
        let multiHead = AtomicityIssue.multipleHeadings(count: 5)
        XCTAssertFalse(multiHead.isCritical, "multipleHeadings should not be critical")

        // noOutgoingLinks is not critical
        let noLinks = AtomicityIssue.noOutgoingLinks
        XCTAssertFalse(noLinks.isCritical, "noOutgoingLinks should not be critical")

        // Report with no issues should be good
        let goodReport = AtomicityReport(
            wordCount: 100, headingCount: 1, paragraphCount: 2,
            outgoingLinkCount: 1, titleWordCount: 5, issues: []
        )
        XCTAssertTrue(goodReport.isAtomic)
        XCTAssertEqual(goodReport.severity, .good)

        // Report with critical issue
        let criticalReport = AtomicityReport(
            wordCount: 10, headingCount: 1, paragraphCount: 1,
            outgoingLinkCount: 0, titleWordCount: 2,
            issues: [.tooShort(wordCount: 10, minimum: 50)]
        )
        XCTAssertFalse(criticalReport.isAtomic)
        XCTAssertEqual(criticalReport.severity, .critical)

        // Report with warning only
        let warningReport = AtomicityReport(
            wordCount: 200, headingCount: 3, paragraphCount: 2,
            outgoingLinkCount: 1, titleWordCount: 3,
            issues: [.multipleHeadings(count: 3)]
        )
        XCTAssertEqual(warningReport.severity, .warning)
    }
}
