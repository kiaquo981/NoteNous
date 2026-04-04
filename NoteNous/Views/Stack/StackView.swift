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
        animation: nil
    ) private var notes: FetchedResults<NoteEntity>

    @State private var searchMatchCount: Int = 0
    @State private var draggingNote: NoteEntity?

    private var searchService: SearchService {
        SearchService(context: context)
    }

    var body: some View {
        List(selection: Binding(
            get: { appState.selectedNote },
            set: { newNote in
                if let note = newNote {
                    appState.navigateToNote(note)
                } else {
                    appState.selectedNote = nil
                }
            }
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
                // Pinned section
                let pinned = filteredNotes.filter(\.isPinned)
                let unpinned = filteredNotes.filter { !$0.isPinned }

                if !pinned.isEmpty {
                    Section {
                        ForEach(pinned, id: \.objectID) { note in
                            noteRow(note)
                        }
                        .onMove { source, destination in
                            guard appState.stackSortMode == .manual else { return }
                            moveNotes(isPinned: true, from: source, to: destination)
                        }
                    } header: {
                        HStack(spacing: 4) {
                            Image(systemName: "pin.fill")
                                .font(.caption2)
                            Text("Pinned")
                                .font(Moros.fontMonoSmall)
                        }
                        .foregroundStyle(Moros.signal)
                    }
                }

                Section {
                    ForEach(unpinned, id: \.objectID) { note in
                        noteRow(note)
                    }
                    .onMove { source, destination in
                        guard appState.stackSortMode == .manual else { return }
                        moveNotes(isPinned: false, from: source, to: destination)
                    }
                } header: {
                    if !pinned.isEmpty {
                        Text("Notes")
                            .font(Moros.fontMonoSmall)
                            .foregroundStyle(Moros.textDim)
                    }
                }
            }
        }
        .listStyle(.inset(alternatesRowBackgrounds: false))
        .animation(.morosGentle, value: appState.selectedPARAFilter)
        .animation(.morosGentle, value: appState.selectedCODEFilter)
        .animation(.morosGentle, value: appState.selectedNoteTypeFilter)
        .animation(.morosGentle, value: appState.stackSortMode)
        .searchable(text: $appState.searchQuery, prompt: "Search notes...")
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Picker("Sort", selection: $appState.stackSortMode) {
                    ForEach(StackSortMode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 180)
                .help("Manual mode enables drag-to-reorder")
            }

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

    // MARK: - Note Row with Drag Support

    @ViewBuilder
    private func noteRow(_ note: NoteEntity) -> some View {
        NoteCardRow(note: note)
            .tag(note)
            .opacity(draggingNote?.objectID == note.objectID ? 0.4 : 1.0)
            .onDrag {
                self.draggingNote = note
                return NSItemProvider(object: (note.zettelId ?? note.objectID.uriRepresentation().absoluteString) as NSString)
            }
            .onDrop(of: [.text], delegate: NoteDropDelegate(
                note: note,
                draggingNote: $draggingNote,
                notes: filteredNotes,
                context: context,
                sortMode: appState.stackSortMode
            ))
            .contextMenu {
                Button("Show in Finder") {
                    VaultService.shared.showInFinder(note)
                }
                Button("Open in External Editor") {
                    VaultService.shared.openInExternalEditor(note)
                }
                Button("Copy File Path") {
                    VaultService.shared.copyPath(note)
                }
                Divider()
                Button(note.isPinned ? "Unpin" : "Pin") {
                    let service = NoteService(context: context)
                    service.togglePin(note)
                }
                Button("Archive") {
                    let service = NoteService(context: context)
                    service.archiveNote(note)
                }
                Divider()
                Button("Delete", role: .destructive) {
                    let service = NoteService(context: context)
                    service.deleteNote(note)
                }
            }
    }

    // MARK: - Move Notes (onMove handler)

    private func moveNotes(isPinned: Bool, from source: IndexSet, to destination: Int) {
        let section = isPinned
            ? filteredNotes.filter(\.isPinned)
            : filteredNotes.filter { !$0.isPinned }
        var mutable = section
        let service = NoteService(context: context)
        service.moveNotes(in: &mutable, from: source, to: destination)
        // Switch to manual mode on first drag
        if appState.stackSortMode != .manual {
            appState.stackSortMode = .manual
        }
    }

    // MARK: - Filtered Notes

    private var filteredNotes: [NoteEntity] {
        // Deduplicate by objectID AND zettelId
        var seenObjectIDs = Set<NSManagedObjectID>()
        var seenZettelIds = Set<String>()
        var result = Array(notes).filter { note in
            // Skip ghost notes (no title AND no content)
            if note.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && note.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return false
            }
            // Dedup by objectID (Core Data level)
            if seenObjectIDs.contains(note.objectID) { return false }
            seenObjectIDs.insert(note.objectID)
            // Dedup by zettelId (business level)
            if let zid = note.zettelId, !zid.isEmpty {
                if seenZettelIds.contains(zid) { return false }
                seenZettelIds.insert(zid)
            }
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
        } else {
            // Apply sort mode
            switch appState.stackSortMode {
            case .updatedAt:
                result.sort { lhs, rhs in
                    if lhs.isPinned != rhs.isPinned { return lhs.isPinned }
                    return (lhs.updatedAt ?? .distantPast) > (rhs.updatedAt ?? .distantPast)
                }
            case .manual:
                result.sort { lhs, rhs in
                    if lhs.isPinned != rhs.isPinned { return lhs.isPinned }
                    return lhs.sortOrder < rhs.sortOrder
                }
            }
        }

        return result
    }

    private func updateMatchCount() {
        searchMatchCount = filteredNotes.count
    }
}

// MARK: - Drop Delegate for Drag Reorder

struct NoteDropDelegate: DropDelegate {
    let note: NoteEntity
    @Binding var draggingNote: NoteEntity?
    let notes: [NoteEntity]
    let context: NSManagedObjectContext
    let sortMode: StackSortMode

    func performDrop(info: DropInfo) -> Bool {
        draggingNote = nil
        return true
    }

    func dropEntered(info: DropInfo) {
        guard sortMode == .manual else { return }
        guard let dragging = draggingNote,
              dragging.objectID != note.objectID else { return }
        // Only reorder within same pinned group
        guard dragging.isPinned == note.isPinned else { return }

        let group = notes.filter { $0.isPinned == note.isPinned }
        guard let fromIndex = group.firstIndex(where: { $0.objectID == dragging.objectID }),
              let toIndex = group.firstIndex(where: { $0.objectID == note.objectID }) else { return }

        if fromIndex != toIndex {
            var mutable = group
            withAnimation(.morosGentle) {
                mutable.move(fromOffsets: IndexSet(integer: fromIndex), toOffset: toIndex > fromIndex ? toIndex + 1 : toIndex)
                let service = NoteService(context: context)
                service.assignSortOrders(mutable)
            }
        }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }
}

// MARK: - Note Card Row

struct NoteCardRow: View {
    @ObservedObject var note: NoteEntity
    // Hover removed — macOS List handles selection highlighting natively

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
                    .lineLimit(1)
                Spacer()
                PARABadge(category: note.paraCategory)
            }

            // Row 2: Preview text (2 lines max)
            if !cleanContent.isEmpty {
                Text(cleanContent)
                    .font(Moros.fontSmall)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            // Row 3: zettelId | relative time | tags
            HStack(spacing: 8) {
                if let zettelId = note.zettelId {
                    Text(zettelId)
                        .font(.system(size: 9, weight: .regular, design: .monospaced))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }

                Spacer()

                if let date = note.updatedAt {
                    Text(date, style: .relative)
                        .font(.system(size: 9, weight: .regular, design: .monospaced))
                        .foregroundStyle(.tertiary)
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
    }
}
