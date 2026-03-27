import SwiftUI

struct NoteEditorView: View {
    @ObservedObject var note: NoteEntity
    @Environment(\.managedObjectContext) private var context
    @EnvironmentObject var appState: AppState
    @State private var title: String = ""
    @State private var content: String = ""
    @State private var showBacklinks: Bool = true
    @State private var showSimilarNotes: Bool = true
    @State private var showLinkSuggestions: Bool = true
    @State private var showLinkBrowser: Bool = false
    @State private var showLinkCreation: Bool = false
    @State private var showLocalGraph: Bool = false

    // Wikilink autocomplete
    @StateObject private var wikilinkState = WikilinkAutocompleteState()
    @State private var wikilinkAnchorPoint: CGPoint = .zero

    // AI Classification
    @State private var isClassifying: Bool = false
    @State private var classificationError: String?

    // Auto-classify debounce
    @State private var autoClassifyTask: Task<Void, Never>?

    // Promotion
    @State private var showPromotionSheet: Bool = false
    @State private var contextNote: String = ""
    @State private var isContextExpanded: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            // Sequence Navigator
            if let zettelId = note.zettelId {
                SequenceNavigator(zettelId: zettelId)
                    .padding(.horizontal)
                    .padding(.top, 6)
            }

            // Header
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    if let zettelId = note.zettelId {
                        Text(zettelId)
                            .font(Moros.fontMonoCaption)
                            .foregroundStyle(Moros.textDim)
                            .textSelection(.enabled)
                    }
                    Spacer()

                    // Classify button
                    Button(action: classifyNote) {
                        if isClassifying {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Image(systemName: "brain")
                        }
                    }
                    .buttonStyle(.plain)
                    .font(.caption)
                    .foregroundStyle(note.aiClassified ? Moros.oracle : Moros.textDim)
                    .help(note.aiClassified ? "Re-classify with AI" : "Classify with AI")
                    .disabled(isClassifying)

                    NoteAtomicityIndicator(note: note)
                    NoteTypeBadge(type: note.noteType)
                    CODEStageBadge(stage: note.codeStage)
                    PARABadge(category: note.paraCategory)
                }

                TextField("What is this note's claim?", text: $title)
                    .textFieldStyle(.plain)
                    .font(.system(size: 24, weight: .light))
                    .foregroundStyle(Moros.textMain)
                    .onSubmit { saveChanges() }

                if let error = classificationError {
                    Text(error)
                        .font(Moros.fontCaption)
                        .foregroundStyle(Moros.signal)
                }
            }
            .padding()

            // Methodology Context Bar
            noteTypeContextBar

            Rectangle()
                .fill(Moros.border)
                .frame(height: 1)

            // Context Note — WHY this note exists, for AI classification
            contextNoteSection

            Rectangle()
                .fill(Moros.border)
                .frame(height: 1)

            // Content Editor with wikilink autocomplete overlay
            ZStack(alignment: .topLeading) {
                MarkdownTextView(
                    text: $content,
                    onWikilinkTrigger: { query in
                        wikilinkState.configure(context: context)
                        wikilinkState.show(initialQuery: query)
                    },
                    onWikilinkDismiss: {
                        wikilinkState.dismiss()
                    },
                    onContentChange: { newText in
                        scheduleAutoClassify()
                        debouncedSyncLinks()
                    },
                    onCursorPositionChange: { _ in }
                )

                // Wikilink autocomplete popup
                if wikilinkState.isVisible {
                    WikilinkAutocomplete(
                        state: wikilinkState,
                        onSelect: { selectedNote in
                            insertWikilinkForSelectedNote(selectedNote)
                        },
                        onCreate: { newTitle in
                            let parser = WikilinkParser(context: context)
                            let match = WikilinkMatch(
                                fullMatch: "[[\(newTitle)]]",
                                targetTitle: newTitle,
                                displayText: nil,
                                range: newTitle.startIndex..<newTitle.endIndex
                            )
                            let newNote = parser.createNoteFromBrokenLink(match)
                            insertWikilinkForSelectedNote(newNote)
                        },
                        onDismiss: {
                            wikilinkState.dismiss()
                        }
                    )
                    .padding(.top, 40)
                    .padding(.leading, 20)
                }
            }

            Rectangle()
                .fill(Moros.border)
                .frame(height: 1)

            // Footer — Tags + Actions
            HStack {
                Image(systemName: "tag")
                    .foregroundStyle(Moros.textDim)
                ForEach(note.tagsArray, id: \.objectID) { tag in
                    if let name = tag.name {
                        TagBadge(name: name)
                    }
                }
                Spacer()

                Button(action: { showLinkCreation = true }) {
                    Label("Link", systemImage: "link.badge.plus")
                }
                .buttonStyle(.plain)
                .font(.caption)
                .foregroundStyle(Moros.oracle)

                Button(action: { showLinkBrowser.toggle() }) {
                    Label("\(note.totalLinkCount)", systemImage: "arrow.triangle.branch")
                }
                .buttonStyle(.plain)
                .font(.caption)
                .foregroundStyle(Moros.textSub)

                Button(action: { showLocalGraph.toggle() }) {
                    Image(systemName: "point.3.connected.trianglepath.dotted")
                }
                .buttonStyle(.plain)
                .font(.caption)
                .foregroundStyle(Moros.textSub)

                Button(action: { appState.isAIChatVisible.toggle() }) {
                    Image(systemName: "brain.head.profile")
                }
                .buttonStyle(.plain)
                .font(.caption)
                .foregroundStyle(appState.isAIChatVisible ? Moros.oracle : Moros.textSub)
                .help("Toggle AI Chat (Cmd+Shift+A)")

                if note.aiClassified {
                    HStack(spacing: 4) {
                        Image(systemName: "brain")
                        Text("\(Int(note.aiConfidence * 100))%")
                    }
                    .font(.caption)
                    .foregroundStyle(Moros.textDim)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)

            // Local Graph Panel (toggleable)
            if showLocalGraph {
                Rectangle()
                    .fill(Moros.border)
                    .frame(height: 1)
                LocalGraphView(centerNote: note)
                    .frame(height: 260)
            }

            // Backlinks Panel
            if showBacklinks {
                Rectangle()
                    .fill(Moros.border)
                    .frame(height: 1)
                BacklinksPanel(note: note)
            }

            // Similar Notes Panel
            if showSimilarNotes {
                Rectangle()
                    .fill(Moros.border)
                    .frame(height: 1)
                SimilarNotesPanel(
                    note: note,
                    embeddingService: EmbeddingService.shared
                )
            }

            // Link Suggestions Panel
            if showLinkSuggestions {
                Rectangle()
                    .fill(Moros.border)
                    .frame(height: 1)
                LinkSuggestionsPanel(note: note)
            }
        }
        .morosBackground(Moros.limit01)
        .onAppear {
            loadNote()
            wikilinkState.configure(context: context)
        }
        .onChange(of: note.objectID) { loadNote() }
        .onChange(of: title) { saveChanges() }
        .onChange(of: content) { saveChanges() }
        .sheet(isPresented: $showLinkCreation) {
            LinkCreationSheet(sourceNote: note)
                .environment(\.managedObjectContext, context)
        }
        .sheet(isPresented: $showLinkBrowser) {
            LinkBrowserView(note: note)
                .environment(\.managedObjectContext, context)
                .environmentObject(appState)
                .frame(minWidth: 500, minHeight: 400)
        }
        .sheet(isPresented: $showPromotionSheet) {
            PromotionSheet(note: note)
                .environment(\.managedObjectContext, context)
                .environmentObject(appState)
        }
    }

    // MARK: - Methodology Context Bar

    @ViewBuilder
    private var noteTypeContextBar: some View {
        switch note.noteType {
        case .fleeting:
            HStack(spacing: 8) {
                Image(systemName: "bolt.fill")
                    .foregroundStyle(Moros.ambient)
                Text("Fleeting note")
                    .font(Moros.fontCaption)
                    .foregroundStyle(Moros.textSub)
                Text("Process within 7 days or discard")
                    .font(Moros.fontCaption)
                    .foregroundStyle(Moros.textDim)
                Spacer()
                Button("Promote") {
                    showPromotionSheet = true
                }
                .font(Moros.fontCaption)
                .foregroundStyle(Moros.verdit)
                .buttonStyle(.plain)
            }
            .padding(.horizontal)
            .padding(.vertical, 6)
            .background(Moros.ambient.opacity(0.06))

        case .literature:
            HStack(spacing: 8) {
                Image(systemName: "book.fill")
                    .foregroundStyle(Moros.oracle)
                if let sourceTitle = note.sourceTitle {
                    Text("From: \(sourceTitle)")
                        .font(Moros.fontCaption)
                        .foregroundStyle(Moros.textSub)
                } else {
                    Text("Literature note")
                        .font(Moros.fontCaption)
                        .foregroundStyle(Moros.textSub)
                    Text("No source linked")
                        .font(Moros.fontCaption)
                        .foregroundStyle(Moros.signal)
                }
                Spacer()
            }
            .padding(.horizontal)
            .padding(.vertical, 6)
            .background(Moros.oracle.opacity(0.06))

        case .permanent:
            HStack(spacing: 8) {
                Image(systemName: "diamond.fill")
                    .foregroundStyle(Moros.verdit)
                if let zettelId = note.zettelId {
                    Text(zettelId)
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundStyle(Moros.verdit)
                    let fz = FolgezettelService(context: context)
                    if let parentId = fz.parentId(of: zettelId),
                       let parentNote = fz.findNote(byFolgezettelId: parentId, in: context) {
                        Text("continues from '\(parentId): \(parentNote.title)'")
                            .font(Moros.fontCaption)
                            .foregroundStyle(Moros.textDim)
                            .lineLimit(1)
                    }
                }
                Spacer()
            }
            .padding(.horizontal)
            .padding(.vertical, 6)
            .background(Moros.verdit.opacity(0.06))

        case .structure:
            HStack(spacing: 8) {
                Image(systemName: "folder.fill")
                    .foregroundStyle(Moros.textSub)
                Text("Structure note")
                    .font(Moros.fontCaption)
                    .foregroundStyle(Moros.textSub)
                Text("Curated overview / index note")
                    .font(Moros.fontCaption)
                    .foregroundStyle(Moros.textDim)
                Spacer()
            }
            .padding(.horizontal)
            .padding(.vertical, 6)
            .background(Moros.textSub.opacity(0.06))
        }
    }

    // MARK: - Context Note Section

    @ViewBuilder
    private var contextNoteSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Toggle header
            Button(action: {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isContextExpanded.toggle()
                }
            }) {
                HStack(spacing: 6) {
                    Image(systemName: isContextExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 9))
                        .foregroundStyle(Moros.textDim)
                    Image(systemName: "brain.filled.head.profile")
                        .font(.system(size: 11))
                        .foregroundStyle(contextNote.isEmpty ? Moros.textDim : Moros.oracle)
                    Text("CONTEXT")
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundStyle(Moros.textDim)
                    if !contextNote.isEmpty {
                        Text("(\(contextNote.count) chars)")
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundStyle(Moros.textGhost)
                    }
                    Spacer()
                    if contextNote.isEmpty {
                        Text("Por que essa nota existe?")
                            .font(.system(size: 10))
                            .foregroundStyle(Moros.textGhost)
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 6)
            }
            .buttonStyle(.plain)

            // Context editor (expandable)
            if isContextExpanded {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Descreva o contexto: de onde veio essa ideia, por que é relevante, como se conecta ao que você já sabe.")
                        .font(.system(size: 10))
                        .foregroundStyle(Moros.textDim)
                        .padding(.horizontal)

                    TextEditor(text: $contextNote)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(Moros.textSub)
                        .scrollContentBackground(.hidden)
                        .frame(minHeight: 48, maxHeight: 120)
                        .padding(.horizontal, 12)
                        .onChange(of: contextNote) { saveChanges() }
                }
                .padding(.bottom, 6)
                .background(Moros.oracle.opacity(0.03))
            }
        }
    }

    // MARK: - Note Loading / Saving

    private func loadNote() {
        title = note.title
        content = note.content
        contextNote = note.contextNote ?? ""
        isContextExpanded = !contextNote.isEmpty
    }

    private func saveChanges() {
        guard title != note.title || content != note.content || contextNote != (note.contextNote ?? "") else { return }
        let service = NoteService(context: context)
        service.updateNote(note, title: title, content: content)
        if contextNote != (note.contextNote ?? "") {
            note.contextNote = contextNote.isEmpty ? nil : contextNote
            try? context.save()
        }
    }

    // MARK: - Wikilink Insertion

    private func insertWikilinkForSelectedNote(_ selectedNote: NoteEntity) {
        let selectedTitle = selectedNote.title
        if let openRange = content.range(of: "[[", options: .backwards) {
            let afterOpen = content[openRange.upperBound...]
            if !afterOpen.contains("]]") {
                content = String(content[content.startIndex..<openRange.lowerBound]) + "[[\(selectedTitle)]]" + ""
            }
        }
        wikilinkState.dismiss()
    }

    // MARK: - Link Sync (debounced)

    @State private var linkSyncTask: Task<Void, Never>?

    private func debouncedSyncLinks() {
        linkSyncTask?.cancel()
        linkSyncTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            guard !Task.isCancelled else { return }
            let parser = WikilinkParser(context: context)
            parser.syncLinks(for: note)
        }
    }

    // MARK: - AI Classification

    private func classifyNote() {
        guard !isClassifying else { return }
        isClassifying = true
        classificationError = nil

        Task {
            do {
                let engine = ClassificationEngine()
                let tagService = TagService(context: context)
                let noteService = NoteService(context: context)

                let existingTags = tagService.topTags(limit: 30).compactMap { $0.name }
                let recentNotes = noteService.fetchNotes(limit: 30).compactMap { n -> (zettelId: String, title: String)? in
                    guard let zid = n.zettelId else { return nil }
                    return (zettelId: zid, title: n.title)
                }

                let result = try await engine.classify(
                    title: title,
                    content: content,
                    contextNote: contextNote.isEmpty ? nil : contextNote,
                    existingTags: existingTags,
                    recentNotes: recentNotes
                )

                await MainActor.run {
                    note.paraCategory = result.paraCategory
                    note.codeStage = result.codeStage
                    note.noteType = result.noteType
                    note.aiClassified = true
                    note.aiConfidence = Float(result.confidence)
                    note.updatedAt = Date()

                    for tagName in result.tags {
                        let tag = tagService.findOrCreate(name: tagName)
                        let currentTags = note.tagsArray.compactMap { $0.name }
                        if !currentTags.contains(tag.name ?? "") {
                            tagService.addTag(tag, to: note)
                        }
                    }

                    let linkService = LinkService(context: context)
                    for suggested in result.suggested_links {
                        if let targetNote = noteService.findByZettelId(suggested.zettel_id) {
                            let linkType: LinkType = {
                                switch suggested.link_type.lowercased() {
                                case "supports": return .supports
                                case "contradicts": return .contradicts
                                case "extends": return .extends
                                case "example": return .example
                                default: return .reference
                                }
                            }()
                            linkService.createLink(
                                from: note,
                                to: targetNote,
                                type: linkType,
                                context: suggested.reason,
                                strength: Float(suggested.strength),
                                isAISuggested: true
                            )
                        }
                    }

                    try? context.save()
                    isClassifying = false
                }
            } catch {
                await MainActor.run {
                    classificationError = "Classification failed: \(error.localizedDescription)"
                    isClassifying = false
                }
            }
        }
    }

    // MARK: - Auto-classify

    private func scheduleAutoClassify() {
        autoClassifyTask?.cancel()
        autoClassifyTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            guard !Task.isCancelled else { return }

            let totalText = title + content
            if totalText.count > 50 && !note.aiClassified && !isClassifying {
                classifyNote()
            }
        }
    }
}
