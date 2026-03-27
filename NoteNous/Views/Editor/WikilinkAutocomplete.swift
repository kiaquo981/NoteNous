import SwiftUI
import CoreData

// MARK: - WikilinkAutocompleteState

@MainActor
final class WikilinkAutocompleteState: ObservableObject {
    @Published var isVisible = false
    @Published var query = ""
    @Published var results: [NoteEntity] = []
    @Published var selectedIndex = 0

    private var context: NSManagedObjectContext?

    func configure(context: NSManagedObjectContext) {
        self.context = context
    }

    func show(initialQuery: String = "") {
        query = initialQuery
        selectedIndex = 0
        isVisible = true
        search()
    }

    func dismiss() {
        isVisible = false
        query = ""
        results = []
        selectedIndex = 0
    }

    func search() {
        guard let context else { return }

        let parser = WikilinkParser(context: context)
        results = parser.searchNotes(matching: query, limit: 10)
        selectedIndex = min(selectedIndex, max(results.count, 1) - 1)
    }

    func moveUp() {
        if selectedIndex > 0 {
            selectedIndex -= 1
        }
    }

    func moveDown() {
        let maxIndex = showCreateOption ? results.count : results.count - 1
        if selectedIndex < maxIndex {
            selectedIndex += 1
        }
    }

    /// Returns the selected note, or nil if "Create new" is selected.
    var selectedNote: NoteEntity? {
        guard selectedIndex < results.count else { return nil }
        return results[selectedIndex]
    }

    /// Whether to show a "Create new note" option at the bottom.
    var showCreateOption: Bool {
        !query.isEmpty && !results.contains(where: { $0.title.localizedCaseInsensitiveCompare(query) == .orderedSame })
    }

    /// Whether the "Create new" option is currently selected.
    var isCreateOptionSelected: Bool {
        showCreateOption && selectedIndex == results.count
    }
}

// MARK: - WikilinkAutocomplete View

struct WikilinkAutocomplete: View {
    @ObservedObject var state: WikilinkAutocompleteState
    var onSelect: (NoteEntity) -> Void
    var onCreate: (String) -> Void
    var onDismiss: () -> Void

    var body: some View {
        if state.isVisible {
            VStack(alignment: .leading, spacing: 0) {
                // Search field
                HStack(spacing: 6) {
                    Image(systemName: "link")
                        .foregroundStyle(.secondary)
                        .font(.caption)

                    TextField("Search notes...", text: $state.query)
                        .textFieldStyle(.plain)
                        .font(.callout)
                        .onSubmit { handleSubmit() }
                        .onChange(of: state.query) { state.search() }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)

                Divider()

                // Results list
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            ForEach(Array(state.results.enumerated()), id: \.element.objectID) { index, note in
                                WikilinkAutocompleteRow(
                                    note: note,
                                    isSelected: index == state.selectedIndex
                                )
                                .id(index)
                                .onTapGesture {
                                    onSelect(note)
                                    state.dismiss()
                                }
                            }

                            if state.showCreateOption {
                                createNewRow
                                    .id(state.results.count)
                                    .onTapGesture {
                                        onCreate(state.query)
                                        state.dismiss()
                                    }
                            }

                            if state.results.isEmpty && !state.showCreateOption {
                                noResultsView
                            }
                        }
                    }
                    .onChange(of: state.selectedIndex) { newIndex in
                        proxy.scrollTo(newIndex, anchor: .center)
                    }
                }
                .frame(maxHeight: 250)
            }
            .frame(width: 320)
            .background(.regularMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .shadow(color: .black.opacity(0.15), radius: 12, y: 4)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(.separator, lineWidth: 0.5)
            )
        }
    }

    // MARK: - Create New Row

    private var createNewRow: some View {
        HStack(spacing: 8) {
            Image(systemName: "plus.circle.fill")
                .foregroundStyle(.blue)

            VStack(alignment: .leading, spacing: 1) {
                Text("Create \"\(state.query)\"")
                    .font(.callout)
                    .lineLimit(1)

                Text("New note")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Text("enter")
                .font(.caption2)
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 3))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(state.isCreateOptionSelected ? Color.accentColor.opacity(0.1) : .clear)
        .contentShape(Rectangle())
    }

    // MARK: - No Results

    private var noResultsView: some View {
        VStack(spacing: 4) {
            Text("No matching notes")
                .font(.callout)
                .foregroundStyle(.secondary)
            Text("Type a title to create a new note")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
    }

    // MARK: - Actions

    private func handleSubmit() {
        if state.isCreateOptionSelected {
            onCreate(state.query)
            state.dismiss()
        } else if let note = state.selectedNote {
            onSelect(note)
            state.dismiss()
        }
    }
}

// MARK: - WikilinkAutocompleteRow

struct WikilinkAutocompleteRow: View {
    @ObservedObject var note: NoteEntity
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 8) {
            NoteTypeBadge(type: note.noteType)

            VStack(alignment: .leading, spacing: 2) {
                Text(note.title.isEmpty ? "Untitled" : note.title)
                    .font(.callout)
                    .lineLimit(1)

                HStack(spacing: 6) {
                    if let zettelId = note.zettelId {
                        Text(zettelId)
                            .font(.caption2)
                            .monospaced()
                            .foregroundStyle(.tertiary)
                    }

                    if !note.contentPlainText.isEmpty {
                        Text(note.contentPlainText.prefix(60))
                            .font(.caption2)
                            .foregroundStyle(.quaternary)
                            .lineLimit(1)
                    }
                }
            }

            Spacer()

            PARABadge(category: note.paraCategory)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(isSelected ? Color.accentColor.opacity(0.1) : .clear)
        .contentShape(Rectangle())
    }
}
