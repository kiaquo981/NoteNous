import XCTest
@testable import NoteNous

final class SourceServiceTests: XCTestCase {

    private var tempDir: URL!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        tempDir = nil
        super.tearDown()
    }

    private func makeService() -> SourceService {
        // SourceService uses Application Support by default.
        // We test the public API which persists to its own path.
        // For isolation we create a fresh instance each time.
        return SourceService()
    }

    // MARK: - Add Source

    func testAddSource() {
        let service = makeService()
        let initialCount = service.sources.count

        let source = service.addSource(
            title: "Test Book",
            author: "Author Name",
            sourceType: .book,
            url: "https://example.com",
            isbn: "978-0-000-00000-0",
            dateConsumed: Date(),
            rating: 4,
            notes: "Great book"
        )

        XCTAssertEqual(service.sources.count, initialCount + 1)
        XCTAssertEqual(source.title, "Test Book")
        XCTAssertEqual(source.author, "Author Name")
        XCTAssertEqual(source.sourceType, .book)
        XCTAssertEqual(source.url, "https://example.com")
        XCTAssertEqual(source.isbn, "978-0-000-00000-0")
        XCTAssertEqual(source.rating, 4)
        XCTAssertEqual(source.notes, "Great book")
    }

    // MARK: - Delete Source

    func testDeleteSource() {
        let service = makeService()
        let source = service.addSource(title: "To Delete")
        let countAfterAdd = service.sources.count

        service.deleteSource(id: source.id)
        XCTAssertEqual(service.sources.count, countAfterAdd - 1)
        XCTAssertNil(service.source(for: source.id))
    }

    // MARK: - Waiting Period

    func testWaitingPeriod() {
        let tenDaysAgo = Calendar.current.date(byAdding: .day, value: -10, to: Date())!
        let source = Source(
            title: "Recent Read",
            dateConsumed: tenDaysAgo,
            dateCarded: nil
        )

        XCTAssertNotNil(source.waitingPeriodDays)
        XCTAssertEqual(source.waitingPeriodDays!, 10, accuracy: 1)
    }

    func testIsReadyToCard() {
        let twentyDaysAgo = Calendar.current.date(byAdding: .day, value: -20, to: Date())!
        let source = Source(title: "Old Read", dateConsumed: twentyDaysAgo, dateCarded: nil)
        XCTAssertTrue(source.isReadyToCard, "Source consumed 20 days ago should be ready to card")
    }

    func testNotReadyToCard() {
        let fiveDaysAgo = Calendar.current.date(byAdding: .day, value: -5, to: Date())!
        let source = Source(title: "Recent Read", dateConsumed: fiveDaysAgo, dateCarded: nil)
        XCTAssertFalse(source.isReadyToCard, "Source consumed 5 days ago should not be ready to card")
    }

    // MARK: - Sources Ready to Card Filter

    func testSourcesReadyToCard() {
        let service = makeService()
        // Clear existing
        for s in service.sources {
            service.deleteSource(id: s.id)
        }

        let oldDate = Calendar.current.date(byAdding: .day, value: -20, to: Date())!
        let recentDate = Calendar.current.date(byAdding: .day, value: -3, to: Date())!

        service.addSource(title: "Ready", dateConsumed: oldDate)
        service.addSource(title: "Not Ready", dateConsumed: recentDate)
        service.addSource(title: "No Date")

        let ready = service.sourcesReadyToCard()
        XCTAssertEqual(ready.count, 1)
        XCTAssertEqual(ready.first?.title, "Ready")
    }

    // MARK: - Persistence

    func testPersistence() {
        // Add a source, create a new service instance, verify data survives
        let service1 = makeService()
        let source = service1.addSource(title: "Persistent Source", author: "Persistent Author")
        let savedId = source.id

        // Create a new instance which loads from disk
        let service2 = SourceService()
        let found = service2.source(for: savedId)
        XCTAssertNotNil(found, "Source should survive reload")
        XCTAssertEqual(found?.title, "Persistent Source")
        XCTAssertEqual(found?.author, "Persistent Author")

        // Cleanup
        service2.deleteSource(id: savedId)
    }
}
