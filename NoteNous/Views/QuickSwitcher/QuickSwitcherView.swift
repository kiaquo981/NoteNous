import SwiftUI
import CoreData

struct QuickSwitcherView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.managedObjectContext) private var context
    @State private var query = ""
    @State private var searchResults: [SearchResult] = []
    @State private var selectedIndex: Int = 0
    @FocusState private var isSearchFocused: Bool

    private var searchService: SearchService {
        SearchService(context: context)
    }

    var body: some View {
        ZStack {
            // Dark backdrop
            Color.black.opacity(0.5)
                .ignoresSafeArea()
                .transition(.opacity)
                .onTapGesture {
                    dismiss()
                }

            // Switcher panel — positioned in top third
            VStack(spacing: 0) {
                Spacer()
                    .frame(height: 80)

                VStack(spacing: 0) {
                    // Search field
                    HStack(spacing: 10) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 16))
                            .foregroundStyle(Moros.textDim)
                        TextField("Quick switch...", text: $query)
                            .textFieldStyle(.plain)
                            .font(Moros.fontH3)
                            .foregroundStyle(Moros.textMain)
                            .focused($isSearchFocused)
                            .onSubmit { openSelected() }

                        if !query.isEmpty {
                            Button(action: { query = "" }) {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(Moros.textDim)
                            }
                            .buttonStyle(.plain)
                        }

                        // Shortcut hint
                        Text("\u{2318}O")
                            .font(Moros.fontMonoSmall)
                            .foregroundStyle(Moros.textDim)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Moros.limit03, in: Rectangle())
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)

                    Rectangle().fill(Moros.border).frame(height: 1)

                    // Results
                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 0) {
                                if query.isEmpty {
                                    // Show recent notes
                                    if !recentNotes.isEmpty {
                                        QuickSwitcherSection(title: "RECENT") {
                                            ForEach(Array(recentNotes.enumerated()), id: \.element.objectID) { index, note in
                                                QuickSwitcherNoteRow(
                                                    note: note,
                                                    isHighlighted: index == selectedIndex
                                                )
                                                .id(index)
                                                .contentShape(Rectangle())
                                                .onTapGesture {
                                                    openNote(note)
                                                }
                                            }
                                        }
                                    } else {
                                        Text("Start typing to find a note...")
                                            .font(Moros.fontBody)
                                            .foregroundStyle(Moros.textDim)
                                            .padding()
                                    }
                                } else {
                                    if !searchResults.isEmpty {
                                        ForEach(Array(searchResults.enumerated()), id: \.element.id) { index, result in
                                            QuickSwitcherNoteRow(
                                                note: result.note,
                                                isHighlighted: index == selectedIndex
                                            )
                                            .id(index)
                                            .contentShape(Rectangle())
                                            .onTapGesture {
                                                openNote(result.note)
                                            }
                                        }
                                    } else {
                                        VStack(spacing: 8) {
                                            Text("No results for \"\(query)\"")
                                                .font(Moros.fontBody)
                                                .foregroundStyle(Moros.textDim)

                                            // Create new note option
                                            Button(action: { createAndOpen() }) {
                                                HStack(spacing: 8) {
                                                    Image(systemName: "plus.circle")
                                                        .foregroundStyle(Moros.oracle)
                                                    Text("Create new note: \"\(query)\"")
                                                        .foregroundStyle(Moros.oracle)
                                                }
                                                .padding(.horizontal, 12)
                                                .padding(.vertical, 6)
                                                .background(Moros.oracle.opacity(0.1), in: Rectangle())
                                            }
                                            .buttonStyle(.plain)
                                        }
                                        .padding()
                                    }
                                }
                            }
                        }
                        .frame(maxHeight: 340)
                        .onChange(of: selectedIndex) {
                            withAnimation {
                                proxy.scrollTo(selectedIndex, anchor: .center)
                            }
                        }
                    }
                }
                .frame(width: 600)
                .background(Moros.limit01, in: Rectangle())
                .overlay(Rectangle().stroke(Moros.borderLit, lineWidth: 1))
                .morosGlow(Moros.oracle, radius: 20)

                Spacer()
            }
        }
        .onAppear {
            isSearchFocused = true
            selectedIndex = 0
        }
        .onChange(of: query) {
            performSearch()
            selectedIndex = 0
        }
        .onKeyPress(.upArrow) {
            moveSelection(-1)
            return .handled
        }
        .onKeyPress(.downArrow) {
            moveSelection(1)
            return .handled
        }
        .onKeyPress(.escape) {
            dismiss()
            return .handled
        }
    }

    // MARK: - Recent Notes

    private var recentNotes: [NoteEntity] {
        let ids = appState.recentNoteIds.prefix(5)
        guard !ids.isEmpty else { return [] }

        let request = NoteEntity.fetchRequest() as! NSFetchRequest<NoteEntity>
        let predicates = ids.map { NSPredicate(format: "id == %@", $0 as CVarArg) }
        request.predicate = NSCompoundPredicate(orPredicateWithSubpredicates: predicates)

        guard let notes = try? context.fetch(request) else { return [] }

        // Maintain order from recentNoteIds
        return ids.compactMap { id in
            notes.first { $0.id == id }
        }
    }

    // MARK: - Search

    private func performSearch() {
        guard !query.isEmpty else { searchResults = []; return }
        searchResults = searchService.search(query: query, scope: .all)
    }

    // MARK: - Navigation

    private var totalItems: Int {
        if query.isEmpty {
            return recentNotes.count
        } else {
            return searchResults.count
        }
    }

    private func moveSelection(_ delta: Int) {
        let count = totalItems
        guard count > 0 else { return }
        selectedIndex = max(0, min(count - 1, selectedIndex + delta))
    }

    private func openSelected() {
        if query.isEmpty {
            let notes = recentNotes
            guard selectedIndex < notes.count else { return }
            openNote(notes[selectedIndex])
        } else if !searchResults.isEmpty {
            guard selectedIndex < searchResults.count else { return }
            openNote(searchResults[selectedIndex].note)
        } else {
            // No results — create new note
            createAndOpen()
        }
    }

    private func openNote(_ note: NoteEntity) {
        appState.selectedNote = note
        dismiss()
    }

    private func createAndOpen() {
        let service = NoteService(context: context)
        let note = service.createNote(title: query, content: "")
        appState.selectedNote = note
        dismiss()
    }

    private func dismiss() {
        appState.isQuickSwitcherVisible = false
    }
}

// MARK: - Quick Switcher Components

struct QuickSwitcherSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .foregroundStyle(Moros.textDim)
                .padding(.horizontal, 12)
                .padding(.top, 8)
                .padding(.bottom, 4)
            content
        }
    }
}

struct QuickSwitcherNoteRow: View {
    let note: NoteEntity
    var isHighlighted: Bool = false

    var body: some View {
        HStack(spacing: 10) {
            // Note type icon
            Image(systemName: noteTypeIcon)
                .font(.system(size: 12))
                .foregroundStyle(noteTypeColor)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 2) {
                Text(note.title.isEmpty ? "Untitled" : note.title)
                    .font(Moros.fontBody)
                    .foregroundStyle(Moros.textMain)
                    .lineLimit(1)

                HStack(spacing: 6) {
                    if let zettelId = note.zettelId {
                        Text(zettelId)
                            .font(Moros.fontMonoSmall)
                            .foregroundStyle(Moros.textDim)
                    }

                    if !note.contentPlainText.isEmpty {
                        Text(String(note.contentPlainText.prefix(60)))
                            .font(Moros.fontCaption)
                            .foregroundStyle(Moros.textDim)
                            .lineLimit(1)
                    }
                }
            }

            Spacer()

            PARABadge(category: note.paraCategory)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(isHighlighted ? Moros.oracle.opacity(0.15) : .clear, in: Rectangle())
        .animation(.morosMicro, value: isHighlighted)
    }

    private var noteTypeIcon: String {
        switch note.noteType {
        case .fleeting: return "bolt.fill"
        case .literature: return "book.fill"
        case .permanent: return "diamond.fill"
        case .structure: return "folder.fill"
        }
    }

    private var noteTypeColor: Color {
        switch note.noteType {
        case .fleeting: return Moros.ambient
        case .literature: return Moros.oracle
        case .permanent: return Moros.verdit
        case .structure: return Moros.textSub
        }
    }
}
