import SwiftUI
import CoreData

/// Card sort options for NoteCardGrid.
enum CardSortOrder: String, CaseIterable, Identifiable {
    case date = "Date"
    case type = "Type"
    case links = "Links"

    var id: String { rawValue }
}

/// An alternative to the list StackView -- shows notes as physical 4x6 cards in a grid.
/// MOROS styled: LIMIT-02 background, sharp corners, border, color stripe at top.
struct NoteCardGrid: View {
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

    @State private var sortOrder: CardSortOrder = .date

    private let columns = [
        GridItem(.adaptive(minimum: 260, maximum: 340), spacing: 12)
    ]

    var body: some View {
        VStack(spacing: 0) {
            // Sort toolbar
            HStack {
                Text("\(filteredAndSortedNotes.count) cards")
                    .font(Moros.fontMonoSmall)
                    .foregroundStyle(Moros.textDim)

                Spacer()

                Picker("Sort", selection: $sortOrder) {
                    ForEach(CardSortOrder.allCases) { order in
                        Text(order.rawValue).tag(order)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 180)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)

            Rectangle().fill(Moros.border).frame(height: 1)

            // Card Grid
            ScrollView {
                if filteredAndSortedNotes.isEmpty {
                    EmptyStateView(
                        icon: "rectangle.on.rectangle",
                        title: "No Cards",
                        subtitle: "Press Cmd+N to create your first note"
                    )
                    .padding(.top, 60)
                } else {
                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(filteredAndSortedNotes, id: \.objectID) { note in
                            GridNoteCard(note: note)
                                .onTapGesture {
                                    appState.selectedNote = note
                                }
                                .transition(.morosScale)
                        }
                    }
                    .padding(16)
                    .animation(.morosGentle, value: filteredAndSortedNotes.count)
                }
            }
        }
        .morosBackground(Moros.limit01)
    }

    // MARK: - Filtering & Sorting

    private var filteredAndSortedNotes: [NoteEntity] {
        // Deduplicate
        var seen = Set<String>()
        var result = Array(notes).filter { note in
            guard let zid = note.zettelId else { return true }
            if seen.contains(zid) { return false }
            seen.insert(zid)
            return true
        }

        // Apply filters
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
            let query = appState.searchQuery.lowercased()
            result = result.filter {
                $0.title.lowercased().contains(query) ||
                $0.contentPlainText.lowercased().contains(query)
            }
        }

        // Sort
        switch sortOrder {
        case .date:
            result.sort { ($0.updatedAt ?? .distantPast) > ($1.updatedAt ?? .distantPast) }
        case .type:
            result.sort { $0.noteTypeRaw < $1.noteTypeRaw }
        case .links:
            result.sort { $0.totalLinkCount > $1.totalLinkCount }
        }

        return result
    }
}

// MARK: - Grid Note Card

struct GridNoteCard: View {
    @ObservedObject var note: NoteEntity
    @Environment(\.managedObjectContext) private var context
    @State private var isHovered: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Color stripe at top
            Rectangle()
                .fill(stripeColor)
                .frame(height: 5)

            VStack(alignment: .leading, spacing: 8) {
                // Title
                Text(note.title.isEmpty ? "Untitled" : note.title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Moros.textMain)
                    .lineLimit(2)

                // Content preview (first 3 lines)
                if !note.contentPlainText.isEmpty {
                    Text(String(note.contentPlainText.prefix(180)))
                        .font(.system(size: 11))
                        .foregroundStyle(Moros.textSub)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)

                // Source reference (for literature notes)
                if let sourceTitle = note.sourceTitle {
                    HStack(spacing: 4) {
                        Image(systemName: "book.closed")
                            .font(.system(size: 9))
                            .foregroundStyle(Moros.textDim)
                        Text(sourceTitle)
                            .font(.system(size: 9))
                            .foregroundStyle(Moros.textDim)
                            .lineLimit(1)
                    }
                }

                // Bottom row: tags, type icon, zettel ID
                HStack(spacing: 6) {
                    // Note type icon
                    Image(systemName: note.noteType.icon)
                        .font(.system(size: 9))
                        .foregroundStyle(noteTypeColor)

                    // Tags (first 2)
                    ForEach(note.tagsArray.prefix(2), id: \.objectID) { tag in
                        if let name = tag.name {
                            Text("#\(name)")
                                .font(.system(size: 8, weight: .medium, design: .monospaced))
                                .foregroundStyle(Moros.oracle)
                        }
                    }

                    Spacer()

                    // Zettel ID
                    if let zettelId = note.zettelId {
                        Text(zettelId)
                            .font(.system(size: 8, weight: .regular, design: .monospaced))
                            .foregroundStyle(Moros.textGhost)
                    }
                }
            }
            .padding(12)
        }
        .frame(height: 180)
        .background(Moros.limit02)
        .overlay(Rectangle().stroke(isHovered ? Moros.borderLit : Moros.border, lineWidth: 1))
        .shadow(color: isHovered ? Moros.oracle.opacity(0.1) : .clear, radius: 8, x: 0, y: 0)
        .scaleEffect(isHovered ? 1.03 : 1.0)
        .onHover { isHovered = $0 }
        .animation(.morosSnap, value: isHovered)
        .contextMenu { noteContextMenu }
    }

    // MARK: - Context Menu

    @ViewBuilder
    private var noteContextMenu: some View {
        Button(action: {
            note.isPinned.toggle()
            try? context.save()
        }) {
            Label(note.isPinned ? "Unpin" : "Pin", systemImage: note.isPinned ? "pin.slash" : "pin")
        }

        Button(action: {
            let service = NoteService(context: context)
            service.archiveNote(note)
        }) {
            Label("Archive", systemImage: "archivebox")
        }
    }

    // MARK: - Computed

    private var stripeColor: Color {
        if let hex = note.colorHex {
            return Color(hex: hex)
        }
        return noteTypeColor.opacity(0.6)
    }

    private var noteTypeColor: Color {
        switch note.noteType {
        case .fleeting: Moros.ambient
        case .literature: Moros.oracle
        case .permanent: Moros.verdit
        case .structure: Moros.textSub
        }
    }
}
