import XCTest
@testable import NoteNous

final class PDFReaderServiceTests: XCTestCase {

    // Test using PDFReaderService's model types directly (they are Codable structs).
    // We test document/annotation CRUD on the struct level to avoid file system side effects.

    typealias PDFDocumentItem = PDFReaderService.PDFDocumentItem
    typealias PDFAnnotationItem = PDFReaderService.PDFAnnotationItem

    // MARK: - testAddDocument

    func testAddDocument() {
        var documents: [PDFDocumentItem] = []

        let doc = PDFDocumentItem(
            title: "Test PDF",
            filePath: "/tmp/test.pdf",
            author: "Author",
            totalPages: 42
        )
        documents.append(doc)

        XCTAssertEqual(documents.count, 1)
        XCTAssertEqual(documents[0].title, "Test PDF")
        XCTAssertEqual(documents[0].filePath, "/tmp/test.pdf")
        XCTAssertEqual(documents[0].author, "Author")
        XCTAssertEqual(documents[0].totalPages, 42)
        XCTAssertTrue(documents[0].annotations.isEmpty)
    }

    // MARK: - testAddAnnotation

    func testAddAnnotation() {
        var doc = PDFDocumentItem(
            title: "Annotated PDF",
            filePath: "/tmp/annotated.pdf",
            totalPages: 10
        )

        let annotation = PDFAnnotationItem(
            text: "Important passage",
            note: "My note about this",
            page: 3,
            color: "#FF0000"
        )
        doc.annotations.append(annotation)

        XCTAssertEqual(doc.annotations.count, 1)
        XCTAssertEqual(doc.annotations[0].text, "Important passage")
        XCTAssertEqual(doc.annotations[0].note, "My note about this")
        XCTAssertEqual(doc.annotations[0].page, 3)
        XCTAssertEqual(doc.annotations[0].color, "#FF0000")
    }

    // MARK: - testDeleteAnnotation

    func testDeleteAnnotation() {
        var doc = PDFDocumentItem(
            title: "Test",
            filePath: "/tmp/test.pdf",
            totalPages: 5
        )

        let ann1 = PDFAnnotationItem(text: "First", page: 1)
        let ann2 = PDFAnnotationItem(text: "Second", page: 2)
        doc.annotations.append(contentsOf: [ann1, ann2])

        XCTAssertEqual(doc.annotations.count, 2)

        // Delete first annotation
        doc.annotations.removeAll { $0.id == ann1.id }

        XCTAssertEqual(doc.annotations.count, 1)
        XCTAssertEqual(doc.annotations[0].text, "Second")
    }

    // MARK: - testPersistence (encode/decode round-trip)

    func testPersistence() throws {
        let annotation = PDFAnnotationItem(
            text: "Highlighted text",
            note: "My note",
            page: 7,
            color: "#4477CC"
        )

        let doc = PDFDocumentItem(
            title: "Persisted PDF",
            filePath: "/tmp/persisted.pdf",
            author: "Test Author",
            totalPages: 100,
            annotations: [annotation]
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode([doc])

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let loaded = try decoder.decode([PDFDocumentItem].self, from: data)

        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded[0].title, "Persisted PDF")
        XCTAssertEqual(loaded[0].author, "Test Author")
        XCTAssertEqual(loaded[0].totalPages, 100)
        XCTAssertEqual(loaded[0].annotations.count, 1)
        XCTAssertEqual(loaded[0].annotations[0].text, "Highlighted text")
        XCTAssertEqual(loaded[0].annotations[0].page, 7)
        XCTAssertEqual(loaded[0].id, doc.id, "UUID should survive round-trip")
    }
}
