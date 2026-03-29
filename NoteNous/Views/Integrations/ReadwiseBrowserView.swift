import SwiftUI

/// Browse imported Readwise content — books, highlights, and notes.
struct ReadwiseBrowserView: View {
    @ObservedObject var readwiseService: ReadwiseService

    @State private var books: [ReadwiseService.ReadwiseBook] = []
    @State private var selectedBook: ReadwiseService.ReadwiseBook?
    @State private var highlights: [ReadwiseService.ReadwiseHighlight] = []
    @State private var isLoadingBooks: Bool = false
    @State private var isLoadingHighlights: Bool = false
    @State private var searchText: String = ""
    @State private var selectedCategory: String = "all"
    @State private var errorMessage: String?

    private let categories = ["all", "books", "articles", "tweets", "podcasts"]

    var body: some View {
        HSplitView {
            bookListPanel
                .frame(minWidth: 260, maxWidth: 360)
            highlightDetailPanel
                .frame(minWidth: 400)
        }

        .onAppear { loadBooks() }
    }

    // MARK: - Book List

    private var bookListPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            VStack(alignment: .leading, spacing: Moros.spacing8) {
                Text("Readwise Library")
                    .font(Moros.fontH3)
                    .foregroundStyle(Moros.textMain)

                // Search
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(Moros.textDim)
                    TextField("Search books...", text: $searchText)
                        .textFieldStyle(.plain)
                        .font(Moros.fontSmall)
                        .foregroundStyle(Moros.textMain)
                }
                .padding(Moros.spacing8)
                .background(Moros.limit02)
                .overlay(Rectangle().stroke(Moros.border, lineWidth: 1))

                // Category filter
                HStack(spacing: Moros.spacing4) {
                    ForEach(categories, id: \.self) { cat in
                        Button(cat.capitalized) {
                            selectedCategory = cat
                        }
                        .font(Moros.fontCaption)
                        .foregroundStyle(selectedCategory == cat ? Moros.oracle : Moros.textDim)
                        .padding(.horizontal, Moros.spacing4)
                        .padding(.vertical, 2)
                        .background(selectedCategory == cat ? Moros.limit03 : Color.clear)
                        .overlay(
                            Rectangle()
                                .stroke(selectedCategory == cat ? Moros.oracle.opacity(0.3) : Color.clear, lineWidth: 1)
                        )
                    }
                }
            }
            .padding(Moros.spacing12)

            Divider().background(Moros.border)

            // Book list
            if isLoadingBooks {
                Spacer()
                HStack {
                    Spacer()
                    ProgressView()
                        .controlSize(.small)
                    Text("Loading books...")
                        .font(Moros.fontSmall)
                        .foregroundStyle(Moros.textDim)
                    Spacer()
                }
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(filteredBooks) { book in
                            bookRow(book)
                                .onTapGesture { selectBook(book) }
                        }
                    }
                }
            }
        }

    }

    private func bookRow(_ book: ReadwiseService.ReadwiseBook) -> some View {
        HStack(spacing: Moros.spacing8) {
            // Cover placeholder
            if let coverURL = book.cover_image_url, let url = URL(string: coverURL) {
                AsyncImage(url: url) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } placeholder: {
                    Rectangle()
                        .fill(Moros.limit03)
                }
                .frame(width: 36, height: 48)
                .clipped()
            } else {
                Rectangle()
                    .fill(Moros.limit03)
                    .frame(width: 36, height: 48)
                    .overlay(
                        Image(systemName: iconForCategory(book.category))
                            .foregroundStyle(Moros.textDim)
                            .font(.system(size: 14))
                    )
            }

            VStack(alignment: .leading, spacing: Moros.spacing2) {
                Text(book.title)
                    .font(Moros.fontSmall)
                    .foregroundStyle(Moros.textMain)
                    .lineLimit(2)

                if let author = book.author {
                    Text(author)
                        .font(Moros.fontCaption)
                        .foregroundStyle(Moros.textDim)
                        .lineLimit(1)
                }

                HStack(spacing: Moros.spacing4) {
                    Text(book.category.capitalized)
                        .font(Moros.fontMicro)
                        .foregroundStyle(Moros.oracle)

                    Text("\(book.num_highlights) highlights")
                        .font(Moros.fontMicro)
                        .foregroundStyle(Moros.textDim)
                }
            }

            Spacer()
        }
        .padding(.horizontal, Moros.spacing12)
        .padding(.vertical, Moros.spacing8)
        .background(selectedBook?.id == book.id ? Moros.limit03 : Color.clear)
        .contentShape(Rectangle())
    }

    // MARK: - Highlight Detail

    private var highlightDetailPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let book = selectedBook {
                // Book header
                VStack(alignment: .leading, spacing: Moros.spacing4) {
                    Text(book.title)
                        .font(Moros.fontH2)
                        .foregroundStyle(Moros.textMain)

                    if let author = book.author {
                        Text("by \(author)")
                            .font(Moros.fontBody)
                            .foregroundStyle(Moros.textSub)
                    }

                    Text("\(book.num_highlights) highlights")
                        .font(Moros.fontSmall)
                        .foregroundStyle(Moros.textDim)
                }
                .padding(Moros.spacing16)

                Divider().background(Moros.border)

                if isLoadingHighlights {
                    Spacer()
                    HStack {
                        Spacer()
                        ProgressView()
                            .controlSize(.small)
                        Text("Loading highlights...")
                            .font(Moros.fontSmall)
                            .foregroundStyle(Moros.textDim)
                        Spacer()
                    }
                    Spacer()
                } else {
                    ScrollView {
                        LazyVStack(spacing: Moros.spacing8) {
                            ForEach(filteredHighlights) { highlight in
                                highlightCard(highlight, bookTitle: book.title)
                            }
                        }
                        .padding(Moros.spacing12)
                    }
                }
            } else {
                Spacer()
                VStack(spacing: Moros.spacing8) {
                    Image(systemName: "book.closed")
                        .font(.system(size: 32))
                        .foregroundStyle(Moros.textDim)
                    Text("Select a book to view highlights")
                        .font(Moros.fontBody)
                        .foregroundStyle(Moros.textDim)
                }
                .frame(maxWidth: .infinity)
                Spacer()
            }
        }

    }

    private func highlightCard(_ highlight: ReadwiseService.ReadwiseHighlight, bookTitle: String) -> some View {
        VStack(alignment: .leading, spacing: Moros.spacing8) {
            // Highlight text
            Text(highlight.text)
                .font(Moros.fontBody)
                .foregroundStyle(Moros.textMain)
                .italic()
                .padding(.leading, Moros.spacing8)
                .overlay(
                    Rectangle()
                        .fill(highlightColor(highlight.color))
                        .frame(width: 3),
                    alignment: .leading
                )

            // User note
            if let note = highlight.note, !note.isEmpty {
                HStack(spacing: Moros.spacing4) {
                    Image(systemName: "note.text")
                        .font(.system(size: 10))
                        .foregroundStyle(Moros.oracle)
                    Text(note)
                        .font(Moros.fontSmall)
                        .foregroundStyle(Moros.textSub)
                }
            }

            // Tags
            if let tags = highlight.tags, !tags.isEmpty {
                HStack(spacing: Moros.spacing4) {
                    ForEach(tags, id: \.name) { tag in
                        Text("#\(tag.name)")
                            .font(Moros.fontMicro)
                            .foregroundStyle(Moros.oracle)
                            .padding(.horizontal, Moros.spacing4)
                            .padding(.vertical, 1)
                            .background(Moros.oracle.opacity(0.1))
                    }
                }
            }

            // Metadata row
            HStack {
                if let location = highlight.location {
                    Text("Loc \(location)")
                        .font(Moros.fontMicro)
                        .foregroundStyle(Moros.textDim)
                }

                Spacer()

                Button("Create Note") {
                    NotificationCenter.default.post(
                        name: .readwiseCreateNoteFromHighlight,
                        object: nil,
                        userInfo: [
                            "text": highlight.text,
                            "note": highlight.note ?? "",
                            "bookTitle": bookTitle,
                            "url": highlight.url ?? ""
                        ]
                    )
                }
                .font(Moros.fontCaption)
                .foregroundStyle(Moros.oracle)
                .buttonStyle(.plain)
            }
        }
        .padding(Moros.spacing12)
        .background(Moros.limit02)
        .overlay(Rectangle().stroke(Moros.border, lineWidth: 1))
    }

    // MARK: - Filtering

    private var filteredBooks: [ReadwiseService.ReadwiseBook] {
        var result = books
        if selectedCategory != "all" {
            result = result.filter { $0.category.lowercased() == selectedCategory }
        }
        if !searchText.isEmpty {
            result = result.filter {
                $0.title.localizedCaseInsensitiveContains(searchText) ||
                ($0.author?.localizedCaseInsensitiveContains(searchText) ?? false)
            }
        }
        return result
    }

    private var filteredHighlights: [ReadwiseService.ReadwiseHighlight] {
        if searchText.isEmpty { return highlights }
        return highlights.filter {
            $0.text.localizedCaseInsensitiveContains(searchText) ||
            ($0.note?.localizedCaseInsensitiveContains(searchText) ?? false)
        }
    }

    // MARK: - Actions

    private func loadBooks() {
        guard readwiseService.isConfigured else { return }
        isLoadingBooks = true
        Task {
            do {
                let fetched = try await readwiseService.fetchBooks()
                await MainActor.run {
                    books = fetched
                    isLoadingBooks = false
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    isLoadingBooks = false
                }
            }
        }
    }

    private func selectBook(_ book: ReadwiseService.ReadwiseBook) {
        selectedBook = book
        isLoadingHighlights = true
        Task {
            do {
                let fetched = try await readwiseService.fetchHighlights(bookId: book.id)
                await MainActor.run {
                    highlights = fetched
                    isLoadingHighlights = false
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    isLoadingHighlights = false
                }
            }
        }
    }

    // MARK: - Helpers

    private func iconForCategory(_ category: String) -> String {
        switch category.lowercased() {
        case "books": return "book.closed"
        case "articles": return "doc.text"
        case "tweets": return "at"
        case "podcasts": return "waveform"
        default: return "ellipsis.circle"
        }
    }

    private func highlightColor(_ color: String?) -> Color {
        switch color?.lowercased() {
        case "yellow": return .yellow
        case "blue": return Moros.oracle
        case "red": return Moros.signal
        case "green": return .green
        case "orange": return .orange
        default: return Moros.oracle
        }
    }
}

// MARK: - Notification

extension Notification.Name {
    static let readwiseCreateNoteFromHighlight = Notification.Name("readwiseCreateNoteFromHighlight")
}
