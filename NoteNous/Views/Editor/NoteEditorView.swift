import SwiftUI

struct NoteEditorView: View {
    @ObservedObject var note: NoteEntity
    @Environment(\.managedObjectContext) private var context
    @EnvironmentObject var appState: AppState
    @State private var title: String = ""
    @State private var content: String = ""
    @State private var showBacklinks: Bool = true
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
                            .font(.caption)
                            .monospaced()
                            .foregroundStyle(.tertiary)
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
                    .foregroundStyle(note.aiClassified ? .purple : .secondary)
                    .help(note.aiClassified ? "Re-classify with AI" : "Classify with AI")
                    .disabled(isClassifying)

                    NoteAtomicityIndicator(note: note)
                    NoteTypeBadge(type: note.noteType)
                    CODEStageBadge(stage: note.codeStage)
                    PARABadge(category: note.paraCategory)
                }

                TextField("What is this note's claim?", text: $title)
                    .textFieldStyle(.plain)
                    .font(.title2.weight(.bold))
                    .onSubmit { saveChanges() }

                if let error = classificationError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
            .padding()

            Divider()

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

            Divider()

            // Footer — Tags + Actions
            HStack {
                Image(systemName: "tag")
                    .foregroundStyle(.secondary)
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

                Button(action: { showLinkBrowser.toggle() }) {
                    Label("\(note.totalLinkCount)", systemImage: "arrow.triangle.branch")
                }
                .buttonStyle(.plain)
                .font(.caption)

                Button(action: { showLocalGraph.toggle() }) {
                    Image(systemName: "point.3.connected.trianglepath.dotted")
                }
                .buttonStyle(.plain)
                .font(.caption)

                if note.aiClassified {
                    HStack(spacing: 4) {
                        Image(systemName: "brain")
                        Text("\(Int(note.aiConfidence * 100))%")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)

            // Local Graph Panel (toggleable)
            if showLocalGraph {
                Divider()
                LocalGraphView(centerNote: note)
                    .frame(height: 260)
            }

            // Backlinks Panel
            if showBacklinks {
                Divider()
                BacklinksPanel(note: note)
            }
        }
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
    }

    // MARK: - Note Loading / Saving

    private func loadNote() {
        title = note.title
        content = note.content
    }

    private func saveChanges() {
        guard title != note.title || content != note.content else { return }
        let service = NoteService(context: context)
        service.updateNote(note, title: title, content: content)
    }

    // MARK: - Wikilink Insertion

    private func insertWikilinkForSelectedNote(_ selectedNote: NoteEntity) {
        // Insert via the MarkdownTextView coordinator is not directly accessible here,
        // so we perform a text-level replacement: find the open `[[query` and replace with `[[Title]]`
        let selectedTitle = selectedNote.title
        // Find the last unclosed [[ in content up to where the user was typing
        if let openRange = content.range(of: "[[", options: .backwards) {
            let afterOpen = content[openRange.upperBound...]
            if !afterOpen.contains("]]") {
                // Replace from [[ to end of query with [[Title]]
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
            try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 second debounce
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

                // Gather context
                let existingTags = tagService.topTags(limit: 30).compactMap { $0.name }
                let recentNotes = noteService.fetchNotes(limit: 30).compactMap { n -> (zettelId: String, title: String)? in
                    guard let zid = n.zettelId else { return nil }
                    return (zettelId: zid, title: n.title)
                }

                let result = try await engine.classify(
                    title: title,
                    content: content,
                    existingTags: existingTags,
                    recentNotes: recentNotes
                )

                await MainActor.run {
                    // Apply classification results
                    note.paraCategory = result.paraCategory
                    note.codeStage = result.codeStage
                    note.noteType = result.noteType
                    note.aiClassified = true
                    note.aiConfidence = Float(result.confidence)
                    note.updatedAt = Date()

                    // Apply tags
                    for tagName in result.tags {
                        let tag = tagService.findOrCreate(name: tagName)
                        let currentTags = note.tagsArray.compactMap { $0.name }
                        if !currentTags.contains(tag.name ?? "") {
                            tagService.addTag(tag, to: note)
                        }
                    }

                    // Apply suggested links
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

                    // Save
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
            try? await Task.sleep(nanoseconds: 3_000_000_000) // 3 second debounce
            guard !Task.isCancelled else { return }

            // Only auto-classify if: >50 chars, not yet classified, not currently classifying
            let totalText = title + content
            if totalText.count > 50 && !note.aiClassified && !isClassifying {
                classifyNote()
            }
        }
    }
}
