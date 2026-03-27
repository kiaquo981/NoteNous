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
                }
            }
        }
        .listStyle(.inset(alternatesRowBackgrounds: true))
        .searchable(text: $appState.searchQuery, prompt: "Search notes...")
    }

    private var filteredNotes: [NoteEntity] {
        var result = Array(notes)

        if let para = appState.selectedPARAFilter {
            result = result.filter { $0.paraCategory == para }
        }
        if let code = appState.selectedCODEFilter {
            result = result.filter { $0.codeStage == code }
        }
        if !appState.searchQuery.isEmpty {
            let query = appState.searchQuery.lowercased()
            result = result.filter {
                $0.title.lowercased().contains(query) ||
                $0.contentPlainText.lowercased().contains(query) ||
                ($0.zettelId?.lowercased().contains(query) ?? false)
            }
        }

        return result
    }
}

// MARK: - Note Card Row

struct NoteCardRow: View {
    @ObservedObject var note: NoteEntity

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                if note.isPinned {
                    Image(systemName: "pin.fill")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }
                Text(note.title.isEmpty ? "Untitled" : note.title)
                    .font(.headline)
                    .lineLimit(1)
                Spacer()
                PARABadge(category: note.paraCategory)
            }

            if !note.contentPlainText.isEmpty {
                Text(note.contentPlainText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            HStack(spacing: 8) {
                if let zettelId = note.zettelId {
                    Text(zettelId)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .monospaced()
                }

                Spacer()

                if let date = note.updatedAt {
                    Text(date, style: .relative)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }

                if !note.tagsArray.isEmpty {
                    HStack(spacing: 2) {
                        ForEach(note.tagsArray.prefix(3), id: \.objectID) { tag in
                            if let name = tag.name {
                                Text("#\(name)")
                                    .font(.caption2)
                                    .foregroundStyle(.blue)
                            }
                        }
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }
}
