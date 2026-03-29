import SwiftUI
import PDFKit

/// PDF viewer using macOS PDFKit with MOROS theme, text selection, and annotation support.
struct PDFReaderView: View {
    @ObservedObject var pdfService: PDFReaderService
    let documentId: UUID

    @State private var currentPage: Int = 0
    @State private var totalPages: Int = 0
    @State private var pageInput: String = "1"
    @State private var scaleFactor: CGFloat = 1.0
    @State private var selectedText: String = ""
    @State private var showAnnotationSheet: Bool = false
    @State private var annotationNote: String = ""
    @State private var selectedColor: String = "#4477cc"
    @State private var showAnnotationPanel: Bool = true

    private let highlightColors: [(String, String, Color)] = [
        ("ORACLE", "#4477cc", Moros.oracle),
        ("SIGNAL", "#cc2233", Moros.signal),
        ("VERDIT", "#33aa55", Color.green),
        ("AMBIENT", "#8899bb", Moros.ambient)
    ]

    var body: some View {
        if let doc = pdfService.document(for: documentId) {
            HSplitView {
                VStack(spacing: 0) {
                    toolbar(doc: doc)
                    Divider().background(Moros.border)
                    pdfViewRepresentable(doc: doc)
                }
                .frame(minWidth: 500)

                if showAnnotationPanel {
                    PDFAnnotationPanel(
                        pdfService: pdfService,
                        documentId: documentId,
                        onNavigateToPage: { page in
                            currentPage = page
                            pageInput = "\(page + 1)"
                        }
                    )
                    .frame(minWidth: 260, maxWidth: 360)
                }
            }
    
            .sheet(isPresented: $showAnnotationSheet) {
                annotationCreationSheet(doc: doc)
            }
        } else {
            VStack(spacing: Moros.spacing8) {
                Image(systemName: "doc.text")
                    .font(.system(size: 32))
                    .foregroundStyle(Moros.textDim)
                Text("Document not found")
                    .font(Moros.fontBody)
                    .foregroundStyle(Moros.textDim)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    
        }
    }

    // MARK: - Toolbar

    private func toolbar(doc: PDFReaderService.PDFDocumentItem) -> some View {
        HStack(spacing: Moros.spacing12) {
            Text(doc.title)
                .font(Moros.fontSmall)
                .foregroundStyle(Moros.textMain)
                .lineLimit(1)

            Spacer()

            // Page navigation
            HStack(spacing: Moros.spacing4) {
                Button(action: { navigatePage(-1) }) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 11))
                }
                .buttonStyle(.plain)
                .foregroundStyle(Moros.textSub)
                .disabled(currentPage <= 0)

                TextField("", text: $pageInput)
                    .textFieldStyle(.plain)
                    .font(Moros.fontMono)
                    .foregroundStyle(Moros.textMain)
                    .frame(width: 36)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 2)
                    .background(Moros.limit02)
                    .overlay(Rectangle().stroke(Moros.border, lineWidth: 1))
                    .onSubmit {
                        if let page = Int(pageInput), page >= 1, page <= totalPages {
                            currentPage = page - 1
                        } else {
                            pageInput = "\(currentPage + 1)"
                        }
                    }

                Text("/ \(totalPages)")
                    .font(Moros.fontMono)
                    .foregroundStyle(Moros.textDim)

                Button(action: { navigatePage(1) }) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11))
                }
                .buttonStyle(.plain)
                .foregroundStyle(Moros.textSub)
                .disabled(currentPage >= totalPages - 1)
            }

            Divider()
                .frame(height: 16)
                .background(Moros.border)

            // Zoom controls
            HStack(spacing: Moros.spacing4) {
                Button(action: { scaleFactor = max(0.25, scaleFactor - 0.25) }) {
                    Image(systemName: "minus.magnifyingglass")
                        .font(.system(size: 11))
                }
                .buttonStyle(.plain)
                .foregroundStyle(Moros.textSub)

                Text("\(Int(scaleFactor * 100))%")
                    .font(Moros.fontMono)
                    .foregroundStyle(Moros.textDim)
                    .frame(width: 40)

                Button(action: { scaleFactor = min(4.0, scaleFactor + 0.25) }) {
                    Image(systemName: "plus.magnifyingglass")
                        .font(.system(size: 11))
                }
                .buttonStyle(.plain)
                .foregroundStyle(Moros.textSub)
            }

            Divider()
                .frame(height: 16)
                .background(Moros.border)

            // Create note from selection
            if !selectedText.isEmpty {
                Button("Create Note") {
                    annotationNote = ""
                    showAnnotationSheet = true
                }
                .buttonStyle(MorosButtonStyle(accent: Moros.oracle))
            }

            // Toggle annotation panel
            Button(action: { showAnnotationPanel.toggle() }) {
                Image(systemName: showAnnotationPanel ? "sidebar.right" : "sidebar.right")
                    .font(.system(size: 12))
                    .foregroundStyle(showAnnotationPanel ? Moros.oracle : Moros.textDim)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, Moros.spacing12)
        .padding(.vertical, Moros.spacing8)
        .background(Moros.limit02)
    }

    // MARK: - PDF View

    private func pdfViewRepresentable(doc: PDFReaderService.PDFDocumentItem) -> some View {
        PDFKitViewRepresentable(
            filePath: doc.filePath,
            currentPage: $currentPage,
            totalPages: $totalPages,
            scaleFactor: $scaleFactor,
            selectedText: $selectedText
        )
    }

    // MARK: - Annotation Sheet

    private func annotationCreationSheet(doc: PDFReaderService.PDFDocumentItem) -> some View {
        VStack(alignment: .leading, spacing: Moros.spacing12) {
            Text("Create Annotation")
                .font(Moros.fontH3)
                .foregroundStyle(Moros.textMain)

            // Selected text preview
            Text(selectedText)
                .font(Moros.fontSmall)
                .foregroundStyle(Moros.textSub)
                .italic()
                .padding(Moros.spacing8)
                .background(Moros.limit02)
                .overlay(Rectangle().stroke(Moros.border, lineWidth: 1))
                .lineLimit(5)

            // Note field
            Text("Note")
                .font(Moros.fontCaption)
                .foregroundStyle(Moros.textDim)

            TextEditor(text: $annotationNote)
                .font(Moros.fontSmall)
                .foregroundStyle(Moros.textMain)
                .frame(height: 80)
                .padding(Moros.spacing4)
                .background(Moros.limit02)
                .overlay(Rectangle().stroke(Moros.border, lineWidth: 1))

            // Color picker
            Text("Highlight Color")
                .font(Moros.fontCaption)
                .foregroundStyle(Moros.textDim)

            HStack(spacing: Moros.spacing8) {
                ForEach(highlightColors, id: \.0) { name, hex, color in
                    VStack(spacing: Moros.spacing2) {
                        Rectangle()
                            .fill(color)
                            .frame(width: 24, height: 24)
                            .overlay(
                                Rectangle()
                                    .stroke(selectedColor == hex ? Color.white : Color.clear, lineWidth: 2)
                            )
                        Text(name)
                            .font(Moros.fontMicro)
                            .foregroundStyle(Moros.textDim)
                    }
                    .onTapGesture { selectedColor = hex }
                }
            }

            HStack {
                Spacer()
                Button("Cancel") {
                    showAnnotationSheet = false
                }
                .buttonStyle(MorosButtonStyle())

                Button("Save") {
                    pdfService.addAnnotation(
                        to: documentId,
                        text: selectedText,
                        note: annotationNote,
                        page: currentPage,
                        color: selectedColor
                    )
                    showAnnotationSheet = false
                    selectedText = ""
                }
                .buttonStyle(MorosButtonStyle(accent: Moros.oracle))
            }
        }
        .padding(Moros.spacing20)
        .frame(width: 420)

    }

    // MARK: - Navigation

    private func navigatePage(_ delta: Int) {
        let newPage = currentPage + delta
        guard newPage >= 0, newPage < totalPages else { return }
        currentPage = newPage
        pageInput = "\(newPage + 1)"
    }
}

// MARK: - PDFKit NSViewRepresentable

struct PDFKitViewRepresentable: NSViewRepresentable {
    let filePath: String
    @Binding var currentPage: Int
    @Binding var totalPages: Int
    @Binding var scaleFactor: CGFloat
    @Binding var selectedText: String

    func makeNSView(context: Context) -> PDFView {
        let pdfView = PDFView()
        pdfView.autoScales = true
        pdfView.displayMode = .singlePageContinuous
        pdfView.displayDirection = .vertical
        pdfView.backgroundColor = NSColor(Moros.void)

        if let doc = PDFDocument(url: URL(fileURLWithPath: filePath)) {
            pdfView.document = doc
            DispatchQueue.main.async {
                totalPages = doc.pageCount
            }
        }

        // Observe page changes
        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.pageChanged(_:)),
            name: .PDFViewPageChanged,
            object: pdfView
        )

        // Observe selection changes
        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.selectionChanged(_:)),
            name: .PDFViewSelectionChanged,
            object: pdfView
        )

        context.coordinator.pdfView = pdfView
        return pdfView
    }

    func updateNSView(_ pdfView: PDFView, context: Context) {
        pdfView.scaleFactor = scaleFactor

        // Navigate to page if changed externally
        if let doc = pdfView.document,
           currentPage >= 0,
           currentPage < doc.pageCount,
           let page = doc.page(at: currentPage) {
            if pdfView.currentPage != page {
                pdfView.go(to: page)
            }
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject {
        var parent: PDFKitViewRepresentable
        weak var pdfView: PDFView?

        init(_ parent: PDFKitViewRepresentable) {
            self.parent = parent
        }

        @objc func pageChanged(_ notification: Notification) {
            guard let pdfView = pdfView,
                  let currentPage = pdfView.currentPage,
                  let doc = pdfView.document,
                  let pageIndex = doc.index(for: currentPage) as Int?
            else { return }
            DispatchQueue.main.async {
                self.parent.currentPage = pageIndex
            }
        }

        @objc func selectionChanged(_ notification: Notification) {
            guard let pdfView = pdfView else { return }
            let text = pdfView.currentSelection?.string ?? ""
            DispatchQueue.main.async {
                self.parent.selectedText = text
            }
        }
    }
}
