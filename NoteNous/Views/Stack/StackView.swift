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
                        .listRowBackground(Moros.limit01)
                }
            }
        }
        .listStyle(.inset(alternatesRowBackgrounds: false))
        .scrollContentBackground(.hidden)
        .morosBackground(Moros.limit01)
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
        var result = Array(notes)

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

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
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

            if !note.contentPlainText.isEmpty {
                Text(note.contentPlainText)
                    .font(Moros.fontSmall)
                    .foregroundStyle(Moros.textSub)
                    .lineLimit(2)
            }

            HStack(spacing: 8) {
                if let zettelId = note.zettelId {
                    Text(zettelId)
                        .font(Moros.fontMonoSmall)
                        .foregroundStyle(Moros.textDim)
                }

                Spacer()

                if let date = note.updatedAt {
                    Text(date, style: .relative)
                        .font(Moros.fontMonoSmall)
                        .foregroundStyle(Moros.textDim)
                }

                if !note.tagsArray.isEmpty {
                    HStack(spacing: 2) {
                        ForEach(note.tagsArray.prefix(3), id: \.objectID) { tag in
                            if let name = tag.name {
                                Text("#\(name)")
                                    .font(Moros.fontMonoSmall)
                                    .foregroundStyle(Moros.oracle)
                            }
                        }
                    }
                }
            }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 4)
        .background(isHovered ? Moros.limit02 : .clear, in: Rectangle())
        .onHover { isHovered = $0 }
        .animation(.easeOut(duration: Moros.animFast), value: isHovered)
    }
}
