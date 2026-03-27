import SwiftUI
import CoreData

struct CommandPaletteView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @Environment(\.managedObjectContext) private var context
    @State private var query = ""
    @State private var searchResults: [SearchResult] = []
    @State private var selectedScope: SearchScope = .all

    private var searchService: SearchService {
        SearchService(context: context)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Search field
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search notes, commands...", text: $query)
                    .textFieldStyle(.plain)
                    .font(.title3)
                    .onSubmit { executeFirst() }

                if !query.isEmpty {
                    Button(action: { query = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding()

            // Scope filter pills
            if !query.isEmpty {
                HStack(spacing: 6) {
                    ForEach(SearchScope.allCases) { scope in
                        Button(action: { selectedScope = scope }) {
                            Text(scope.rawValue)
                                .font(.caption)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(
                                    selectedScope == scope
                                        ? Color.accentColor.opacity(0.2)
                                        : Color.secondary.opacity(0.1),
                                    in: Capsule()
                                )
                                .foregroundStyle(selectedScope == scope ? .primary : .secondary)
                        }
                        .buttonStyle(.plain)
                    }
                    Spacer()
                }
                .padding(.horizontal)
                .padding(.bottom, 6)
            }

            Divider()

            // Results
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    if query.isEmpty {
                        // Recent searches
                        let recents = searchService.recentSearches
                        if !recents.isEmpty {
                            CommandSection(title: "Recent Searches") {
                                ForEach(recents, id: \.self) { recent in
                                    CommandRow(icon: "clock", label: recent) {
                                        query = recent
                                    }
                                }
                                Button(action: {
                                    searchService.clearRecentSearches()
                                }) {
                                    HStack {
                                        Spacer()
                                        Text("Clear Recent Searches")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                        Spacer()
                                    }
                                    .padding(.vertical, 4)
                                }
                                .buttonStyle(.plain)
                            }
                        }

                        CommandSection(title: "Actions") {
                            CommandRow(icon: "plus", label: "New Note", shortcut: "\u{2318}N") {
                                createNote()
                            }
                            CommandRow(icon: "rectangle.on.rectangle", label: "Switch to Desk", shortcut: "\u{2318}1") {
                                appState.selectedView = .desk; dismiss()
                            }
                            CommandRow(icon: "square.stack", label: "Switch to Stack", shortcut: "\u{2318}2") {
                                appState.selectedView = .stack; dismiss()
                            }
                            CommandRow(icon: "point.3.connected.trianglepath.dotted", label: "Switch to Graph", shortcut: "\u{2318}3") {
                                appState.selectedView = .graph; dismiss()
                            }
                        }
                    } else {
                        if !searchResults.isEmpty {
                            CommandSection(title: "Notes (\(searchResults.count))") {
                                ForEach(searchResults) { result in
                                    Button(action: { selectNote(result.note) }) {
                                        HStack {
                                            Image(systemName: "note.text")
                                                .frame(width: 20)
                                            VStack(alignment: .leading) {
                                                Text(result.note.title.isEmpty ? "Untitled" : result.note.title)
                                                    .lineLimit(1)
                                                if let zettelId = result.note.zettelId {
                                                    Text(zettelId)
                                                        .font(.caption)
                                                        .foregroundStyle(.tertiary)
                                                        .monospaced()
                                                }
                                            }
                                            Spacer()
                                            // Relevance indicator
                                            HStack(spacing: 4) {
                                                Image(systemName: result.matchType.icon)
                                                    .font(.caption2)
                                                Text(result.matchType.label)
                                                    .font(.caption2)
                                            }
                                            .foregroundStyle(.secondary)
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 2)
                                            .background(Color.secondary.opacity(0.1), in: Capsule())

                                            PARABadge(category: result.note.paraCategory)
                                        }
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 6)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        } else {
                            Text("No results")
                                .foregroundStyle(.secondary)
                                .padding()
                        }
                    }
                }
            }
            .frame(maxHeight: 400)
        }
        .frame(width: 540)
        .background(.ultraThickMaterial, in: RoundedRectangle(cornerRadius: 12))
        .onChange(of: query) { performSearch() }
        .onChange(of: selectedScope) { performSearch() }
    }

    private func performSearch() {
        guard !query.isEmpty else { searchResults = []; return }
        searchResults = searchService.search(query: query, scope: selectedScope)
    }

    private func selectNote(_ note: NoteEntity) {
        searchService.addRecentSearch(query)
        appState.selectedNote = note
        dismiss()
    }

    private func createNote() {
        let service = NoteService(context: context)
        let note = service.createNote()
        appState.selectedNote = note
        dismiss()
    }

    private func executeFirst() {
        if let first = searchResults.first {
            selectNote(first.note)
        }
    }
}

// MARK: - Command Palette Components

struct CommandSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.tertiary)
                .padding(.horizontal, 12)
                .padding(.top, 8)
                .padding(.bottom, 4)
            content
        }
    }
}

struct CommandRow: View {
    let icon: String
    let label: String
    var shortcut: String = ""
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Image(systemName: icon)
                    .frame(width: 20)
                Text(label)
                Spacer()
                if !shortcut.isEmpty {
                    Text(shortcut)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
