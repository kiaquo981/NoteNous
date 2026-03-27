import SwiftUI
import CoreData

/// Sheet shown when promoting a fleeting note to permanent.
/// Shows atomicity report, validates quality, and handles Folgezettel placement.
struct PromotionSheet: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.managedObjectContext) private var context
    @Environment(\.dismiss) private var dismiss

    @ObservedObject var note: NoteEntity

    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \NoteEntity.updatedAt, ascending: false)],
        predicate: NSCompoundPredicate(andPredicateWithSubpredicates: [
            NSPredicate(format: "noteTypeRaw == %d", NoteType.permanent.rawValue),
            NSPredicate(format: "isArchived == NO")
        ])
    ) private var permanentNotes: FetchedResults<NoteEntity>

    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \TagEntity.usageCount, ascending: false)]
    ) private var allTags: FetchedResults<TagEntity>

    @State private var placementMode: PlacementMode = .newRoot
    @State private var selectedParentNote: NoteEntity?
    @State private var tagInput: String = ""
    @State private var selectedTags: Set<NSManagedObjectID> = []
    @State private var sourceTitle: String = ""
    @State private var sourceURL: String = ""

    private var report: AtomicityReport {
        let service = AtomicNoteService(context: context)
        return service.analyze(note: note)
    }

    private var hasCriticalIssues: Bool {
        report.issues.contains(where: { $0.isCritical })
    }

    private var isLiteratureNote: Bool {
        note.noteType == .literature
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            header

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Atomicity Report
                    atomicitySection

                    Divider()

                    // Folgezettel Placement
                    placementSection

                    Divider()

                    // Tag Assignment
                    tagSection

                    // Source (for literature notes)
                    if isLiteratureNote {
                        Divider()
                        sourceSection
                    }
                }
                .padding()
            }

            Divider()

            // Footer with promote button
            footer
        }
        .frame(minWidth: 500, minHeight: 600)
        .onAppear {
            selectedTags = Set(note.tagsArray.map(\.objectID))
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            VStack(alignment: .leading) {
                Text(isLiteratureNote ? "Convert to Literature Note" : "Promote to Permanent")
                    .font(.title2.weight(.semibold))
                Text(note.title.isEmpty ? "Untitled" : note.title)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Cancel") {
                dismiss()
            }
            .keyboardShortcut(.cancelAction)
        }
        .padding()
    }

    // MARK: - Atomicity Section

    private var atomicitySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Atomicity Check", systemImage: "atom")
                .font(.headline)

            HStack(spacing: 12) {
                AtomicityIndicator(report: report, size: .large)

                VStack(alignment: .leading, spacing: 4) {
                    Text("\(report.wordCount) words")
                        .font(.callout)
                    Text("\(report.headingCount) headings, \(report.paragraphCount) paragraphs")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("\(report.outgoingLinkCount) outgoing links")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if !report.issues.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(report.issues.enumerated()), id: \.offset) { _, issue in
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: issue.isCritical ? "exclamationmark.triangle.fill" : "info.circle.fill")
                                .foregroundStyle(issue.isCritical ? .red : .orange)
                                .font(.caption)
                            Text(issue.description)
                                .font(.caption)
                                .foregroundStyle(issue.isCritical ? .red : .secondary)
                        }
                    }
                }
                .padding(10)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
            }
        }
    }

    // MARK: - Placement Section

    private var placementSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Folgezettel Placement", systemImage: "point.topleft.down.to.point.bottomright.curvepath")
                .font(.headline)

            Text("Where does this idea belong in your Zettelkasten?")
                .font(.caption)
                .foregroundStyle(.secondary)

            Picker("Placement", selection: $placementMode) {
                Text("New root topic").tag(PlacementMode.newRoot)
                Text("Continue from...").tag(PlacementMode.continueFrom)
                Text("Branch from...").tag(PlacementMode.branchFrom)
            }
            .pickerStyle(.segmented)

            if placementMode != .newRoot {
                parentNotePicker
            }
        }
    }

    private var parentNotePicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Select parent note:")
                .font(.caption)
                .foregroundStyle(.secondary)

            List(selection: $selectedParentNote) {
                ForEach(permanentNotes.prefix(20), id: \.objectID) { pNote in
                    HStack {
                        Text(pNote.zettelId ?? "?")
                            .font(.caption.monospaced())
                            .frame(width: 60, alignment: .leading)
                        Text(pNote.title.isEmpty ? "Untitled" : pNote.title)
                            .font(.callout)
                            .lineLimit(1)
                    }
                    .tag(pNote)
                }
            }
            .listStyle(.bordered)
            .frame(height: 150)
        }
    }

    // MARK: - Tag Section

    private var tagSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Tags", systemImage: "tag")
                .font(.headline)

            HStack {
                TextField("Add tag...", text: $tagInput)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit {
                        addTag()
                    }
                Button("Add") {
                    addTag()
                }
                .disabled(tagInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            if !selectedTags.isEmpty {
                FlowLayout(spacing: 4) {
                    ForEach(allTags.filter { selectedTags.contains($0.objectID) }, id: \.objectID) { tag in
                        HStack(spacing: 4) {
                            Text("#\(tag.name ?? "")")
                                .font(.caption)
                            Button {
                                selectedTags.remove(tag.objectID)
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.caption2)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.blue.opacity(0.1), in: Capsule())
                    }
                }
            }

            if !allTags.isEmpty {
                Text("Existing tags:")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                FlowLayout(spacing: 4) {
                    ForEach(allTags.prefix(10), id: \.objectID) { tag in
                        Button {
                            if selectedTags.contains(tag.objectID) {
                                selectedTags.remove(tag.objectID)
                            } else {
                                selectedTags.insert(tag.objectID)
                            }
                        } label: {
                            Text("#\(tag.name ?? "")")
                                .font(.caption)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(
                                    selectedTags.contains(tag.objectID) ? Color.blue.opacity(0.2) : Color.gray.opacity(0.15),
                                    in: Capsule()
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    // MARK: - Source Section

    private var sourceSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Source", systemImage: "book.closed")
                .font(.headline)

            TextField("Source title (book, article, etc.)", text: $sourceTitle)
                .textFieldStyle(.roundedBorder)

            TextField("Source URL (optional)", text: $sourceURL)
                .textFieldStyle(.roundedBorder)
        }
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            if hasCriticalIssues {
                Label("Fix critical issues before promoting", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            Spacer()

            Button("Promote") {
                promoteNote()
            }
            .keyboardShortcut(.defaultAction)
            .buttonStyle(.borderedProminent)
            .disabled(hasCriticalIssues)
        }
        .padding()
    }

    // MARK: - Actions

    private func promoteNote() {
        let folgezettelService = FolgezettelService(context: context)

        // Assign Folgezettel ID
        let newZettelId: String
        switch placementMode {
        case .newRoot:
            newZettelId = folgezettelService.generateNextRoot()
        case .continueFrom:
            if let parent = selectedParentNote, let parentId = parent.zettelId {
                newZettelId = folgezettelService.generateContinuation(of: parentId)
            } else {
                newZettelId = folgezettelService.generateNextRoot()
            }
        case .branchFrom:
            if let parent = selectedParentNote, let parentId = parent.zettelId {
                newZettelId = folgezettelService.generateBranch(from: parentId)
            } else {
                newZettelId = folgezettelService.generateNextRoot()
            }
        }

        // Update note type
        if !isLiteratureNote {
            note.noteTypeRaw = NoteType.permanent.rawValue
        }

        note.zettelId = newZettelId
        note.codeStageRaw = CODEStage.organized.rawValue
        note.updatedAt = Date()

        // Apply source info for literature notes
        if isLiteratureNote {
            if !sourceTitle.isEmpty { note.sourceTitle = sourceTitle }
            if !sourceURL.isEmpty { note.sourceURL = sourceURL }
        }

        // Apply tags
        let currentTags = note.tagsArray
        for tag in currentTags {
            note.mutableSetValue(forKey: "tags").remove(tag)
        }
        for tagObjectID in selectedTags {
            if let tag = try? context.existingObject(with: tagObjectID) as? TagEntity {
                note.mutableSetValue(forKey: "tags").add(tag)
            }
        }

        // Create link to parent if applicable
        if placementMode != .newRoot, let parent = selectedParentNote {
            let linkService = LinkService(context: context)
            linkService.createLink(from: note, to: parent, type: .extends)
        }

        try? context.save()

        dismiss()
    }

    private func addTag() {
        let name = tagInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }

        let tagService = TagService(context: context)
        if let existing = allTags.first(where: { $0.name?.lowercased() == name.lowercased() }) {
            selectedTags.insert(existing.objectID)
        } else {
            let newTag = tagService.findOrCreate(name: name)
            selectedTags.insert(newTag.objectID)
        }
        tagInput = ""
    }

    // MARK: - Types

    enum PlacementMode: Hashable {
        case newRoot
        case continueFrom
        case branchFrom
    }
}

// MARK: - Flow Layout (simple horizontal wrapping)

struct FlowLayout: Layout {
    var spacing: CGFloat = 4

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = arrangeSubviews(proposal: proposal, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrangeSubviews(proposal: proposal, subviews: subviews)
        for (index, position) in result.positions.enumerated() {
            subviews[index].place(at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y), proposal: .unspecified)
        }
    }

    private func arrangeSubviews(proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, positions: [CGPoint]) {
        let maxWidth = proposal.width ?? .infinity
        var positions: [CGPoint] = []
        var currentX: CGFloat = 0
        var currentY: CGFloat = 0
        var lineHeight: CGFloat = 0
        var maxX: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if currentX + size.width > maxWidth && currentX > 0 {
                currentX = 0
                currentY += lineHeight + spacing
                lineHeight = 0
            }
            positions.append(CGPoint(x: currentX, y: currentY))
            lineHeight = max(lineHeight, size.height)
            currentX += size.width + spacing
            maxX = max(maxX, currentX)
        }

        return (CGSize(width: maxX, height: currentY + lineHeight), positions)
    }
}
