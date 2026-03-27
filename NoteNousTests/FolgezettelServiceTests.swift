import XCTest
import CoreData
@testable import NoteNous

final class FolgezettelServiceTests: NoteNousTestCase {

    private var sut: FolgezettelService!

    override func setUp() {
        super.setUp()
        sut = FolgezettelService(context: context)
    }

    override func tearDown() {
        sut = nil
        super.tearDown()
    }

    // MARK: - generateNextRoot

    func testGenerateNextRoot_firstRoot() {
        let root = sut.generateNextRoot()
        XCTAssertEqual(root, "1")
    }

    func testGenerateNextRoot_incrementsExistingRoots() {
        // Create notes with zettelIds "1" and "2"
        let note1 = createNote(title: "Root 1")
        note1.zettelId = "1"
        let note2 = createNote(title: "Root 2")
        note2.zettelId = "2"
        try? context.save()

        let next = sut.generateNextRoot()
        XCTAssertEqual(next, "3")
    }

    // MARK: - generateContinuation

    func testGenerateContinuation_letterIncrement() {
        let result = sut.generateContinuation(of: "1a")
        XCTAssertEqual(result, "1b")
    }

    func testGenerateContinuation_numberIncrement() {
        let result = sut.generateContinuation(of: "1a1")
        XCTAssertEqual(result, "1a2")
    }

    func testGenerateContinuation_rootIncrement() {
        let result = sut.generateContinuation(of: "1")
        XCTAssertEqual(result, "2")
    }

    func testGenerateContinuation_multiLetterSequence() {
        let result = sut.generateContinuation(of: "1b")
        XCTAssertEqual(result, "1c")
    }

    // MARK: - generateBranch

    func testGenerateBranch_numberToLetter() {
        // "1" ends with number → branch adds letter → "1a"
        let result = sut.generateBranch(from: "1")
        XCTAssertEqual(result, "1a")
    }

    func testGenerateBranch_letterToNumber() {
        // "1a" ends with letter → branch adds number → "1a1"
        let result = sut.generateBranch(from: "1a")
        XCTAssertEqual(result, "1a1")
    }

    func testGenerateBranch_deepAlternation() {
        // "1a1" ends with number → "1a1a"
        let result = sut.generateBranch(from: "1a1")
        XCTAssertEqual(result, "1a1a")
    }

    func testDeepBranching_alternatingPattern() {
        // "1a1a" → "1a1a1"
        let result = sut.generateBranch(from: "1a1a")
        XCTAssertEqual(result, "1a1a1")

        // "1a1a1" → "1a1a1a"
        let result2 = sut.generateBranch(from: "1a1a1")
        XCTAssertEqual(result2, "1a1a1a")
    }

    // MARK: - parentId

    func testParentId_rootReturnsNil() {
        XCTAssertNil(sut.parentId(of: "1"))
    }

    func testParentId_firstLevel() {
        XCTAssertEqual(sut.parentId(of: "1a"), "1")
    }

    func testParentId_secondLevel() {
        XCTAssertEqual(sut.parentId(of: "1a1"), "1a")
    }

    func testParentId_thirdLevel() {
        XCTAssertEqual(sut.parentId(of: "1b"), "1")
    }

    // MARK: - isDescendant

    func testIsDescendant_true() {
        XCTAssertTrue(sut.isDescendant("1a1", of: "1"))
        XCTAssertTrue(sut.isDescendant("1a1a", of: "1a"))
        XCTAssertTrue(sut.isDescendant("1a", of: "1"))
    }

    func testIsDescendant_false() {
        XCTAssertFalse(sut.isDescendant("2a", of: "1"))
        XCTAssertFalse(sut.isDescendant("1", of: "1"))  // same ID
        XCTAssertFalse(sut.isDescendant("1", of: "1a"))  // child shorter than parent
    }

    // MARK: - childrenIds

    func testChildrenIds_returnsImmediateChildren() {
        let n1 = createNote(title: "1"); n1.zettelId = "1"
        let n1a = createNote(title: "1a"); n1a.zettelId = "1a"
        let n1b = createNote(title: "1b"); n1b.zettelId = "1b"
        let n1a1 = createNote(title: "1a1"); n1a1.zettelId = "1a1"
        try? context.save()

        let children = sut.childrenIds(of: "1")
        XCTAssertEqual(children, ["1a", "1b"])
    }

    func testChildrenIds_excludesGrandchildren() {
        let n1 = createNote(title: "1"); n1.zettelId = "1"
        let n1a = createNote(title: "1a"); n1a.zettelId = "1a"
        let n1a1 = createNote(title: "1a1"); n1a1.zettelId = "1a1"
        try? context.save()

        let children = sut.childrenIds(of: "1")
        XCTAssertEqual(children, ["1a"])
        XCTAssertFalse(children.contains("1a1"))
    }

    // MARK: - sequenceFrom

    func testSequenceFrom_depthFirstTraversal() {
        let n1 = createNote(title: "1"); n1.zettelId = "1"
        let n1a = createNote(title: "1a"); n1a.zettelId = "1a"
        let n1a1 = createNote(title: "1a1"); n1a1.zettelId = "1a1"
        let n1b = createNote(title: "1b"); n1b.zettelId = "1b"
        try? context.save()

        let sequence = sut.sequenceFrom(id: "1")
        XCTAssertEqual(sequence, ["1", "1a", "1a1", "1b"])
    }

    // MARK: - depth

    func testDepth_root() {
        XCTAssertEqual(sut.depth(of: "1"), 1)
    }

    func testDepth_levelTwo() {
        XCTAssertEqual(sut.depth(of: "1a"), 2)
    }

    func testDepth_levelThree() {
        XCTAssertEqual(sut.depth(of: "1a1"), 3)
    }

    func testDepth_levelFour() {
        XCTAssertEqual(sut.depth(of: "1a1a"), 4)
    }
}
