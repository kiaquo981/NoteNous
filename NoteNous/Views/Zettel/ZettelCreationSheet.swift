import SwiftUI
import CoreData

/// The heart of the Zettelkasten creation flow.
/// Replaces the generic "New Note" with a methodology-guided multi-step sheet.
struct ZettelCreationSheet: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.managedObjectContext) private var context
    @Environment(\.dismiss) private var dismiss

    // MARK: - State

    @State private var currentStep: CreationStep = .chooseType
    @State private var selectedNoteType: NoteType = .fleeting

    // Folgezettel placement (permanent only)
    @State private var placementMode: PlacementMode = .newRoot
    @State private var selectedParentNote: NoteEntity?
    @State private var parentSearchQuery: String = ""

    // Content
    @State private var title: String = ""
    @State private var content: String = ""
    @State private var contextNote: String = ""

    // Source (literature only)
    @State private var selectedSource: Source?
    @State private var newSourceTitle: String = ""
    @State private var newSourceAuthor: String = ""
    @State private var newSourceType: SourceType = .book
    @State private var pageReference: String = ""
    @State private var showNewSourceForm: Bool = false

    // Connect (permanent only)
    @State private var linkSearchQuery: String = ""
    @State private var selectedLinkNotes: [(note: NoteEntity, type: LinkType)] = []
    @State private var tagInput: String = ""
    @State private var selectedTagNames: [String] = []

    @StateObject private var sourceService = SourceService()

    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \NoteEntity.updatedAt, ascending: false)],
        predicate: NSCompoundPredicate(andPredicateWithSubpredicates: [
            NSPredicate(format: "isArchived == NO"),
            NSPredicate(format: "noteTypeRaw == %d", NoteType.permanent.rawValue)
        ])
    ) private var permanentNotes: FetchedResults<NoteEntity>

    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \NoteEntity.updatedAt, ascending: false)],
        predicate: NSPredicate(format: "isArchived == NO")
    ) private var allNotes: FetchedResults<NoteEntity>

    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \TagEntity.usageCount, ascending: false)]
    ) private var allTags: FetchedResults<TagEntity>

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            sheetHeader
            Rectangle().fill(Moros.border).frame(height: 1)
            stepContent
            Rectangle().fill(Moros.border).frame(height: 1)
            sheetFooter
        }
        .frame(minWidth: 560, minHeight: 500)

        .preferredColorScheme(.dark)
    }

    // MARK: - Header

    private var sheetHeader: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("New Zettel")
                    .font(Moros.fontH2)
                    .foregroundStyle(Moros.textMain)
                Text(stepSubtitle)
                    .font(Moros.fontCaption)
                    .foregroundStyle(Moros.textDim)
            }
            Spacer()
            stepIndicator
            Spacer().frame(width: 16)
            Button(action: { dismiss() }) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(Moros.textDim)
            }
            .buttonStyle(.plain)
        }
        .padding()
    }

    private var stepIndicator: some View {
        HStack(spacing: 4) {
            ForEach(stepsForCurrentType, id: \.self) { step in
                Rectangle()
                    .fill(step == currentStep ? Moros.oracle : (step.rawValue < currentStep.rawValue ? Moros.verdit : Moros.limit03))
                    .frame(width: 24, height: 3)
            }
        }
    }

    private var stepSubtitle: String {
        switch currentStep {
        case .chooseType: "What type of thought is this?"
        case .placement: "Where does this idea live in your Zettelkasten?"
        case .source: "What source does this come from?"
        case .titleContent: selectedNoteType == .permanent ? "State your idea as a claim" : "Capture your thought"
        case .connect: "Link this idea to your existing knowledge"
        }
    }

    private var stepsForCurrentType: [CreationStep] {
        switch selectedNoteType {
        case .fleeting:
            return [.chooseType, .titleContent]
        case .literature:
            return [.chooseType, .source, .titleContent, .connect]
        case .permanent:
            return [.chooseType, .placement, .titleContent, .connect]
        case .structure:
            return [.chooseType, .titleContent, .connect]
        }
    }

    // MARK: - Step Content

    @ViewBuilder
    private var stepContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                switch currentStep {
                case .chooseType:
                    typeSelectionView
                case .placement:
                    placementView
                case .source:
                    sourceView
                case .titleContent:
                    titleContentView
                case .connect:
                    connectView
                }
            }
            .padding()
        }
    }

    // MARK: - Step 1: Type Selection

    private var typeSelectionView: some View {
        VStack(spacing: 12) {
            typeCard(
                type: .fleeting,
                icon: "bolt.fill",
                title: "Fleeting",
                subtitle: "Quick capture. Process later.",
                description: "A raw thought, reminder, or fragment. Lives in your inbox until you develop or discard it.",
                color: Moros.ambient
            )
            typeCard(
                type: .literature,
                icon: "book.fill",
                title: "Literature",
                subtitle: "From a source, in your own words.",
                description: "A note about something you read, watched, or heard. Always reference the source. Write in YOUR words.",
                color: Moros.oracle
            )
            typeCard(
                type: .permanent,
                icon: "diamond.fill",
                title: "Permanent",
                subtitle: "A developed idea, ready to connect.",
                description: "A single, atomic idea stated as a claim. Connected to other ideas via Folgezettel. The backbone of your Zettelkasten.",
                color: Moros.verdit
            )
        }
    }

    private func typeCard(type: NoteType, icon: String, title: String, subtitle: String, description: String, color: Color) -> some View {
        Button {
            selectedNoteType = type
            if type == .fleeting {
                currentStep = .titleContent
            } else if type == .literature {
                currentStep = .source
            } else {
                currentStep = .placement
            }
        } label: {
            HStack(alignment: .top, spacing: 16) {
                Image(systemName: icon)
                    .font(.system(size: 28))
                    .foregroundStyle(color)
                    .frame(width: 40)

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(Moros.fontH3)
                        .foregroundStyle(Moros.textMain)
                    Text(subtitle)
                        .font(Moros.fontBody)
                        .foregroundStyle(color)
                    Text(description)
                        .font(Moros.fontSmall)
                        .foregroundStyle(Moros.textDim)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .foregroundStyle(Moros.textDim)
            }
            .padding(16)
            .background(Moros.limit02, in: Rectangle())
            .overlay(Rectangle().stroke(Moros.border, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Step 2a: Placement (Permanent)

    private var placementView: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("FOLGEZETTEL PLACEMENT")
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .foregroundStyle(Moros.textDim)

            placementOptionRow(
                mode: .newRoot,
                icon: "plus.circle",
                title: "New root topic",
                subtitle: "Start a new top-level thread of ideas"
            )
            placementOptionRow(
                mode: .continueFrom,
                icon: "arrow.right",
                title: "Continues from...",
                subtitle: "A sibling idea that follows another note"
            )
            placementOptionRow(
                mode: .branchFrom,
                icon: "arrow.turn.down.right",
                title: "Branches from...",
                subtitle: "A sub-idea that dives deeper into a note"
            )

            if placementMode != .newRoot {
                VStack(alignment: .leading, spacing: 8) {
                    Text("SELECT PARENT NOTE")
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundStyle(Moros.textDim)

                    TextField("Search notes...", text: $parentSearchQuery)
                        .textFieldStyle(.plain)
                        .font(Moros.fontBody)
                        .foregroundStyle(Moros.textMain)
                        .padding(8)
                        .background(Moros.limit02, in: Rectangle())

                    let filtered = filteredParentNotes
                    if filtered.isEmpty {
                        Text("No permanent notes found.")
                            .font(Moros.fontSmall)
                            .foregroundStyle(Moros.textDim)
                            .padding(.vertical, 8)
                    } else {
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 0) {
                                ForEach(filtered.prefix(20), id: \.objectID) { note in
                                    parentNoteRow(note)
                                }
                            }
                        }
                        .frame(maxHeight: 200)
                        .background(Moros.limit02, in: Rectangle())
                        .overlay(Rectangle().stroke(Moros.border, lineWidth: 1))
                    }

                    if let parent = selectedParentNote, let parentId = parent.zettelId {
                        let fz = FolgezettelService(context: context)
                        let previewId = placementMode == .continueFrom
                            ? fz.generateContinuation(of: parentId)
                            : fz.generateBranch(from: parentId)

                        HStack(spacing: 8) {
                            Text("NEW ID:")
                                .font(.system(size: 9, weight: .medium, design: .monospaced))
                                .foregroundStyle(Moros.textDim)
                            Text(previewId)
                                .font(.system(size: 14, weight: .bold, design: .monospaced))
                                .foregroundStyle(Moros.oracle)
                            Text(placementMode == .continueFrom ? "(sibling of \(parentId))" : "(child of \(parentId))")
                                .font(Moros.fontCaption)
                                .foregroundStyle(Moros.textDim)
                        }
                        .padding(10)
                        .background(Moros.oracle.opacity(0.08), in: Rectangle())
                    }
                }
            } else {
                let fz = FolgezettelService(context: context)
                let previewId = fz.generateNextRoot()
                HStack(spacing: 8) {
                    Text("NEW ROOT ID:")
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundStyle(Moros.textDim)
                    Text(previewId)
                        .font(.system(size: 14, weight: .bold, design: .monospaced))
                        .foregroundStyle(Moros.oracle)
                }
                .padding(10)
                .background(Moros.oracle.opacity(0.08), in: Rectangle())
            }
        }
    }

    private func placementOptionRow(mode: PlacementMode, icon: String, title: String, subtitle: String) -> some View {
        Button {
            placementMode = mode
            if mode == .newRoot { selectedParentNote = nil }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 16))
                    .foregroundStyle(placementMode == mode ? Moros.oracle : Moros.textDim)
                    .frame(width: 24)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(Moros.fontBody)
                        .foregroundStyle(Moros.textMain)
                    Text(subtitle)
                        .font(Moros.fontCaption)
                        .foregroundStyle(Moros.textDim)
                }

                Spacer()

                if placementMode == mode {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Moros.oracle)
                }
            }
            .padding(10)
            .background(placementMode == mode ? Moros.oracle.opacity(0.06) : Moros.limit02, in: Rectangle())
            .overlay(Rectangle().stroke(placementMode == mode ? Moros.oracle.opacity(0.3) : Moros.border, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private func parentNoteRow(_ note: NoteEntity) -> some View {
        Button {
            selectedParentNote = note
        } label: {
            HStack(spacing: 8) {
                Text(note.zettelId ?? "?")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(Moros.textDim)
                    .frame(width: 50, alignment: .leading)
                Text(note.title.isEmpty ? "Untitled" : note.title)
                    .font(Moros.fontBody)
                    .foregroundStyle(Moros.textMain)
                    .lineLimit(1)
                Spacer()
                if selectedParentNote?.objectID == note.objectID {
                    Image(systemName: "checkmark")
                        .foregroundStyle(Moros.oracle)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(selectedParentNote?.objectID == note.objectID ? Moros.oracle.opacity(0.08) : .clear)
        }
        .buttonStyle(.plain)
    }

    private var filteredParentNotes: [NoteEntity] {
        if parentSearchQuery.isEmpty {
            return Array(permanentNotes)
        }
        let q = parentSearchQuery.lowercased()
        return permanentNotes.filter { note in
            (note.title.lowercased().contains(q)) ||
            (note.zettelId?.lowercased().contains(q) == true)
        }
    }

    // MARK: - Step 2b: Source (Literature)

    private var sourceView: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("SOURCE")
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .foregroundStyle(Moros.textDim)

            if !sourceService.sources.isEmpty && !showNewSourceForm {
                Text("Select an existing source or add a new one:")
                    .font(Moros.fontSmall)
                    .foregroundStyle(Moros.textSub)

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(sourceService.sources, id: \.id) { source in
                            Button {
                                selectedSource = source
                            } label: {
                                HStack(spacing: 10) {
                                    Image(systemName: source.sourceType.icon)
                                        .foregroundStyle(Moros.textDim)
                                        .frame(width: 20)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(source.title)
                                            .font(Moros.fontBody)
                                            .foregroundStyle(Moros.textMain)
                                        if let author = source.author {
                                            Text(author)
                                                .font(Moros.fontCaption)
                                                .foregroundStyle(Moros.textDim)
                                        }
                                    }
                                    Spacer()
                                    waitingBadge(source.waitingStatus)
                                    if selectedSource?.id == source.id {
                                        Image(systemName: "checkmark")
                                            .foregroundStyle(Moros.oracle)
                                    }
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(selectedSource?.id == source.id ? Moros.oracle.opacity(0.08) : .clear)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .frame(maxHeight: 180)
                .background(Moros.limit02, in: Rectangle())
                .overlay(Rectangle().stroke(Moros.border, lineWidth: 1))
            }

            Button(action: { showNewSourceForm.toggle() }) {
                Label(showNewSourceForm ? "Hide form" : "Add new source", systemImage: showNewSourceForm ? "chevron.up" : "plus.circle")
                    .font(Moros.fontBody)
                    .foregroundStyle(Moros.oracle)
            }
            .buttonStyle(.plain)

            if showNewSourceForm {
                newSourceFormView
            }

            if selectedSource != nil || !newSourceTitle.isEmpty {
                TextField("Page / chapter reference", text: $pageReference)
                    .textFieldStyle(.plain)
                    .font(Moros.fontBody)
                    .foregroundStyle(Moros.textMain)
                    .padding(8)
                    .background(Moros.limit02, in: Rectangle())

                HStack(spacing: 6) {
                    Image(systemName: "info.circle")
                        .foregroundStyle(Moros.oracle)
                    Text("Write in YOUR words, not the author's. Paraphrase the key insight.")
                        .font(Moros.fontCaption)
                        .foregroundStyle(Moros.textSub)
                }
                .padding(8)
                .background(Moros.oracle.opacity(0.06), in: Rectangle())
            }
        }
    }

    private var newSourceFormView: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("Source title (book, article, video...)", text: $newSourceTitle)
                .textFieldStyle(.plain)
                .font(Moros.fontBody)
                .foregroundStyle(Moros.textMain)
                .padding(8)
                .background(Moros.limit02, in: Rectangle())

            TextField("Author (optional)", text: $newSourceAuthor)
                .textFieldStyle(.plain)
                .font(Moros.fontBody)
                .foregroundStyle(Moros.textMain)
                .padding(8)
                .background(Moros.limit02, in: Rectangle())

            Picker("Type", selection: $newSourceType) {
                ForEach(SourceType.allCases) { type in
                    Label(type.label, systemImage: type.icon).tag(type)
                }
            }
            .pickerStyle(.menu)
        }
        .padding(10)
        .background(Moros.limit03, in: Rectangle())
    }

    private func waitingBadge(_ status: Source.WaitingStatus) -> some View {
        Text(status.label.uppercased())
            .font(.system(size: 8, weight: .medium, design: .monospaced))
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(waitingColor(status).opacity(0.15), in: Rectangle())
            .foregroundStyle(waitingColor(status))
    }

    private func waitingColor(_ status: Source.WaitingStatus) -> Color {
        switch status {
        case .notConsumed: Moros.textDim
        case .waiting: Moros.ambient
        case .readyToCard: Moros.verdit
        case .carded: Moros.oracle
        }
    }

    // MARK: - Step 3: Title & Content

    private var titleContentView: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Literature source header
            if selectedNoteType == .literature {
                if let source = selectedSource {
                    HStack(spacing: 8) {
                        Image(systemName: source.sourceType.icon)
                            .foregroundStyle(Moros.oracle)
                        Text(source.title)
                            .font(Moros.fontBody)
                            .foregroundStyle(Moros.textMain)
                        if let author = source.author {
                            Text("by \(author)")
                                .font(Moros.fontCaption)
                                .foregroundStyle(Moros.textDim)
                        }
                        if !pageReference.isEmpty {
                            Text("p. \(pageReference)")
                                .font(Moros.fontMonoCaption)
                                .foregroundStyle(Moros.textDim)
                        }
                    }
                    .padding(8)
                    .background(Moros.oracle.opacity(0.06), in: Rectangle())
                } else if !newSourceTitle.isEmpty {
                    HStack(spacing: 8) {
                        Image(systemName: newSourceType.icon)
                            .foregroundStyle(Moros.oracle)
                        Text(newSourceTitle)
                            .font(Moros.fontBody)
                            .foregroundStyle(Moros.textMain)
                        if !newSourceAuthor.isEmpty {
                            Text("by \(newSourceAuthor)")
                                .font(Moros.fontCaption)
                                .foregroundStyle(Moros.textDim)
                        }
                    }
                    .padding(8)
                    .background(Moros.oracle.opacity(0.06), in: Rectangle())
                }
            }

            // Title
            VStack(alignment: .leading, spacing: 4) {
                if selectedNoteType == .permanent {
                    Text("TITLE (STATE AS A CLAIM)")
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundStyle(Moros.textDim)
                } else {
                    Text("TITLE")
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundStyle(Moros.textDim)
                }

                TextField(
                    selectedNoteType == .permanent
                        ? "Spaced repetition makes memory a choice"
                        : "Title (optional for fleeting)",
                    text: $title
                )
                .textFieldStyle(.plain)
                .font(.system(size: 20, weight: .light))
                .foregroundStyle(Moros.textMain)
                .padding(10)
                .background(Moros.limit02, in: Rectangle())

                if selectedNoteType == .permanent {
                    HStack {
                        let wordCount = title.split(separator: " ").count
                        Text("\(wordCount) words")
                            .font(Moros.fontMonoSmall)
                            .foregroundStyle(wordCount >= 5 ? Moros.verdit : Moros.ambient)
                        if wordCount < 5 && wordCount > 0 {
                            Text("Aim for 5+ words. A claim, not a topic.")
                                .font(Moros.fontCaption)
                                .foregroundStyle(Moros.ambient)
                        }
                    }
                }
            }

            // Content
            VStack(alignment: .leading, spacing: 4) {
                Text("CONTENT")
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundStyle(Moros.textDim)

                TextEditor(text: $content)
                    .font(.system(size: 13, weight: .regular, design: .monospaced))
                    .foregroundStyle(Moros.textMain)
            
                    .padding(10)
                    .background(Moros.limit02, in: Rectangle())
                    .frame(minHeight: 160)

                // Atomicity bar
                atomicityBar
            }

            // Context — why this note exists
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Image(systemName: "brain.filled.head.profile")
                        .font(.system(size: 10))
                        .foregroundStyle(Moros.oracle)
                    Text("CONTEXT")
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundStyle(Moros.textDim)
                    Text("— por que essa nota existe?")
                        .font(.system(size: 10))
                        .foregroundStyle(Moros.textGhost)
                }

                TextField("De onde veio essa ideia? Por que é relevante? Como se conecta ao que você já sabe?", text: $contextNote, axis: .vertical)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(Moros.textSub)
                    .lineLimit(2...4)
                    .textFieldStyle(.plain)
                    .padding(8)
                    .background(Moros.oracle.opacity(0.04), in: Rectangle())
                    .overlay(Rectangle().stroke(Moros.oracle.opacity(0.12), lineWidth: 1))
            }
        }
    }

    private var atomicityBar: some View {
        let wordCount = content.split(separator: " ").filter { !$0.isEmpty }.count

        return HStack(spacing: 8) {
            Text("\(wordCount) words")
                .font(Moros.fontMonoSmall)
                .foregroundStyle(Moros.textDim)

            GeometryReader { geo in
                let maxWidth = geo.size.width
                let ratio = min(Double(wordCount) / 400.0, 1.0)
                let barColor: Color = {
                    if wordCount < 40 { return Moros.ambient }
                    if wordCount <= 400 { return Moros.verdit }
                    return Moros.signal
                }()

                ZStack(alignment: .leading) {
                    Rectangle()
                        .fill(Moros.limit03)
                        .frame(height: 4)
                    Rectangle()
                        .fill(barColor)
                        .frame(width: maxWidth * ratio, height: 4)
                }
            }
            .frame(height: 4)

            Text(selectedNoteType == .permanent || selectedNoteType == .literature ? "40-400 ideal" : "")
                .font(Moros.fontMicro)
                .foregroundStyle(Moros.textDim)
        }
    }

    // MARK: - Step 4: Connect

    private var connectView: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Link to existing notes
            VStack(alignment: .leading, spacing: 8) {
                Text("LINK TO EXISTING NOTES")
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundStyle(Moros.textDim)

                TextField("Search notes to link...", text: $linkSearchQuery)
                    .textFieldStyle(.plain)
                    .font(Moros.fontBody)
                    .foregroundStyle(Moros.textMain)
                    .padding(8)
                    .background(Moros.limit02, in: Rectangle())

                if !linkSearchQuery.isEmpty {
                    let results = searchResults
                    if results.isEmpty {
                        Text("No matching notes.")
                            .font(Moros.fontSmall)
                            .foregroundStyle(Moros.textDim)
                    } else {
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 0) {
                                ForEach(results.prefix(10), id: \.objectID) { note in
                                    linkNoteRow(note)
                                }
                            }
                        }
                        .frame(maxHeight: 150)
                        .background(Moros.limit02, in: Rectangle())
                        .overlay(Rectangle().stroke(Moros.border, lineWidth: 1))
                    }
                }

                // Selected links
                if !selectedLinkNotes.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("LINKED (\(selectedLinkNotes.count))")
                            .font(.system(size: 9, weight: .medium, design: .monospaced))
                            .foregroundStyle(Moros.textDim)

                        ForEach(Array(selectedLinkNotes.enumerated()), id: \.offset) { index, item in
                            HStack(spacing: 8) {
                                Text(item.note.zettelId ?? "?")
                                    .font(Moros.fontMonoSmall)
                                    .foregroundStyle(Moros.textDim)
                                Text(item.note.title.isEmpty ? "Untitled" : item.note.title)
                                    .font(Moros.fontSmall)
                                    .foregroundStyle(Moros.textSub)
                                    .lineLimit(1)
                                Spacer()
                                Picker("", selection: Binding(
                                    get: { selectedLinkNotes[index].type },
                                    set: { selectedLinkNotes[index].type = $0 }
                                )) {
                                    ForEach(LinkType.allCases) { lt in
                                        Text(lt.label).tag(lt)
                                    }
                                }
                                .frame(width: 100)
                                Button {
                                    selectedLinkNotes.remove(at: index)
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundStyle(Moros.textDim)
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Moros.oracle.opacity(0.06), in: Rectangle())
                        }
                    }
                }
            }

            Rectangle().fill(Moros.border).frame(height: 1)

            // Tags
            VStack(alignment: .leading, spacing: 8) {
                Text("TAGS")
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundStyle(Moros.textDim)

                HStack {
                    TextField("Add tag...", text: $tagInput)
                        .textFieldStyle(.plain)
                        .font(Moros.fontBody)
                        .foregroundStyle(Moros.textMain)
                        .padding(8)
                        .background(Moros.limit02, in: Rectangle())
                        .onSubmit { addTag() }
                    Button("Add") { addTag() }
                        .disabled(tagInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }

                if !selectedTagNames.isEmpty {
                    HStack(spacing: 4) {
                        ForEach(selectedTagNames, id: \.self) { tag in
                            HStack(spacing: 4) {
                                Text("#\(tag)")
                                    .font(Moros.fontCaption)
                                Button {
                                    selectedTagNames.removeAll { $0 == tag }
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.system(size: 9))
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(Moros.oracle.opacity(0.1), in: Rectangle())
                            .foregroundStyle(Moros.oracle)
                        }
                    }
                }

                if !allTags.isEmpty {
                    Text("Existing:")
                        .font(Moros.fontMicro)
                        .foregroundStyle(Moros.textDim)
                    HStack(spacing: 4) {
                        ForEach(allTags.prefix(8), id: \.objectID) { tag in
                            if let name = tag.name, !selectedTagNames.contains(name) {
                                Button {
                                    selectedTagNames.append(name)
                                } label: {
                                    Text("#\(name)")
                                        .font(Moros.fontCaption)
                                        .padding(.horizontal, 5)
                                        .padding(.vertical, 2)
                                        .background(Moros.limit03, in: Rectangle())
                                        .foregroundStyle(Moros.textSub)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
        }
    }

    private var searchResults: [NoteEntity] {
        let q = linkSearchQuery.lowercased()
        return allNotes.filter { note in
            (note.title.lowercased().contains(q)) ||
            (note.zettelId?.lowercased().contains(q) == true)
        }
    }

    private func linkNoteRow(_ note: NoteEntity) -> some View {
        let isLinked = selectedLinkNotes.contains(where: { $0.note.objectID == note.objectID })
        return Button {
            if isLinked {
                selectedLinkNotes.removeAll { $0.note.objectID == note.objectID }
            } else {
                selectedLinkNotes.append((note: note, type: .reference))
            }
        } label: {
            HStack(spacing: 8) {
                Text(note.zettelId ?? "?")
                    .font(Moros.fontMonoSmall)
                    .foregroundStyle(Moros.textDim)
                    .frame(width: 50, alignment: .leading)
                Image(systemName: note.noteType.icon)
                    .font(.system(size: 10))
                    .foregroundStyle(Moros.textDim)
                Text(note.title.isEmpty ? "Untitled" : note.title)
                    .font(Moros.fontBody)
                    .foregroundStyle(Moros.textMain)
                    .lineLimit(1)
                Spacer()
                if isLinked {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Moros.oracle)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(isLinked ? Moros.oracle.opacity(0.06) : .clear)
        }
        .buttonStyle(.plain)
    }

    private func addTag() {
        let name = tagInput.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !name.isEmpty, !selectedTagNames.contains(name) else { return }
        selectedTagNames.append(name)
        tagInput = ""
    }

    // MARK: - Footer

    private var sheetFooter: some View {
        HStack {
            if currentStep != .chooseType {
                Button("Back") {
                    goBack()
                }
                .foregroundStyle(Moros.textSub)
            }

            Spacer()

            if currentStep == .titleContent && selectedNoteType == .fleeting {
                Button("Capture") {
                    createNote()
                }
                .keyboardShortcut(.return, modifiers: .command)
                .buttonStyle(.borderedProminent)
                .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            } else if isLastStep {
                Button("Create Zettel") {
                    createNote()
                }
                .keyboardShortcut(.return, modifiers: .command)
                .buttonStyle(.borderedProminent)
                .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            } else if currentStep != .chooseType {
                Button("Next") {
                    goNext()
                }
                .keyboardShortcut(.return, modifiers: .command)
                .buttonStyle(.borderedProminent)
                .disabled(!canAdvance)
            }
        }
        .padding()
    }

    private var isLastStep: Bool {
        let steps = stepsForCurrentType
        return currentStep == steps.last
    }

    private var canAdvance: Bool {
        switch currentStep {
        case .chooseType: return true
        case .placement: return placementMode == .newRoot || selectedParentNote != nil
        case .source: return selectedSource != nil || !newSourceTitle.isEmpty
        case .titleContent: return !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .connect: return true
        }
    }

    // MARK: - Navigation

    private func goNext() {
        let steps = stepsForCurrentType
        guard let idx = steps.firstIndex(of: currentStep), idx < steps.count - 1 else { return }
        currentStep = steps[idx + 1]
    }

    private func goBack() {
        let steps = stepsForCurrentType
        guard let idx = steps.firstIndex(of: currentStep), idx > 0 else { return }
        currentStep = steps[idx - 1]
    }

    // MARK: - Create Note

    private func createNote() {
        let noteService = NoteService(context: context)
        let fzService = FolgezettelService(context: context)
        let tagService = TagService(context: context)
        let linkService = LinkService(context: context)

        let noteTitle = title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? (selectedNoteType == .fleeting ? "Quick Capture" : "Untitled")
            : title.trimmingCharacters(in: .whitespacesAndNewlines)
        let noteContent = content.trimmingCharacters(in: .whitespacesAndNewlines)

        let note = noteService.createNote(
            title: noteTitle,
            content: noteContent,
            paraCategory: selectedNoteType == .fleeting ? .inbox : .resource
        )

        // Set note type and context
        note.noteType = selectedNoteType
        let ctx = contextNote.trimmingCharacters(in: .whitespacesAndNewlines)
        if !ctx.isEmpty { note.contextNote = ctx }

        // Folgezettel ID for permanent notes
        if selectedNoteType == .permanent {
            switch placementMode {
            case .newRoot:
                note.zettelId = fzService.generateNextRoot()
            case .continueFrom:
                if let parent = selectedParentNote, let parentId = parent.zettelId {
                    note.zettelId = fzService.generateContinuation(of: parentId)
                } else {
                    note.zettelId = fzService.generateNextRoot()
                }
            case .branchFrom:
                if let parent = selectedParentNote, let parentId = parent.zettelId {
                    note.zettelId = fzService.generateBranch(from: parentId)
                } else {
                    note.zettelId = fzService.generateNextRoot()
                }
            }

            note.codeStage = .organized

            // Link to parent
            if placementMode != .newRoot, let parent = selectedParentNote {
                linkService.createLink(from: note, to: parent, type: .extends)
            }
        }

        // Source for literature notes
        if selectedNoteType == .literature {
            if let source = selectedSource {
                note.sourceTitle = source.title
                note.sourceURL = source.url
                if let noteId = note.id {
                    sourceService.linkNote(noteId: noteId, to: source.id)
                }
            } else if !newSourceTitle.isEmpty {
                let source = sourceService.addSource(
                    title: newSourceTitle,
                    author: newSourceAuthor.isEmpty ? nil : newSourceAuthor,
                    sourceType: newSourceType,
                    dateConsumed: Date()
                )
                note.sourceTitle = source.title
                if let noteId = note.id {
                    sourceService.linkNote(noteId: noteId, to: source.id)
                }
            }
        }

        // Tags
        for tagName in selectedTagNames {
            let tag = tagService.findOrCreate(name: tagName)
            note.mutableSetValue(forKey: "tags").add(tag)
        }

        // Links
        for linkItem in selectedLinkNotes {
            linkService.createLink(from: note, to: linkItem.note, type: linkItem.type)
        }

        try? context.save()

        appState.selectedNote = note
        dismiss()
    }

    // MARK: - Types

    enum CreationStep: Int, Hashable {
        case chooseType = 0
        case placement = 1
        case source = 2
        case titleContent = 3
        case connect = 4
    }

    enum PlacementMode: Hashable {
        case newRoot
        case continueFrom
        case branchFrom
    }
}
