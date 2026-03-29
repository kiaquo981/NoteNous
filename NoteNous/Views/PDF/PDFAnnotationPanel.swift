import SwiftUI

/// Side panel showing all annotations for the current PDF document.
struct PDFAnnotationPanel: View {
    @ObservedObject var pdfService: PDFReaderService
    let documentId: UUID
    var onNavigateToPage: ((Int) -> Void)?

    @State private var editingAnnotationId: UUID?
    @State private var editNote: String = ""
    @State private var filterColor: String?
    @State private var filterPageFrom: String = ""
    @State private var filterPageTo: String = ""
    @State private var showFilters: Bool = false

    private var document: PDFReaderService.PDFDocumentItem? {
        pdfService.document(for: documentId)
    }

    private var annotations: [PDFReaderService.PDFAnnotationItem] {
        guard let doc = document else { return [] }
        var filtered = doc.annotations

        if let color = filterColor {
            filtered = filtered.filter { $0.color == color }
        }

        if let from = Int(filterPageFrom), from > 0 {
            filtered = filtered.filter { $0.page >= from - 1 }
        }
        if let to = Int(filterPageTo), to > 0 {
            filtered = filtered.filter { $0.page <= to - 1 }
        }

        return filtered.sorted { $0.page < $1.page }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            VStack(alignment: .leading, spacing: Moros.spacing8) {
                HStack {
                    Text("Annotations")
                        .font(Moros.fontH3)
                        .foregroundStyle(Moros.textMain)

                    Spacer()

                    Text("\(annotations.count)")
                        .font(Moros.fontMono)
                        .foregroundStyle(Moros.oracle)

                    Button(action: { showFilters.toggle() }) {
                        Image(systemName: "line.3.horizontal.decrease")
                            .font(.system(size: 11))
                            .foregroundStyle(showFilters ? Moros.oracle : Moros.textDim)
                    }
                    .buttonStyle(.plain)
                }

                if showFilters {
                    filtersSection
                }
            }
            .padding(Moros.spacing12)

            Divider().background(Moros.border)

            // Annotations list
            if annotations.isEmpty {
                Spacer()
                VStack(spacing: Moros.spacing8) {
                    Image(systemName: "highlighter")
                        .font(.system(size: 24))
                        .foregroundStyle(Moros.textDim)
                    Text("No annotations yet")
                        .font(Moros.fontSmall)
                        .foregroundStyle(Moros.textDim)
                    Text("Select text in the PDF to create annotations")
                        .font(Moros.fontCaption)
                        .foregroundStyle(Moros.textGhost)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: Moros.spacing4) {
                        ForEach(annotations) { annotation in
                            annotationRow(annotation)
                        }
                    }
                    .padding(Moros.spacing8)
                }
            }

            Divider().background(Moros.border)

            // Footer actions
            HStack {
                Button("Export All as Notes") {
                    NotificationCenter.default.post(
                        name: .pdfExportAllAnnotations,
                        object: nil,
                        userInfo: ["documentId": documentId]
                    )
                }
                .font(Moros.fontCaption)
                .foregroundStyle(Moros.oracle)
                .buttonStyle(.plain)
                .disabled(annotations.isEmpty)

                Spacer()
            }
            .padding(Moros.spacing12)
        }

    }

    // MARK: - Filters

    private var filtersSection: some View {
        VStack(alignment: .leading, spacing: Moros.spacing4) {
            // Color filter
            HStack(spacing: Moros.spacing4) {
                Text("Color:")
                    .font(Moros.fontCaption)
                    .foregroundStyle(Moros.textDim)

                Button("All") { filterColor = nil }
                    .font(Moros.fontMicro)
                    .foregroundStyle(filterColor == nil ? Moros.oracle : Moros.textDim)
                    .buttonStyle(.plain)

                ForEach(colorOptions, id: \.0) { hex, color in
                    Button(action: { filterColor = hex }) {
                        Circle()
                            .fill(color)
                            .frame(width: 10, height: 10)
                            .overlay(
                                Circle()
                                    .stroke(filterColor == hex ? Color.white : Color.clear, lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }

            // Page range filter
            HStack(spacing: Moros.spacing4) {
                Text("Pages:")
                    .font(Moros.fontCaption)
                    .foregroundStyle(Moros.textDim)

                TextField("from", text: $filterPageFrom)
                    .textFieldStyle(.plain)
                    .font(Moros.fontMono)
                    .frame(width: 36)
                    .padding(2)
                    .background(Moros.limit02)
                    .overlay(Rectangle().stroke(Moros.border, lineWidth: 1))

                Text("-")
                    .font(Moros.fontCaption)
                    .foregroundStyle(Moros.textDim)

                TextField("to", text: $filterPageTo)
                    .textFieldStyle(.plain)
                    .font(Moros.fontMono)
                    .frame(width: 36)
                    .padding(2)
                    .background(Moros.limit02)
                    .overlay(Rectangle().stroke(Moros.border, lineWidth: 1))
            }
        }
        .padding(Moros.spacing8)
        .background(Moros.limit02)
        .overlay(Rectangle().stroke(Moros.border, lineWidth: 1))
    }

    // MARK: - Annotation Row

    private func annotationRow(_ annotation: PDFReaderService.PDFAnnotationItem) -> some View {
        VStack(alignment: .leading, spacing: Moros.spacing4) {
            // Header
            HStack(spacing: Moros.spacing4) {
                Rectangle()
                    .fill(colorFromHex(annotation.color))
                    .frame(width: 3, height: 12)

                Text("p.\(annotation.page + 1)")
                    .font(Moros.fontMono)
                    .foregroundStyle(Moros.textDim)

                Spacer()

                if annotation.noteId != nil {
                    Image(systemName: "link")
                        .font(.system(size: 9))
                        .foregroundStyle(Moros.oracle)
                }

                // Edit button
                Button(action: {
                    if editingAnnotationId == annotation.id {
                        editingAnnotationId = nil
                    } else {
                        editingAnnotationId = annotation.id
                        editNote = annotation.note
                    }
                }) {
                    Image(systemName: "pencil")
                        .font(.system(size: 9))
                        .foregroundStyle(Moros.textDim)
                }
                .buttonStyle(.plain)

                // Delete button
                Button(action: {
                    pdfService.deleteAnnotation(docId: documentId, annotationId: annotation.id)
                }) {
                    Image(systemName: "trash")
                        .font(.system(size: 9))
                        .foregroundStyle(Moros.signal)
                }
                .buttonStyle(.plain)
            }

            // Highlighted text
            Text(annotation.text)
                .font(Moros.fontSmall)
                .foregroundStyle(Moros.textMain)
                .lineLimit(3)

            // Note
            if !annotation.note.isEmpty && editingAnnotationId != annotation.id {
                Text(annotation.note)
                    .font(Moros.fontCaption)
                    .foregroundStyle(Moros.textSub)
                    .lineLimit(2)
            }

            // Edit mode
            if editingAnnotationId == annotation.id {
                HStack(spacing: Moros.spacing4) {
                    TextField("Add note...", text: $editNote)
                        .textFieldStyle(.plain)
                        .font(Moros.fontCaption)
                        .padding(4)
                        .background(Moros.limit03)
                        .overlay(Rectangle().stroke(Moros.border, lineWidth: 1))

                    Button("Save") {
                        pdfService.updateAnnotation(docId: documentId, annotationId: annotation.id, note: editNote)
                        editingAnnotationId = nil
                    }
                    .font(Moros.fontMicro)
                    .foregroundStyle(Moros.oracle)
                    .buttonStyle(.plain)
                }
            }

            // Actions
            HStack(spacing: Moros.spacing8) {
                Button("Go to page") {
                    onNavigateToPage?(annotation.page)
                }
                .font(Moros.fontMicro)
                .foregroundStyle(Moros.oracle)
                .buttonStyle(.plain)

                if annotation.noteId == nil {
                    Button("Create Note") {
                        NotificationCenter.default.post(
                            name: .pdfCreateNoteFromAnnotation,
                            object: nil,
                            userInfo: [
                                "documentId": documentId,
                                "annotationId": annotation.id
                            ]
                        )
                    }
                    .font(Moros.fontMicro)
                    .foregroundStyle(Moros.oracle)
                    .buttonStyle(.plain)
                }

                Spacer()

                Text(annotation.createdAt.formatted(date: .abbreviated, time: .omitted))
                    .font(Moros.fontMicro)
                    .foregroundStyle(Moros.textGhost)
            }
        }
        .padding(Moros.spacing8)
        .background(Moros.limit02)
        .overlay(Rectangle().stroke(Moros.border, lineWidth: 1))
        .contentShape(Rectangle())
    }

    // MARK: - Helpers

    private let colorOptions: [(String, Color)] = [
        ("#4477cc", Moros.oracle),
        ("#cc2233", Moros.signal),
        ("#33aa55", Color.green),
        ("#8899bb", Moros.ambient)
    ]

    private func colorFromHex(_ hex: String) -> Color {
        switch hex {
        case "#4477cc": return Moros.oracle
        case "#cc2233": return Moros.signal
        case "#33aa55": return Color.green
        case "#8899bb": return Moros.ambient
        default: return Moros.oracle
        }
    }
}

// MARK: - Notifications

extension Notification.Name {
    static let pdfExportAllAnnotations = Notification.Name("pdfExportAllAnnotations")
    static let pdfCreateNoteFromAnnotation = Notification.Name("pdfCreateNoteFromAnnotation")
}
