import SwiftUI
import CoreData

struct StackView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.managedObjectContext) private var context

    @FetchRequest(
        sortDescriptors: [
            NSSortDescriptor(keyPath: \NoteEntity.isPinned, ascending: false),
            NSSortDescriptor(keyPath: \NoteEntity.updatedAt, ascending: false)
        ],
        predicate: NSPredicate(format: "isArchived == NO"),
        animation: .default
    ) private var notes: FetchedResults<NoteEntity>

    @State private var searchMatchCount: Int = 0

    private var searchService: SearchService {
        SearchService(context: context)
    }

    var body: some View {
        List(selection: Binding(
            get: { appState.selectedNote },
            set: { appState.selectedNote = $0 }
        )) {
            if filteredNotes.isEmpty {
                EmptyStateView(
                    icon: "square.stack",
                    title: "No Notes Yet",
                    subtitle: "Press \u{2318}N to create your first note"
                )
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            } else {
                ForEach(filteredNotes, id: \.objectID) { note in
                    NoteCardRow(note: note)
                        .tag(note)
                        .listRowBackground(Color.clear)
                }
            }
        }
        .listStyle(.inset(alternatesRowBackgrounds: false))


        .animation(.morosGentle, value: appState.selectedPARAFilter)
        .animation(.morosGentle, value: appState.selectedCODEFilter)
        .animation(.morosGentle, value: appState.selectedNoteTypeFilter)
        .searchable(text: $appState.searchQuery, prompt: "Search notes...")
        .toolbar {
            if !appState.searchQuery.isEmpty {
                ToolbarItem(placement: .automatic) {
                    Text("\(searchMatchCount) match\(searchMatchCount == 1 ? "" : "es")")
                        .font(Moros.fontMonoSmall)
                        .foregroundStyle(Moros.textDim)
                        .monospacedDigit()
                }
            }
        }
        .onChange(of: appState.searchQuery) { updateMatchCount() }
        .onChange(of: appState.selectedPARAFilter) { updateMatchCount() }
        .onChange(of: appState.selectedCODEFilter) { updateMatchCount() }
        .onChange(of: appState.selectedNoteTypeFilter) { updateMatchCount() }
    }

    private var filteredNotes: [NoteEntity] {
        // Deduplicate by zettelId to prevent showing same note twice
        var seen = Set<String>()
        var result = Array(notes).filter { note in
            guard let zid = note.zettelId else { return true }
            if seen.contains(zid) { return false }
            seen.insert(zid)
            return true
        }

        if let para = appState.selectedPARAFilter {
            result = result.filter { $0.paraCategory == para }
        }
        if let code = appState.selectedCODEFilter {
            result = result.filter { $0.codeStage == code }
        }
        if let noteType = appState.selectedNoteTypeFilter {
            result = result.filter { $0.noteType == noteType }
        }

        if !appState.searchQuery.isEmpty {
            let searchResults = searchService.search(query: appState.searchQuery)
            let matchedIDs = Set(searchResults.map(\.note.objectID))
            result = result.filter { matchedIDs.contains($0.objectID) }

            // Sort by search relevance while keeping pinned at top
            let scoreMap = Dictionary(uniqueKeysWithValues: searchResults.map { ($0.note.objectID, $0.relevanceScore) })
            result.sort { lhs, rhs in
                if lhs.isPinned != rhs.isPinned { return lhs.isPinned }
                let lhsScore = scoreMap[lhs.objectID] ?? 0
                let rhsScore = scoreMap[rhs.objectID] ?? 0
                return lhsScore > rhsScore
            }
        }

        return result
    }

    private func updateMatchCount() {
        searchMatchCount = filteredNotes.count
    }
}

// MARK: - Note Card Row

struct NoteCardRow: View {
    @ObservedObject var note: NoteEntity
    @State private var isHovered = false

    /// Strips YAML frontmatter from content preview
    private var cleanContent: String {
        let text = note.contentPlainText
        if text.hasPrefix("---") {
            let searchStart = text.index(text.startIndex, offsetBy: min(3, text.count))
            if let endRange = text.range(of: "---", range: searchStart..<text.endIndex) {
                return String(text[endRange.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        return text
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Row 1: [Pin] Title ... [PARA badge]
            HStack(spacing: 6) {
                if note.isPinned {
                    Image(systemName: "pin.fill")
                        .font(.caption2)
                        .foregroundStyle(Moros.signal)
                }
                Text(note.title.isEmpty ? "Untitled" : note.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Moros.textMain)
                    .lineLimit(1)
                Spacer()
                PARABadge(category: note.paraCategory)
            }

            // Row 2: Preview text (2 lines max)
            if !cleanContent.isEmpty {
                Text(cleanContent)
                    .font(Moros.fontSmall)
                    .foregroundStyle(Moros.textSub)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            // Row 3: zettelId | relative time | tags
            HStack(spacing: 8) {
                if let zettelId = note.zettelId {
                    Text(zettelId)
                        .font(.system(size: 9, weight: .regular, design: .monospaced))
                        .foregroundStyle(Moros.textDim)
                        .lineLimit(1)
                }

                Spacer()

                if let date = note.updatedAt {
                    Text(date, style: .relative)
                        .font(.system(size: 9, weight: .regular, design: .monospaced))
                        .foregroundStyle(Moros.textDim)
                        .lineLimit(1)
                }

                if !note.tagsArray.isEmpty {
                    HStack(spacing: 4) {
                        ForEach(note.tagsArray.prefix(2), id: \.objectID) { tag in
                            if let name = tag.name {
                                Text("#\(String(name.prefix(10)))")
                                    .font(.system(size: 9, design: .monospaced))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                    }
                }
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .background(isHovered ? Moros.limit02 : .clear, in: Rectangle())
        .onHover { isHovered = $0 }
        .animation(.morosMicro, value: isHovered)
    }
}
