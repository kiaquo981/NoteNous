import XCTest
@testable import NoteNous

final class SpacedRepetitionTests: XCTestCase {

    private var service: SpacedRepetitionService!

    override func setUp() {
        super.setUp()
        service = SpacedRepetitionService()
    }

    override func tearDown() {
        // Cleanup enrolled cards
        for (id, _) in service.cards {
            service.unenroll(noteId: id)
        }
        service = nil
        super.tearDown()
    }

    // MARK: - Enrollment

    func testEnroll() {
        let noteId = UUID()
        service.enroll(noteId: noteId)

        let card = service.cards[noteId]
        XCTAssertNotNil(card)
        XCTAssertEqual(card?.easeFactor, 2.5, "Default ease factor should be 2.5")
        XCTAssertEqual(card?.interval, 0, "Default interval should be 0")
        XCTAssertEqual(card?.repetitions, 0, "Default repetitions should be 0")
    }

    // MARK: - Reviews

    func testReviewGood() {
        let noteId = UUID()
        service.enroll(noteId: noteId)

        service.review(noteId: noteId, quality: 3)
        let card = service.cards[noteId]!
        XCTAssertEqual(card.repetitions, 1, "Repetitions should increment after good review")
        XCTAssertEqual(card.interval, 1, "First successful review should set interval to 1")
    }

    func testReviewEasy() {
        let noteId = UUID()
        service.enroll(noteId: noteId)

        // First review
        service.review(noteId: noteId, quality: 5)
        let card1 = service.cards[noteId]!
        XCTAssertEqual(card1.repetitions, 1)
        let easeAfterFirst = card1.easeFactor
        XCTAssertGreaterThan(easeAfterFirst, 2.5, "Ease should increase after quality 5")

        // Second review
        service.review(noteId: noteId, quality: 5)
        let card2 = service.cards[noteId]!
        XCTAssertEqual(card2.repetitions, 2)
        XCTAssertEqual(card2.interval, 6, "Second successful review should set interval to 6")
    }

    func testReviewFail() {
        let noteId = UUID()
        service.enroll(noteId: noteId)

        // Do a few good reviews first
        service.review(noteId: noteId, quality: 4)
        service.review(noteId: noteId, quality: 4)

        // Now fail
        service.review(noteId: noteId, quality: 1)
        let card = service.cards[noteId]!
        XCTAssertEqual(card.repetitions, 0, "Failed review should reset repetitions to 0")
        XCTAssertEqual(card.interval, 1, "Failed review should reset interval to 1")
    }

    func testReviewHard() {
        let noteId = UUID()
        service.enroll(noteId: noteId)

        let initialEase = service.cards[noteId]!.easeFactor

        service.review(noteId: noteId, quality: 2)
        let card = service.cards[noteId]!
        XCTAssertLessThan(card.easeFactor, initialEase, "Ease should decrease after hard review (quality 2)")
        XCTAssertGreaterThanOrEqual(card.easeFactor, 1.3, "Ease should never go below 1.3")
    }

    // MARK: - Due Cards

    func testDueCards() {
        let noteId = UUID()
        service.enroll(noteId: noteId)
        // Newly enrolled card has nextReviewDate = now, so it's due
        let due = service.dueCards()
        XCTAssertTrue(due.contains { $0.id == noteId }, "Newly enrolled card should be due")
    }

    func testUpcomingCards() {
        let noteId = UUID()
        service.enroll(noteId: noteId)
        let upcoming = service.upcomingCards(days: 7)
        XCTAssertTrue(upcoming.contains { $0.id == noteId }, "Newly enrolled card should appear in upcoming 7 days")
    }

    // MARK: - Unenroll

    func testUnenroll() {
        let noteId = UUID()
        service.enroll(noteId: noteId)
        XCTAssertTrue(service.isEnrolled(noteId: noteId))

        service.unenroll(noteId: noteId)
        XCTAssertFalse(service.isEnrolled(noteId: noteId))
        XCTAssertNil(service.cards[noteId])
    }

    // MARK: - Streak

    func testStreakTracking() {
        let noteId = UUID()
        service.enroll(noteId: noteId)

        // A review on today should start streak at 1 (or increment)
        service.review(noteId: noteId, quality: 4)
        XCTAssertGreaterThanOrEqual(service.streak, 1, "Streak should be at least 1 after a review")
    }

    // MARK: - SM-2 Interval Growth

    func testSM2IntervalGrowth() {
        let noteId = UUID()
        service.enroll(noteId: noteId)

        // 5 good reviews (quality 4)
        for _ in 0..<5 {
            service.review(noteId: noteId, quality: 4)
        }

        let card = service.cards[noteId]!
        XCTAssertGreaterThan(card.interval, 14, "After 5 good reviews, interval should be more than 2 weeks")
        XCTAssertEqual(card.repetitions, 5)
    }
}
