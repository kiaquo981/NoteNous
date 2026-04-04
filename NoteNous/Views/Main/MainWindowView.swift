import SwiftUI
import CoreData
import UniformTypeIdentifiers

// MARK: - Split Editor View

/// Manages the split editor layout: left pane (primary note) + resizable divider + right pane.
struct SplitEditorView: View {
    @EnvironmentObject var appState: AppState
    let primaryNote: NoteEntity

    @State private var splitFraction: CGFloat = 0.5

    private let minFraction: CGFloat = 0.25
    private let maxFraction: CGFloat = 0.75
    private let dividerWidth: CGFloat = 8

    var body: some View {
        GeometryReader { geo in
            let totalWidth = geo.size.width
            let leftWidth = max(0, totalWidth * splitFraction - dividerWidth / 2)
            let rightWidth = max(0, totalWidth * (1 - splitFraction) - dividerWidth / 2)

            HStack(spacing: 0) {
                // Left pane: primary note editor
                NoteEditorView(note: primaryNote)
                    .frame(width: leftWidth)
                    .clipped()

                // Resizable divider
                SplitDividerHandle()
                    .frame(width: dividerWidth)
                    .gesture(
                        DragGesture(minimumDistance: 1)
                            .onChanged { value in
                                let proposed = value.location.x / totalWidth
                                splitFraction = min(maxFraction, max(minFraction, proposed))
                            }
                    )

                // Right pane: split note editor or picker
                Group {
                    if let splitNote = appState.splitNote {
                        NoteEditorView(note: splitNote)
                    } else {
                        SplitNotePicker()
                    }
                }
                .frame(width: rightWidth)
                .clipped()
            }
        }
    }
}

/// The draggable divider between split panes.
private struct SplitDividerHandle: View {
    @State private var isHovered = false

    var body: some View {
        ZStack {
            Rectangle()
                .fill(Color.clear)
                .contentShape(Rectangle())

            RoundedRectangle(cornerRadius: 1)
                .fill(isHovered ? Moros.oracle.opacity(0.6) : Moros.border)
                .frame(width: isHovered ? 3 : 1)
                .animation(.easeInOut(duration: Moros.animFast), value: isHovered)
        }
        .onHover { hovering in
            isHovered = hovering
            if hovering {
                NSCursor.resizeLeftRight.push()
            } else {
                NSCursor.pop()
            }
        }
    }
}

// MARK: - Split Note Picker

/// Mini note picker shown in the right split pane when no second note is selected.
struct SplitNotePicker: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.managedObjectContext) private var context
    @State private var query: String = ""

    @FetchRequest(
        sortDescriptors: [
            NSSortDescriptor(keyPath: \NoteEntity.updatedAt, ascending: false)
        ],
        predicate: NSPredicate(format: "isArchived == NO"),
        animation: nil
    ) private var allNotes: FetchedResults<NoteEntity>

    private var filteredNotes: [NoteEntity] {
        let notes = Array(allNotes).filter { $0.objectID != appState.selectedNote?.objectID }
        if query.trimmingCharacters(in: .whitespaces).isEmpty {
            return Array(notes.prefix(30))
        }
        let lowerQuery = query.lowercased()
        return Array(notes.filter {
            $0.title.lowercased().contains(lowerQuery)
                || $0.content.lowercased().contains(lowerQuery)
                || ($0.zettelId?.lowercased().contains(lowerQuery) ?? false)
        }.prefix(30))
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Image(systemName: "rectangle.split.2x1")
                    .foregroundStyle(Moros.oracle)
                Text("Pick a note for split view")
                    .font(Moros.fontSubhead)
                    .foregroundStyle(Moros.textSub)
                Spacer()
                Button(action: {
                    appState.isSplitActive = false
                    appState.splitNote = nil
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Moros.textDim)
                }
                .buttonStyle(.plain)
                .help("Close split view (Cmd+\\)")
            }
            .padding()

            // Search
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(Moros.textDim)
                TextField("Search notes...", text: $query)
                    .textFieldStyle(.plain)
                    .font(Moros.fontBody)
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(Moros.limit02)

            Rectangle()
                .fill(Moros.border)
                .frame(height: 1)

            // Note list
            ScrollView {
                LazyVStack(spacing: 0) {
                    if query.isEmpty && !appState.recentNoteIds.isEmpty {
                        HStack {
                            Text("RECENT")
                                .font(Moros.fontLabel)
                                .foregroundStyle(Moros.textGhost)
                            Spacer()
                        }
                        .padding(.horizontal)
                        .padding(.top, 8)
                        .padding(.bottom, 4)

                        ForEach(recentNotes, id: \.objectID) { note in
                            SplitNotePickerRow(note: note) {
                                appState.splitNote = note
                            }
                        }

                        HStack {
                            Text("ALL NOTES")
                                .font(Moros.fontLabel)
                                .foregroundStyle(Moros.textGhost)
                            Spacer()
                        }
                        .padding(.horizontal)
                        .padding(.top, 12)
                        .padding(.bottom, 4)
                    }

                    ForEach(filteredNotes, id: \.objectID) { note in
                        SplitNotePickerRow(note: note) {
                            appState.splitNote = note
                        }
                    }

                    if filteredNotes.isEmpty {
                        VStack(spacing: 8) {
                            Image(systemName: "doc.text.magnifyingglass")
                                .font(.title2)
                                .foregroundStyle(Moros.textGhost)
                            Text("No matching notes")
                                .font(Moros.fontSmall)
                                .foregroundStyle(Moros.textDim)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.top, 40)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Moros.void)
    }

    private var recentNotes: [NoteEntity] {
        let request = NoteEntity.fetchRequest() as! NSFetchRequest<NoteEntity>
        let recentIds = Array(appState.recentNoteIds.prefix(5))
        guard !recentIds.isEmpty else { return [] }
        request.predicate = NSPredicate(
            format: "id IN %@ AND isArchived == NO",
            recentIds.map { $0 as CVarArg }
        )
        let results = (try? context.fetch(request)) ?? []
        return results.filter { $0.objectID != appState.selectedNote?.objectID }
    }
}

private struct SplitNotePickerRow: View {
    @ObservedObject var note: NoteEntity
    let onSelect: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(note.title.isEmpty ? "Untitled" : note.title)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Moros.textMain)
                        .lineLimit(1)

                    HStack(spacing: 6) {
                        if let zettelId = note.zettelId {
                            Text(zettelId)
                                .font(Moros.fontMonoSmall)
                                .foregroundStyle(Moros.textDim)
                        }
                        if let date = note.updatedAt {
                            Text(date, style: .relative)
                                .font(Moros.fontMonoSmall)
                                .foregroundStyle(Moros.textGhost)
                        }
                    }
                }
                Spacer()
                Image(systemName: "arrow.right.circle")
                    .foregroundStyle(isHovered ? Moros.oracle : Moros.textGhost)
                    .font(.caption)
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(isHovered ? Moros.limit03 : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

// MARK: - Main Window View

struct MainWindowView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.managedObjectContext) private var context
    @State private var isDropTargeted = false

    var body: some View {
        NavigationSplitView {
            SidebarView()
        } content: {
            ViewRouter()
        } detail: {
            HStack(spacing: 0) {
                if let note = appState.selectedNote {
                    if appState.isSplitActive {
                        SplitEditorView(primaryNote: note)
                    } else {
                        NoteEditorView(note: note)
                    }
                } else {
                    EmptyStateView(
                        icon: "note.text",
                        title: "No Note Selected",
                        subtitle: "Select a note or press \u{2318}N to create one"
                    )
                }

                if appState.isAIChatVisible {
                    Rectangle()
                        .fill(Moros.border)
                        .frame(width: 1)
                        .transition(.opacity)
                    AIChatSidePanel()
                        .transition(.morosSlideIn)
                }
            }
            .animation(.morosPanel, value: appState.isSplitActive)
        }
        .navigationSplitViewStyle(.balanced)
        .frame(minWidth: 900, minHeight: 600)
        .overlay {
            if isDropTargeted {
                Rectangle()
                    .strokeBorder(Moros.oracle, lineWidth: 3)
                    .background(Moros.oracle.opacity(0.05))
                    .allowsHitTesting(false)
            }
        }
        .onDrop(of: [.plainText, .url, .fileURL, .utf8PlainText], isTargeted: $isDropTargeted) { providers in
            handleDrop(providers)
            return true
        }
        .sheet(isPresented: $appState.isCommandPaletteVisible) {
            CommandPaletteView()
                .environmentObject(appState)
                .environment(\.managedObjectContext, context)
        }
        .overlay {
            if appState.isQuickSwitcherVisible {
                QuickSwitcherView()
                    .environmentObject(appState)
                    .environment(\.managedObjectContext, context)
                    .transition(.morosScale)
            }
        }
        .animation(.morosPanel, value: appState.isQuickSwitcherVisible)
        .animation(.morosPanel, value: appState.isAIChatVisible)
        .sheet(isPresented: $appState.isZettelCreationVisible) {
            ZettelCreationSheet()
                .environmentObject(appState)
                .environment(\.managedObjectContext, context)
        }
        .sheet(item: $appState.activeToolView) { tool in
            toolView(for: tool)
                .environmentObject(appState)
                .environment(\.managedObjectContext, context)
                .morosTheme()
                .frame(minWidth: 700, minHeight: 500)
        }

    }

    // MARK: - Tool Views

    @ViewBuilder
    func toolView(for tool: AppState.ToolView) -> some View {
        switch tool {
        case .sources:
            SourceBrowserView(sourceService: SourceService())
        case .readyToCard:
            SourcesDuePanel(sourceService: SourceService())
        case .cardView:
            EmptyView() // Card view switches ViewMode instead
        case .index:
            IndexBrowserView(indexService: IndexService())
        case .dashboard:
            WorkflowDashboard(sourceService: SourceService(), indexService: IndexService())
        case .processingQueue:
            FleetingReviewQueue()
        case .pipeline:
            ProcessingPipeline()
        case .zettelkastenAgent:
            AgentDashboard()
        case .aiChat:
            AIChatView()
        case .voiceInk:
            VoiceInkDashboard()
        case .callNotes:
            CallNoteListView(callNoteService: CallNoteService())
        }
    }

    // MARK: - Drop Handling

    private func handleDrop(_ providers: [NSItemProvider]) {
        for provider in providers {
            // File URLs (.txt, .md)
            if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { data, _ in
                    guard let urlData = data as? Data,
                          let url = URL(dataRepresentation: urlData, relativeTo: nil) else { return }
                    let ext = url.pathExtension.lowercased()
                    guard ext == "txt" || ext == "md" else { return }
                    guard let content = try? String(contentsOf: url, encoding: .utf8) else { return }
                    let title = url.deletingPathExtension().lastPathComponent
                    Task { @MainActor in
                        createDroppedNote(title: title, content: content)
                    }
                }
            }
            // Plain text or URL strings
            else if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
                provider.loadItem(forTypeIdentifier: UTType.plainText.identifier, options: nil) { data, _ in
                    guard let text = data as? String ?? (data as? Data).flatMap({ String(data: $0, encoding: .utf8) }) else { return }
                    Task { @MainActor in
                        createDroppedNote(title: "", content: text)
                    }
                }
            }
            else if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
                provider.loadItem(forTypeIdentifier: UTType.url.identifier, options: nil) { data, _ in
                    guard let urlData = data as? Data,
                          let url = URL(dataRepresentation: urlData, relativeTo: nil) else { return }
                    Task { @MainActor in
                        createDroppedNote(title: url.host ?? "Link", content: url.absoluteString)
                    }
                }
            }
        }
    }

    @MainActor
    private func createDroppedNote(title: String, content: String) {
        let service = NoteService(context: context)
        let note = service.createNote(title: title, content: content)
        appState.selectedNote = note
    }
}
