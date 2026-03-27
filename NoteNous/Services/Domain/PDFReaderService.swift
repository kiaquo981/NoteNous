import Foundation
import CoreData
import PDFKit
import os.log

/// Manages PDF document library and annotations. Persists to JSON in Application Support/NoteNous/.
final class PDFReaderService: ObservableObject {

    // MARK: - Models

    struct PDFAnnotationItem: Identifiable, Codable, Equatable {
        let id: UUID
        var text: String
        var note: String
        var page: Int
        var color: String
        var createdAt: Date
        var noteId: UUID?

        init(
            id: UUID = UUID(),
            text: String,
            note: String = "",
            page: Int,
            color: String = "#4477cc",
            createdAt: Date = Date(),
            noteId: UUID? = nil
        ) {
            self.id = id
            self.text = text
            self.note = note
            self.page = page
            self.color = color
            self.createdAt = createdAt
            self.noteId = noteId
        }
    }

    struct PDFDocumentItem: Identifiable, Codable, Equatable {
        let id: UUID
        var title: String
        var filePath: String
        var author: String?
        var totalPages: Int
        var annotations: [PDFAnnotationItem]
        var sourceId: UUID?
        var importedAt: Date

        init(
            id: UUID = UUID(),
            title: String,
            filePath: String,
            author: String? = nil,
            totalPages: Int = 0,
            annotations: [PDFAnnotationItem] = [],
            sourceId: UUID? = nil,
            importedAt: Date = Date()
        ) {
            self.id = id
            self.title = title
            self.filePath = filePath
            self.author = author
            self.totalPages = totalPages
            self.annotations = annotations
            self.sourceId = sourceId
            self.importedAt = importedAt
        }
    }

    // MARK: - Published State

    @Published var documents: [PDFDocumentItem] = []

    // MARK: - Private

    private let logger = Logger(subsystem: "com.notenous.app", category: "PDFReaderService")
    private let fileURL: URL

    init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("NoteNous", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        self.fileURL = dir.appendingPathComponent("pdf-documents.json")
        loadFromDisk()
    }

    // MARK: - Document Management

    @discardableResult
    func openPDF(url: URL) -> PDFDocumentItem {
        // Check if already registered
        if let existing = documents.first(where: { $0.filePath == url.path }) {
            return existing
        }

        var title = url.deletingPathExtension().lastPathComponent
        var author: String?
        var totalPages = 0

        // Extract metadata from PDFKit
        if let pdfDoc = PDFDocument(url: url) {
            totalPages = pdfDoc.pageCount
            if let attrs = pdfDoc.documentAttributes {
                if let pdfTitle = attrs[PDFDocumentAttribute.titleAttribute] as? String, !pdfTitle.isEmpty {
                    title = pdfTitle
                }
                if let pdfAuthor = attrs[PDFDocumentAttribute.authorAttribute] as? String {
                    author = pdfAuthor
                }
            }
        }

        let doc = PDFDocumentItem(
            title: title,
            filePath: url.path,
            author: author,
            totalPages: totalPages
        )

        documents.append(doc)
        saveToDisk()
        logger.info("Opened PDF: \(title) (\(totalPages) pages)")
        return doc
    }

    func deleteDocument(id: UUID) {
        documents.removeAll { $0.id == id }
        saveToDisk()
        logger.info("Removed document from library: \(id.uuidString)")
    }

    func document(for id: UUID) -> PDFDocumentItem? {
        documents.first { $0.id == id }
    }

    // MARK: - Annotations

    func addAnnotation(to docId: UUID, text: String, note: String, page: Int, color: String) {
        guard let index = documents.firstIndex(where: { $0.id == docId }) else {
            logger.warning("Document not found for annotation: \(docId.uuidString)")
            return
        }

        let annotation = PDFAnnotationItem(
            text: text,
            note: note,
            page: page,
            color: color
        )

        documents[index].annotations.append(annotation)
        saveToDisk()
        logger.info("Added annotation to page \(page)")
    }

    func updateAnnotation(docId: UUID, annotationId: UUID, note: String) {
        guard let docIndex = documents.firstIndex(where: { $0.id == docId }),
              let annIndex = documents[docIndex].annotations.firstIndex(where: { $0.id == annotationId })
        else { return }

        documents[docIndex].annotations[annIndex].note = note
        saveToDisk()
    }

    func deleteAnnotation(docId: UUID, annotationId: UUID) {
        guard let docIndex = documents.firstIndex(where: { $0.id == docId }) else { return }
        documents[docIndex].annotations.removeAll { $0.id == annotationId }
        saveToDisk()
    }

    // MARK: - Note Creation

    func createNoteFromAnnotation(
        _ annotation: PDFAnnotationItem,
        document: PDFDocumentItem,
        noteService: NoteService,
        tagService: TagService,
        sourceService: SourceService
    ) -> NoteEntity {
        var content = "> \(annotation.text)"
        if !annotation.note.isEmpty {
            content += "\n\n**Note:** \(annotation.note)"
        }
        content += "\n\n*Page \(annotation.page + 1) of \(document.title)*"

        let note = noteService.createNote(
            title: "[\(document.title)] p.\(annotation.page + 1)",
            content: content,
            paraCategory: .resource
        )
        note.noteType = .literature
        note.sourceTitle = document.title
        note.sourceURL = document.filePath
        note.updatedAt = Date()

        let pdfTag = tagService.findOrCreate(name: "pdf")
        tagService.addTag(pdfTag, to: note)

        // Link to source if exists
        if let sourceId = document.sourceId, let noteId = note.id {
            sourceService.linkNote(noteId: noteId, to: sourceId)
        }

        // Update annotation with note reference
        if let docIndex = documents.firstIndex(where: { $0.id == document.id }),
           let annIndex = documents[docIndex].annotations.firstIndex(where: { $0.id == annotation.id }) {
            documents[docIndex].annotations[annIndex].noteId = note.id
            saveToDisk()
        }

        logger.info("Created note from PDF annotation")
        return note
    }

    func exportAllAnnotations(
        docId: UUID,
        noteService: NoteService,
        tagService: TagService,
        sourceService: SourceService
    ) -> [NoteEntity] {
        guard let doc = document(for: docId) else { return [] }

        var notes: [NoteEntity] = []
        for annotation in doc.annotations where annotation.noteId == nil {
            let note = createNoteFromAnnotation(
                annotation,
                document: doc,
                noteService: noteService,
                tagService: tagService,
                sourceService: sourceService
            )
            notes.append(note)
        }

        logger.info("Exported \(notes.count) annotations as notes from '\(doc.title)'")
        return notes
    }

    // MARK: - Persistence

    private func saveToDisk() {
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(documents)
            try data.write(to: fileURL, options: .atomicWrite)
        } catch {
            logger.error("Failed to save PDF documents: \(error.localizedDescription)")
        }
    }

    private func loadFromDisk() {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            logger.info("No PDF documents file found, starting fresh")
            return
        }
        do {
            let data = try Data(contentsOf: fileURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            documents = try decoder.decode([PDFDocumentItem].self, from: data)
            logger.info("Loaded \(self.documents.count) PDF documents from disk")
        } catch {
            logger.error("Failed to load PDF documents: \(error.localizedDescription)")
            documents = []
        }
    }
}
