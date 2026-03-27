import SwiftUI
import CoreData

// MARK: - Search Mode

enum SearchMode: String, CaseIterable, Identifiable {
    case keyword = "Keyword"
    case semantic = "Semantic"
    case both = "Both"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .keyword: return "text.magnifyingglass"
        case .semantic: return "brain"
        case .both: return "sparkles"
        }
    }
}

// MARK: - Semantic Search Result

struct SemanticSearchResult: Identifiable {
    let id: UUID
    let note: NoteEntity
    let similarity: Float
    let matchSource: SearchMode

    var similarityPercent: Int {
        Int(similarity * 100)
    }
}

// MARK: - SemanticSearchView

struct SemanticSearchView: View {
    @Environment(\.managedObjectContext) private var context
    @EnvironmentObject var appState: AppState
    @ObservedObject var embeddingService: EmbeddingService

    @State private var query: String = ""
    @State private var searchMode: SearchMode = .both
    @State private var results: [SemanticSearchResult] = []
    @State private var isSearching: Bool = false
    @State private var searchTask: Task<Void, Never>?

    var body: some View {
        VStack(spacing: 0) {
            // Header
            headerView

            Rectangle().fill(Moros.border).frame(height: 1)

            // Search field
            searchFieldView

            Rectangle().fill(Moros.border).frame(height: 1)

            // Mode picker + index status
            controlsBar

            Rectangle().fill(Moros.border).frame(height: 1)

            // Results
            if results.isEmpty && !query.isEmpty && !isSearching {
                noResultsView
            } else if results.isEmpty && query.isEmpty {
                emptyStateView
            } else {
                resultsList
            }
        }
        .morosBackground(Moros.limit01)
        .preferredColorScheme(.dark)
    }

    // MARK: - Header

    private var headerView: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(Moros.oracle)
            Text("Semantic Search")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Moros.textMain)
            Spacer()
            if embeddingService.isIndexing {
                ProgressView()
                    .controlSize(.small)
                    .padding(.trailing, 4)
            }
            Button("Re-index All") {
                Task {
                    await embeddingService.indexAllNotes(context: context)
                }
            }
            .font(Moros.fontCaption)
            .foregroundStyle(Moros.oracle)
            .buttonStyle(.plain)
            .disabled(embeddingService.isIndexing)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // MARK: - Search Field

    private var searchFieldView: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(Moros.textDim)

            TextField("Search across all your notes using natural language...", text: $query)
                .textFieldStyle(.plain)
                .font(Moros.fontBody)
                .foregroundStyle(Moros.textMain)
                .onChange(of: query) {
                    debouncedSearch()
                }

            if !query.isEmpty {
                Button {
                    query = ""
                    results = []
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Moros.textDim)
                }
                .buttonStyle(.plain)
            }

            if isSearching {
                ProgressView()
                    .controlSize(.small)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Moros.limit02)
    }

    // MARK: - Controls Bar

    private var controlsBar: some View {
        HStack(spacing: 12) {
            // Mode picker
            HStack(spacing: 0) {
                ForEach(SearchMode.allCases) { mode in
                    Button {
                        searchMode = mode
                        if !query.isEmpty {
                            debouncedSearch()
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: mode.icon)
                                .font(.system(size: 9))
                            Text(mode.rawValue)
                                .font(.system(size: 10, weight: .medium))
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            searchMode == mode ? Moros.oracle.opacity(0.15) : Color.clear,
                            in: Rectangle()
                        )
                        .foregroundStyle(searchMode == mode ? Moros.oracle : Moros.textDim)
                    }
                    .buttonStyle(.plain)
                }
            }
            .background(Moros.limit02, in: Rectangle())

            Spacer()

            // Index status
            HStack(spacing: 4) {
                Circle()
                    .fill(embeddingService.hasEmbeddings ? Moros.verdit : Moros.signal)
                    .frame(width: 6, height: 6)
                Text("\(embeddingService.indexedCount) of \(embeddingService.totalCount) indexed")
                    .font(Moros.fontCaption)
                    .foregroundStyle(Moros.textDim)
            }

            if embeddingService.isIndexing {
                ProgressView(value: Double(embeddingService.indexedCount), total: max(Double(embeddingService.totalCount), 1))
                    .frame(width: 60)
                    .tint(Moros.oracle)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    // MARK: - Results List

    private var resultsList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(results) { result in
                    SemanticSearchResultRow(
                        result: result,
                        onNavigate: {
                            appState.selectedNote = result.note
                        },
                        onFindSimilar: {
                            findSimilarTo(result.note)
                        }
                    )
                    Rectangle().fill(Moros.border).frame(height: 1)
                }
            }
        }
    }

    // MARK: - Empty States

    private var emptyStateView: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "sparkle.magnifyingglass")
                .font(.system(size: 36))
                .foregroundStyle(Moros.textGhost)
            Text("Search across all your notes using natural language")
                .font(Moros.fontBody)
                .foregroundStyle(Moros.textDim)
                .multilineTextAlignment(.center)
            Text("Try concepts, questions, or topics instead of exact keywords")
                .font(Moros.fontCaption)
                .foregroundStyle(Moros.textGhost)
                .multilineTextAlignment(.center)
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding()
    }

    private var noResultsView: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "magnifyingglass")
                .font(.system(size: 36))
                .foregroundStyle(Moros.textGhost)
            Text("No results found")
                .font(Moros.fontBody)
                .foregroundStyle(Moros.textDim)
            if !embeddingService.hasEmbeddings {
                Text("Index your notes first to enable semantic search")
                    .font(Moros.fontCaption)
                    .foregroundStyle(Moros.textGhost)
                Button("Index All Notes") {
                    Task {
                        await embeddingService.indexAllNotes(context: context)
                    }
                }
                .font(Moros.fontCaption)
                .foregroundStyle(Moros.oracle)
                .buttonStyle(.plain)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding()
    }

    // MARK: - Search Logic

    private func debouncedSearch() {
        searchTask?.cancel()
        searchTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 500_000_000)
            guard !Task.isCancelled else { return }
            await performSearch()
        }
    }

    @MainActor
    private func performSearch() async {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            results = []
            return
        }

        isSearching = true

        var combined: [SemanticSearchResult] = []

        switch searchMode {
        case .keyword:
            let searchService = SearchService(context: context)
            let keywordResults = searchService.search(query: trimmed)
            combined = keywordResults.map { sr in
                SemanticSearchResult(
                    id: sr.note.id ?? UUID(),
                    note: sr.note,
                    similarity: Float(sr.relevanceScore / 100.0),
                    matchSource: .keyword
                )
            }

        case .semantic:
            let semanticResults = await embeddingService.semanticSearch(query: trimmed, context: context, limit: 20)
            combined = semanticResults.map { (note, sim) in
                SemanticSearchResult(
                    id: note.id ?? UUID(),
                    note: note,
                    similarity: sim,
                    matchSource: .semantic
                )
            }

        case .both:
            // Keyword results
            let searchService = SearchService(context: context)
            let keywordResults = searchService.search(query: trimmed)
            var scoreMap: [NSManagedObjectID: (note: NoteEntity, keywordScore: Float, semanticScore: Float)] = [:]

            for kr in keywordResults {
                scoreMap[kr.note.objectID] = (note: kr.note, keywordScore: Float(kr.relevanceScore / 100.0), semanticScore: 0)
            }

            // Semantic results
            let semanticResults = await embeddingService.semanticSearch(query: trimmed, context: context, limit: 20)
            for (note, sim) in semanticResults {
                if var existing = scoreMap[note.objectID] {
                    existing.semanticScore = sim
                    scoreMap[note.objectID] = existing
                } else {
                    scoreMap[note.objectID] = (note: note, keywordScore: 0, semanticScore: sim)
                }
            }

            // Combined weighted score: 40% keyword + 60% semantic
            combined = scoreMap.values.map { entry in
                let combinedScore = entry.keywordScore * 0.4 + entry.semanticScore * 0.6
                let source: SearchMode = entry.keywordScore > 0 && entry.semanticScore > 0 ? .both :
                    entry.keywordScore > 0 ? .keyword : .semantic
                return SemanticSearchResult(
                    id: entry.note.id ?? UUID(),
                    note: entry.note,
                    similarity: combinedScore,
                    matchSource: source
                )
            }
            .sorted { $0.similarity > $1.similarity }
        }

        results = Array(combined.prefix(Constants.Search.maxResults))
        isSearching = false
    }

    private func findSimilarTo(_ note: NoteEntity) {
        query = "Similar to: \(note.title)"
        Task {
            isSearching = true
            let similar = embeddingService.findSimilar(to: note, context: context, limit: 20)
            results = similar.map { (n, sim) in
                SemanticSearchResult(
                    id: n.id ?? UUID(),
                    note: n,
                    similarity: sim,
                    matchSource: .semantic
                )
            }
            isSearching = false
        }
    }
}

// MARK: - Search Result Row

struct SemanticSearchResultRow: View {
    let result: SemanticSearchResult
    let onNavigate: () -> Void
    let onFindSimilar: () -> Void

    var body: some View {
        Button(action: onNavigate) {
            HStack(spacing: 10) {
                // Similarity score
                VStack(spacing: 2) {
                    Text("\(result.similarityPercent)")
                        .font(.system(size: 16, weight: .light, design: .monospaced))
                        .foregroundStyle(scoreColor)
                    Text("%")
                        .font(.system(size: 8, weight: .medium, design: .monospaced))
                        .foregroundStyle(scoreColor.opacity(0.6))
                }
                .frame(width: 36)

                // Note info
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(result.note.title.isEmpty ? "Untitled" : result.note.title)
                            .font(.system(size: 13, weight: .regular))
                            .foregroundStyle(Moros.textMain)
                            .lineLimit(1)

                        matchSourceBadge
                    }

                    // Preview snippet
                    Text(previewText)
                        .font(Moros.fontCaption)
                        .foregroundStyle(Moros.textDim)
                        .lineLimit(2)

                    // Badges
                    HStack(spacing: 6) {
                        PARABadge(category: result.note.paraCategory)
                        NoteTypeBadge(type: result.note.noteType)
                        if let zettelId = result.note.zettelId {
                            Text(zettelId)
                                .font(Moros.fontMonoSmall)
                                .foregroundStyle(Moros.textGhost)
                        }
                    }
                }

                Spacer()

                // Find similar button
                Button(action: onFindSimilar) {
                    Image(systemName: "arrow.triangle.branch")
                        .font(.caption)
                        .foregroundStyle(Moros.textDim)
                }
                .buttonStyle(.plain)
                .help("Find similar notes")

                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .foregroundStyle(Moros.textGhost)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var previewText: String {
        let plain = result.note.contentPlainText
        if plain.isEmpty { return "No content" }
        return String(plain.prefix(120))
    }

    private var scoreColor: Color {
        if result.similarity > 0.8 { return Moros.verdit }
        if result.similarity > 0.5 { return Moros.oracle }
        if result.similarity > 0.3 { return Moros.ambient }
        return Moros.textDim
    }

    @ViewBuilder
    private var matchSourceBadge: some View {
        switch result.matchSource {
        case .keyword:
            Text("KW")
                .font(.system(size: 8, weight: .semibold, design: .monospaced))
                .padding(.horizontal, 4)
                .padding(.vertical, 1)
                .background(Moros.ambient.opacity(0.12), in: Rectangle())
                .foregroundStyle(Moros.ambient)
        case .semantic:
            Text("SEM")
                .font(.system(size: 8, weight: .semibold, design: .monospaced))
                .padding(.horizontal, 4)
                .padding(.vertical, 1)
                .background(Moros.oracle.opacity(0.12), in: Rectangle())
                .foregroundStyle(Moros.oracle)
        case .both:
            Text("BOTH")
                .font(.system(size: 8, weight: .semibold, design: .monospaced))
                .padding(.horizontal, 4)
                .padding(.vertical, 1)
                .background(Moros.verdit.opacity(0.12), in: Rectangle())
                .foregroundStyle(Moros.verdit)
        }
    }
}
