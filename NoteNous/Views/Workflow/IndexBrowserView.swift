import SwiftUI
import CoreData

/// Browse and manage the keyword index (Luhmann's index).
/// Each keyword maps to 1-3 "entry point" notes — not every note about a topic.
struct IndexBrowserView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.managedObjectContext) private var context
    @ObservedObject var indexService: IndexService

    @State private var searchText = ""
    @State private var selectedEntry: IndexEntry?
    @State private var showAddSheet = false
    @State private var newKeyword = ""
    @State private var notePickerVisible = false

    var body: some View {
        HSplitView {
            // Left: keyword list
            keywordList
                .frame(minWidth: 200, idealWidth: 260)

            // Right: entry notes for selected keyword
            entryNotesPanel
                .frame(minWidth: 300)
        }
        .sheet(isPresented: $showAddSheet) {
            addKeywordSheet
        }
    }

    // MARK: - Keyword List

    private var keywordList: some View {
        VStack(spacing: 0) {
            // Search + Add
            HStack {
                TextField("Filter keywords...", text: $searchText)
                    .textFieldStyle(.roundedBorder)
                Button {
                    showAddSheet = true
                } label: {
                    Image(systemName: "plus")
                }
            }
            .padding(8)

            Divider()

            // Stats
            HStack {
                let stats = indexService.stats()
                Text("\(stats.totalKeywords) keywords")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                if stats.overloadedKeywords > 0 {
                    Label("\(stats.overloadedKeywords) overloaded", systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)

            Divider()

            // Keyword list
            List(selection: $selectedEntry) {
                ForEach(filteredEntries) { entry in
                    KeywordRow(entry: entry, isOverloaded: entry.entryNoteIds.count > IndexService.maxEntryNotesPerKeyword)
                        .tag(entry)
                        .contextMenu {
                            Button("Delete Keyword", role: .destructive) {
                                indexService.removeEntry(keyword: entry.keyword)
                                if selectedEntry?.id == entry.id {
                                    selectedEntry = nil
                                }
                            }
                        }
                }
            }
            .listStyle(.sidebar)
        }
    }

    // MARK: - Entry Notes Panel

    private var entryNotesPanel: some View {
        VStack(spacing: 0) {
            if let entry = selectedEntry {
                // Header
                HStack {
                    VStack(alignment: .leading) {
                        Text(entry.keyword)
                            .font(.title2.weight(.semibold))
                        Text("\(entry.entryNoteIds.count) entry note\(entry.entryNoteIds.count == 1 ? "" : "s")")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    if entry.entryNoteIds.count < IndexService.maxEntryNotesPerKeyword {
                        Button {
                            notePickerVisible = true
                        } label: {
                            Label("Add Entry Note", systemImage: "plus")
                        }
                    }

                    if entry.entryNoteIds.count > IndexService.maxEntryNotesPerKeyword {
                        Label("Too many entries", systemImage: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
                .padding()

                Divider()

                // Entry notes
                let entryNotes = resolveNotes(entry: entry)
                if entryNotes.isEmpty {
                    VStack(spacing: 8) {
                        Text("No entry notes found")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                        Text("The referenced notes may have been deleted.")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List {
                        ForEach(entryNotes, id: \.objectID) { note in
                            EntryNoteRow(note: note) {
                                appState.navigateToNote(note)
                            } onRemove: {
                                if let noteId = note.id {
                                    indexService.removeNoteFromEntry(keyword: entry.keyword, noteId: noteId)
                                    // Refresh selectedEntry
                                    selectedEntry = indexService.entry(for: entry.keyword)
                                }
                            }
                        }
                    }
                    .listStyle(.inset)
                }

                // Note picker sheet
                if notePickerVisible {
                    Divider()
                    notePickerSection(entry: entry)
                }
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "text.book.closed")
                        .font(.system(size: 36))
                        .foregroundStyle(.secondary)
                    Text("Select a keyword")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Text("Entry notes serve as doorways into your Zettelkasten.\nKeep 1-3 per keyword for effective navigation.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    // MARK: - Note Picker

    private func notePickerSection(entry: IndexEntry) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Add entry note:")
                    .font(.caption.weight(.semibold))
                Spacer()
                Button("Done") {
                    notePickerVisible = false
                }
                .font(.caption)
            }

            NotePickerList(
                context: context,
                excludeIds: Set(entry.entryNoteIds)
            ) { noteId in
                indexService.addEntry(keyword: entry.keyword, noteId: noteId)
                selectedEntry = indexService.entry(for: entry.keyword)
                notePickerVisible = false
            }
            .frame(height: 200)
        }
        .padding()
        .background(.bar)
    }

    // MARK: - Add Keyword Sheet

    private var addKeywordSheet: some View {
        VStack(spacing: 16) {
            Text("Add Keyword to Index")
                .font(.title3.weight(.semibold))

            TextField("Keyword", text: $newKeyword)
                .textFieldStyle(.roundedBorder)

            Text("Keywords in Luhmann's index are entry points, not categories.\nEach keyword should map to 1-3 notes that best represent the topic.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            HStack {
                Button("Cancel") {
                    newKeyword = ""
                    showAddSheet = false
                }
                .keyboardShortcut(.cancelAction)

                Button("Add") {
                    let trimmed = newKeyword.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty {
                        // Create entry without a note initially
                        let entry = IndexEntry(keyword: trimmed)
                        if indexService.entry(for: trimmed) == nil {
                            // Manually add empty entry
                            indexService.addEmptyEntry(keyword: trimmed)
                        }
                        selectedEntry = indexService.entry(for: trimmed)
                    }
                    newKeyword = ""
                    showAddSheet = false
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(newKeyword.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(24)
        .frame(minWidth: 350)
    }

    // MARK: - Helpers

    private var filteredEntries: [IndexEntry] {
        if searchText.isEmpty {
            return indexService.allKeywordsSorted()
        }
        return indexService.searchKeywords(prefix: searchText)
    }

    private func resolveNotes(entry: IndexEntry) -> [NoteEntity] {
        indexService.entryNotes(for: entry.keyword, in: context)
    }
}

// MARK: - Keyword Row

struct KeywordRow: View {
    let entry: IndexEntry
    let isOverloaded: Bool

    var body: some View {
        HStack {
            Text(entry.keyword)
                .font(.callout)
            Spacer()
            Text("\(entry.entryNoteIds.count)")
                .font(.caption.monospacedDigit())
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(
                    isOverloaded ? Color.orange.opacity(0.2) : Color.gray.opacity(0.15),
                    in: Capsule()
                )
                .foregroundStyle(isOverloaded ? .orange : .secondary)
        }
    }
}

// MARK: - Entry Note Row

struct EntryNoteRow: View {
    @ObservedObject var note: NoteEntity
    let onNavigate: () -> Void
    let onRemove: () -> Void

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(note.zettelId ?? "?")
                        .font(.caption.monospaced())
                        .foregroundStyle(.tertiary)
                    Text(note.title.isEmpty ? "Untitled" : note.title)
                        .font(.callout.weight(.medium))
                        .lineLimit(1)
                }
                if !note.contentPlainText.isEmpty {
                    Text(note.contentPlainText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }

            Spacer()

            Button {
                onNavigate()
            } label: {
                Image(systemName: "arrow.right.circle")
            }
            .buttonStyle(.borderless)

            Button {
                onRemove()
            } label: {
                Image(systemName: "xmark.circle")
                    .foregroundStyle(.red)
            }
            .buttonStyle(.borderless)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Note Picker List

struct NotePickerList: View {
    let context: NSManagedObjectContext
    let excludeIds: Set<UUID>
    let onSelect: (UUID) -> Void

    @State private var pickerSearch = ""

    var body: some View {
        VStack(spacing: 4) {
            TextField("Search notes...", text: $pickerSearch)
                .textFieldStyle(.roundedBorder)
                .font(.caption)

            List {
                ForEach(fetchNotes(), id: \.objectID) { note in
                    Button {
                        if let noteId = note.id {
                            onSelect(noteId)
                        }
                    } label: {
                        HStack {
                            Text(note.zettelId ?? "?")
                                .font(.caption.monospaced())
                                .frame(width: 50, alignment: .leading)
                            Text(note.title.isEmpty ? "Untitled" : note.title)
                                .font(.caption)
                                .lineLimit(1)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .listStyle(.bordered)
        }
    }

    private func fetchNotes() -> [NoteEntity] {
        let request = NoteEntity.fetchRequest() as! NSFetchRequest<NoteEntity>
        var predicates: [NSPredicate] = [
            NSPredicate(format: "noteTypeRaw == %d", NoteType.permanent.rawValue),
            NSPredicate(format: "isArchived == NO")
        ]

        if !pickerSearch.isEmpty {
            predicates.append(NSPredicate(format: "title CONTAINS[cd] %@ OR zettelId CONTAINS[cd] %@", pickerSearch, pickerSearch))
        }

        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: predicates)
        request.sortDescriptors = [NSSortDescriptor(key: "updatedAt", ascending: false)]
        request.fetchLimit = 30

        let results = (try? context.fetch(request)) ?? []
        return results.filter { note in
            guard let noteId = note.id else { return true }
            return !excludeIds.contains(noteId)
        }
    }
}

// MARK: - IndexService Extension for empty entries

// addEmptyEntry is handled via IndexService.addEntry(keyword:noteId:) with a dummy note,
// or by extending IndexService in IndexService.swift directly if needed.
