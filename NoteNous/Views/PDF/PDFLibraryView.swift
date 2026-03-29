import SwiftUI

/// Browse all imported PDFs with grid/list toggle, sorting, and document management.
struct PDFLibraryView: View {
    @ObservedObject var pdfService: PDFReaderService

    @State private var isGridView: Bool = true
    @State private var sortBy: SortOption = .dateImported
    @State private var selectedDocumentId: UUID?
    @State private var showPDFReader: Bool = false
    @State private var showDeleteConfirmation: Bool = false
    @State private var documentToDelete: UUID?

    enum SortOption: String, CaseIterable {
        case dateImported = "Date Imported"
        case annotationCount = "Annotations"
        case title = "Title"
    }

    private var sortedDocuments: [PDFReaderService.PDFDocumentItem] {
        switch sortBy {
        case .dateImported:
            return pdfService.documents.sorted { $0.importedAt > $1.importedAt }
        case .annotationCount:
            return pdfService.documents.sorted { $0.annotations.count > $1.annotations.count }
        case .title:
            return pdfService.documents.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            headerBar
            Divider().background(Moros.border)

            if pdfService.documents.isEmpty {
                emptyState
            } else if isGridView {
                gridLayout
            } else {
                listLayout
            }
        }

        .sheet(isPresented: $showPDFReader) {
            if let docId = selectedDocumentId {
                PDFReaderView(pdfService: pdfService, documentId: docId)
                    .frame(minWidth: 800, minHeight: 600)
            }
        }
        .alert("Remove Document", isPresented: $showDeleteConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Remove", role: .destructive) {
                if let id = documentToDelete {
                    pdfService.deleteDocument(id: id)
                }
            }
        } message: {
            Text("Remove this document from the library? The file will not be deleted.")
        }
    }

    // MARK: - Header

    private var headerBar: some View {
        HStack(spacing: Moros.spacing12) {
            Text("PDF Library")
                .font(Moros.fontH2)
                .foregroundStyle(Moros.textMain)

            Text("\(pdfService.documents.count) documents")
                .font(Moros.fontSmall)
                .foregroundStyle(Moros.textDim)

            Spacer()

            // Sort picker
            Picker("Sort", selection: $sortBy) {
                ForEach(SortOption.allCases, id: \.self) { option in
                    Text(option.rawValue).tag(option)
                }
            }
            .pickerStyle(.menu)
            .font(Moros.fontSmall)
            .frame(width: 140)

            // View toggle
            HStack(spacing: 0) {
                Button(action: { isGridView = true }) {
                    Image(systemName: "square.grid.2x2")
                        .font(.system(size: 12))
                        .foregroundStyle(isGridView ? Moros.oracle : Moros.textDim)
                        .padding(Moros.spacing4)
                }
                .buttonStyle(.plain)

                Button(action: { isGridView = false }) {
                    Image(systemName: "list.bullet")
                        .font(.system(size: 12))
                        .foregroundStyle(!isGridView ? Moros.oracle : Moros.textDim)
                        .padding(Moros.spacing4)
                }
                .buttonStyle(.plain)
            }
            .background(Moros.limit02)
            .overlay(Rectangle().stroke(Moros.border, lineWidth: 1))

            // Open PDF button
            Button("Open PDF") {
                openPDFFile()
            }
            .buttonStyle(MorosButtonStyle(accent: Moros.oracle))
        }
        .padding(Moros.spacing16)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: Moros.spacing12) {
            Spacer()
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 48))
                .foregroundStyle(Moros.textDim)

            Text("No PDFs in Library")
                .font(Moros.fontH3)
                .foregroundStyle(Moros.textSub)

            Text("Open a PDF file to start annotating and creating notes")
                .font(Moros.fontSmall)
                .foregroundStyle(Moros.textDim)

            Button("Open PDF File") {
                openPDFFile()
            }
            .buttonStyle(MorosButtonStyle(accent: Moros.oracle))
            .padding(.top, Moros.spacing8)

            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Grid Layout

    private var gridLayout: some View {
        ScrollView {
            LazyVGrid(columns: [
                GridItem(.adaptive(minimum: 180, maximum: 220), spacing: Moros.spacing12)
            ], spacing: Moros.spacing12) {
                ForEach(sortedDocuments) { doc in
                    gridCard(doc)
                }
            }
            .padding(Moros.spacing16)
        }
    }

    private func gridCard(_ doc: PDFReaderService.PDFDocumentItem) -> some View {
        VStack(alignment: .leading, spacing: Moros.spacing8) {
            // PDF icon/thumbnail
            ZStack {
                Rectangle()
                    .fill(Moros.limit02)
                    .aspectRatio(0.75, contentMode: .fit)

                VStack(spacing: Moros.spacing4) {
                    Image(systemName: "doc.text.fill")
                        .font(.system(size: 32))
                        .foregroundStyle(Moros.signal.opacity(0.6))

                    Text("\(doc.totalPages) pages")
                        .font(Moros.fontMicro)
                        .foregroundStyle(Moros.textDim)
                }
            }

            Text(doc.title)
                .font(Moros.fontSmall)
                .foregroundStyle(Moros.textMain)
                .lineLimit(2)

            if let author = doc.author {
                Text(author)
                    .font(Moros.fontCaption)
                    .foregroundStyle(Moros.textDim)
                    .lineLimit(1)
            }

            HStack {
                Image(systemName: "highlighter")
                    .font(.system(size: 9))
                    .foregroundStyle(Moros.oracle)
                Text("\(doc.annotations.count)")
                    .font(Moros.fontMicro)
                    .foregroundStyle(Moros.textDim)

                Spacer()

                Text(doc.importedAt.formatted(date: .abbreviated, time: .omitted))
                    .font(Moros.fontMicro)
                    .foregroundStyle(Moros.textGhost)
            }
        }
        .padding(Moros.spacing8)
        .background(Moros.limit02)
        .overlay(Rectangle().stroke(Moros.border, lineWidth: 1))
        .contentShape(Rectangle())
        .onTapGesture {
            selectedDocumentId = doc.id
            showPDFReader = true
        }
        .contextMenu {
            Button("Open") {
                selectedDocumentId = doc.id
                showPDFReader = true
            }
            Divider()
            Button("Remove from Library", role: .destructive) {
                documentToDelete = doc.id
                showDeleteConfirmation = true
            }
        }
    }

    // MARK: - List Layout

    private var listLayout: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(sortedDocuments) { doc in
                    listRow(doc)
                    Divider().background(Moros.border)
                }
            }
        }
    }

    private func listRow(_ doc: PDFReaderService.PDFDocumentItem) -> some View {
        HStack(spacing: Moros.spacing12) {
            Image(systemName: "doc.text.fill")
                .font(.system(size: 20))
                .foregroundStyle(Moros.signal.opacity(0.6))
                .frame(width: 32)

            VStack(alignment: .leading, spacing: Moros.spacing2) {
                Text(doc.title)
                    .font(Moros.fontSmall)
                    .foregroundStyle(Moros.textMain)
                    .lineLimit(1)

                HStack(spacing: Moros.spacing8) {
                    if let author = doc.author {
                        Text(author)
                            .font(Moros.fontCaption)
                            .foregroundStyle(Moros.textDim)
                    }

                    Text("\(doc.totalPages) pages")
                        .font(Moros.fontCaption)
                        .foregroundStyle(Moros.textDim)
                }
            }

            Spacer()

            HStack(spacing: Moros.spacing4) {
                Image(systemName: "highlighter")
                    .font(.system(size: 9))
                    .foregroundStyle(Moros.oracle)
                Text("\(doc.annotations.count)")
                    .font(Moros.fontMono)
                    .foregroundStyle(Moros.textSub)
            }

            Text(doc.importedAt.formatted(date: .abbreviated, time: .omitted))
                .font(Moros.fontCaption)
                .foregroundStyle(Moros.textDim)
                .frame(width: 80, alignment: .trailing)

            Button(action: {
                documentToDelete = doc.id
                showDeleteConfirmation = true
            }) {
                Image(systemName: "trash")
                    .font(.system(size: 11))
                    .foregroundStyle(Moros.signal)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, Moros.spacing16)
        .padding(.vertical, Moros.spacing8)
        .background(Color.clear)
        .contentShape(Rectangle())
        .onTapGesture {
            selectedDocumentId = doc.id
            showPDFReader = true
        }
    }

    // MARK: - File Open

    private func openPDFFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.pdf]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.message = "Select a PDF to add to your library"

        if panel.runModal() == .OK, let url = panel.url {
            let doc = pdfService.openPDF(url: url)
            selectedDocumentId = doc.id
            showPDFReader = true
        }
    }
}
