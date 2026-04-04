import SwiftUI

struct NoteEditorView: View {
    @ObservedObject var note: NoteEntity
    @Environment(\.managedObjectContext) private var context
    @EnvironmentObject var appState: AppState
    @State private var title: String = ""
    @State private var content: String = ""
    @State private var showBacklinks: Bool = false
    @State private var showSimilarNotes: Bool = false
    @State private var showLinkSuggestions: Bool = false
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

    // Wikilink navigation — create-on-click confirmation
    @State private var pendingWikilinkTitle: String?
    @State private var showCreateWikilinkSheet: Bool = false

    // Promotion
    @State private var showPromotionSheet: Bool = false
    @State private var contextNote: String = ""
    @State private var isContextExpanded: Bool = false

    // Atomicity
    @State private var showSplitSheet: Bool = false
    @State private var atomicityReport: AtomicityReport?
    @State private var atomicityCheckTask: Task<Void, Never>?

    var body: some View {
        VStack(spacing: 0) {
            // Navigation Bar: History + Sequence Navigator
            HStack(spacing: 8) {
                // Back / Forward history buttons
                HStack(spacing: 2) {
                    Button {
                        appState.navigateBack()
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.caption)
                            .frame(width: 24, height: 24)
                            .foregroundStyle(appState.canGoBack ? Moros.oracle : Moros.textGhost)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(!appState.canGoBack)
                    .help("Back (Cmd+[)")

                    Button {
                        appState.navigateForward()
                    } label: {
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .frame(width: 24, height: 24)
                            .foregroundStyle(appState.canGoForward ? Moros.oracle : Moros.textGhost)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(!appState.canGoForward)
                    .help("Forward (Cmd+])")
                }
                .padding(.horizontal, 4)
                .padding(.vertical, 4)
                .background(Moros.limit02, in: Rectangle())

                if let zettelId = note.zettelId {
                    SequenceNavigator(zettelId: zettelId)
                }

                Spacer()
            }
            .padding(.horizontal)
            .padding(.top, 6)
            .onChange(of: appState.shouldNavigateBack) {
                if appState.shouldNavigateBack {
                    appState.navigateBack()
                    appState.shouldNavigateBack = false
                }
            }
            .onChange(of: appState.shouldNavigateForward) {
                if appState.shouldNavigateForward {
                    appState.navigateForward()
                    appState.shouldNavigateForward = false
                }
            }

            // Breadcrumb Navigation
            BreadcrumbBar(note: note)

            // Header
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        if let zettelId = note.zettelId {
                            Text(zettelId)
                                .font(Moros.fontMonoCaption)
                                .foregroundStyle(Moros.textDim)
                                .textSelection(.enabled)
                        }
                        Button(action: { VaultService.shared.showInFinder(note) }) {
                            HStack(spacing: 4) {
                                Image(systemName: "folder")
                                Text(VaultService.shared.filePath(for: note).path)
                            }
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundStyle(.tertiary)
                        }
                        .buttonStyle(.plain)
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

                    HStack(spacing: 4) {
                        NoteAtomicityIndicator(note: note)
                        NoteTypeBadge(type: note.noteType)
                        CODEStageBadge(stage: note.codeStage)
                        PARABadge(category: note.paraCategory)
                    }
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

            // Atomic Warning Bar (permanent/literature notes only)
            if let report = atomicityReport,
               (note.noteType == .permanent || note.noteType == .literature) {
                AtomicWarningBar(
                    report: report,
                    onSplit: { showSplitSheet = true },
                    onRefineTitle: {
                        let refined = Constants.autoTitle(from: note.content, fallback: note.title)
                        if refined != note.title {
                            note.title = refined
                            note.updatedAt = Date()
                            try? context.save()
                        }
                    }
                )
                .transition(.morosScale)
            }

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
                    onCursorPositionChange: { _ in },
                    onWikilinkClick: { title in
                        handleWikilinkNavigation(title: title)
                    }
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
                    .transition(.morosDropDown)
            }

            // Backlinks Panel
            if showBacklinks {
                Rectangle()
                    .fill(Moros.border)
                    .frame(height: 1)
                BacklinksPanel(note: note)
                    .transition(.morosDropDown)
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
                .transition(.morosDropDown)
            }

            // Link Suggestions Panel
            if showLinkSuggestions {
                Rectangle()
                    .fill(Moros.border)
                    .frame(height: 1)
                LinkSuggestionsPanel(note: note)
                    .transition(.morosDropDown)
            }
        }
        .frame(maxWidth: .infinity)
        .clipped()

        .animation(.morosPanel, value: showLocalGraph)
        .animation(.morosPanel, value: showBacklinks)
        .animation(.morosPanel, value: showSimilarNotes)
        .animation(.morosPanel, value: showLinkSuggestions)
        .onAppear {
            loadNote()
            wikilinkState.configure(context: context)
        }
        .onChange(of: note.objectID) { loadNote() }
        .onChange(of: title) { saveChanges(); debouncedAtomicityCheck() }
        .onChange(of: content) { saveChanges(); debouncedAtomicityCheck() }
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
        .sheet(isPresented: $showSplitSheet) {
            SplitNoteSheet(note: note)
                .environment(\.managedObjectContext, context)
                .environmentObject(appState)
        }
        .alert(
            "Create note?",
            isPresented: $showCreateWikilinkSheet
        ) {
            Button("Create") {
                if let title = pendingWikilinkTitle {
                    confirmCreateAndNavigate(title: title)
                    pendingWikilinkTitle = nil
                }
            }
            Button("Cancel", role: .cancel) {
                pendingWikilinkTitle = nil
            }
        } message: {
            if let title = pendingWikilinkTitle {
                Text("No note titled \"\(title)\" exists. Create it now?")
            }
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
                withAnimation(.morosSnap) {
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
        // Collapse all panels for clean writing space
        showBacklinks = false
        showSimilarNotes = false
        showLinkSuggestions = false
        showLocalGraph = false
        // Check atomicity
        recalculateAtomicity()
    }

    private func saveChanges() {
        guard title != note.title || content != note.content || contextNote != (note.contextNote ?? "") else { return }
        let service = NoteService(context: context)
        service.updateNote(note, title: title, content: content)
        if contextNote != (note.contextNote ?? "") {
            note.contextNote = contextNote.isEmpty ? nil : contextNote
            try? context.save()
        }
        VaultService.shared.syncNote(note)
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

    // MARK: - Wikilink Navigation

    private func handleWikilinkNavigation(title: String) {
        let parser = WikilinkParser(context: context)

        if let existing = parser.findNote(byTitle: title) {
            // Note exists — navigate directly and ensure link
            let linkService = LinkService(context: context)
            if note.objectID != existing.objectID {
                linkService.createLink(from: note, to: existing, type: .reference)
            }
            appState.selectedNote = existing
        } else {
            // Note does not exist — ask the user before creating
            pendingWikilinkTitle = title
            showCreateWikilinkSheet = true
        }
    }

    private func confirmCreateAndNavigate(title: String) {
        let noteService = NoteService(context: context)
        let linkService = LinkService(context: context)

        let newNote = noteService.createNote(title: title)

        if note.objectID != newNote.objectID {
            linkService.createLink(from: note, to: newNote, type: .reference)
        }

<<<<<<< HEAD
        appState.selectedNote = newNote
=======
        if note.objectID != targetNote.objectID {
            linkService.createLink(from: note, to: targetNote, type: .reference)
        }

        appState.navigateToNote(targetNote)
>>>>>>> feature/moros/nav-history
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

    // MARK: - Atomicity Check (debounced)

    private func recalculateAtomicity() {
        guard note.noteType == .permanent || note.noteType == .literature else {
            atomicityReport = nil
            return
        }
        let service = AtomicNoteService(context: context)
        atomicityReport = service.analyze(note: note)
    }

    private func debouncedAtomicityCheck() {
        atomicityCheckTask?.cancel()
        atomicityCheckTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            guard !Task.isCancelled else { return }
            recalculateAtomicity()
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

// MARK: - Breadcrumb Navigation Bar

struct BreadcrumbBar: View {
    @ObservedObject var note: NoteEntity
    @EnvironmentObject var appState: AppState

    var body: some View {
        HStack(spacing: 0) {
            // PARA Category segment
            BreadcrumbSegment(
                icon: note.paraCategory.icon,
                label: note.paraCategory.label,
                accentColor: paraAccentColor
            ) {
                if appState.selectedPARAFilter == note.paraCategory {
                    appState.selectedPARAFilter = nil
                } else {
                    appState.selectedPARAFilter = note.paraCategory
                }
            }

            // Project or Area segment (if assigned)
            if let project = note.project, let projectName = project.name {
                BreadcrumbChevron()
                BreadcrumbSegment(
                    icon: "folder.fill",
                    label: projectName,
                    accentColor: Moros.oracle
                ) {
                    appState.selectedPARAFilter = .project
                }
            } else if let area = note.area, let areaName = area.name {
                BreadcrumbChevron()
                BreadcrumbSegment(
                    icon: "square.stack.3d.up.fill",
                    label: areaName,
                    accentColor: Moros.verdit
                ) {
                    appState.selectedPARAFilter = .area
                }
            }

            // Note title segment (non-interactive)
            BreadcrumbChevron()
            Text(note.title.isEmpty ? "Untitled" : note.title)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Moros.textMain)
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer()
        }
        .padding(.horizontal)
        .padding(.vertical, 6)
        .background(Moros.border.opacity(0.15))
    }

    private var paraAccentColor: Color {
        switch note.paraCategory {
        case .inbox: return Moros.ambient
        case .project: return Moros.oracle
        case .area: return Moros.verdit
        case .resource: return Moros.ambient
        case .archive: return Moros.textDim
        }
    }
}

// MARK: - Breadcrumb Segment (clickable)

private struct BreadcrumbSegment: View {
    let icon: String
    let label: String
    let accentColor: Color
    let action: () -> Void

    @State private var isHovered: Bool = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 10))
                Text(label)
                    .font(.system(size: 11, weight: .regular))
            }
            .foregroundStyle(isHovered ? accentColor : Moros.textSub)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                isHovered ? accentColor.opacity(0.08) : Color.clear,
                in: RoundedRectangle(cornerRadius: 4)
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
        }
    }
}

// MARK: - Breadcrumb Chevron Separator

private struct BreadcrumbChevron: View {
    var body: some View {
        Image(systemName: "chevron.right")
            .font(.system(size: 8, weight: .semibold))
            .foregroundStyle(Moros.textGhost)
            .padding(.horizontal, 4)
    }
}
