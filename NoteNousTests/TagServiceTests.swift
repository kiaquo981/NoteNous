import XCTest
import CoreData
@testable import NoteNous

final class TagServiceTests: NoteNousTestCase {

    private var sut: TagService!

    override func setUp() {
        super.setUp()
        sut = TagService(context: context)
    }

    override func tearDown() {
        sut = nil
        super.tearDown()
    }

    // MARK: - findOrCreate

    func testFindOrCreate_createsNew() {
        let tag = sut.findOrCreate(name: "swift")

        XCTAssertNotNil(tag.id)
        XCTAssertEqual(tag.name, "swift")
        XCTAssertEqual(tag.usageCount, 0)
    }

    func testFindOrCreate_returnsExisting() {
        let first = sut.findOrCreate(name: "swift")
        let second = sut.findOrCreate(name: "swift")

        XCTAssertEqual(first.objectID, second.objectID)
    }

    // MARK: - Case Normalization

    func testCaseNormalization() {
        let upper = sut.findOrCreate(name: "Swift")
        let lower = sut.findOrCreate(name: "swift")

        XCTAssertEqual(upper.objectID, lower.objectID)
    }

    func testCaseNormalization_mixedCase() {
        let tag1 = sut.findOrCreate(name: "MachineLearning")
        let tag2 = sut.findOrCreate(name: "machinelearning")

        XCTAssertEqual(tag1.objectID, tag2.objectID)
    }

    // MARK: - addTag / removeTag

    func testAddTagToNote() {
        let note = createNote(title: "Test")
        let tag = sut.findOrCreate(name: "important")

        sut.addTag(tag, to: note)

        XCTAssertTrue(note.tagsArray.contains(where: { $0.objectID == tag.objectID }))
        XCTAssertEqual(tag.usageCount, 1)
    }

    func testRemoveTagFromNote() {
        let note = createNote(title: "Test")
        let tag = sut.findOrCreate(name: "important")
        sut.addTag(tag, to: note)

        sut.removeTag(tag, from: note)

        XCTAssertFalse(note.tagsArray.contains(where: { $0.objectID == tag.objectID }))
        XCTAssertEqual(tag.usageCount, 0)
    }

    func testRemoveTag_doesNotGoNegative() {
        let note = createNote(title: "Test")
        let tag = sut.findOrCreate(name: "test")
        // usageCount starts at 0, removing should stay at 0
        sut.removeTag(tag, from: note)

        XCTAssertEqual(tag.usageCount, 0)
    }

    // MARK: - topTags

    func testTopTags_orderedByUsageCount() {
        let note1 = createNote(title: "N1")
        let note2 = createNote(title: "N2")

        let tagA = sut.findOrCreate(name: "a")
        let tagB = sut.findOrCreate(name: "b")

        sut.addTag(tagA, to: note1)
        sut.addTag(tagB, to: note1)
        sut.addTag(tagB, to: note2)

        let top = sut.topTags(limit: 10)

        XCTAssertGreaterThanOrEqual(top.count, 2)
        // tagB (2 uses) should come before tagA (1 use)
        if let indexB = top.firstIndex(where: { $0.objectID == tagB.objectID }),
           let indexA = top.firstIndex(where: { $0.objectID == tagA.objectID }) {
            XCTAssertLessThan(indexB, indexA)
        }
    }

    // MARK: - searchTags

    func testSearchTags_prefixSearch() {
        _ = sut.findOrCreate(name: "swift")
        _ = sut.findOrCreate(name: "swiftui")
        _ = sut.findOrCreate(name: "python")

        let results = sut.searchTags(prefix: "swi")

        XCTAssertEqual(results.count, 2)
        XCTAssertTrue(results.allSatisfy { $0.name?.hasPrefix("swi") ?? false })
    }
}
