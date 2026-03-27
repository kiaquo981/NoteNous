import SwiftUI
import CoreData
import os.log

struct DeskCanvasView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.managedObjectContext) private var viewContext

    @State private var canvasState = DeskCanvasState()
    @State private var sectionStore = DeskSectionStore()
    @State private var showSectionPanel: Bool = false
    @State private var editingNoteId: UUID?
    @State private var editingTitle: String = ""
    @State private var showColorPopoverForNote: UUID?
    @State private var selectedColorHex: String?
    @State private var contextMenuPosition: CGPoint = .zero
    @State private var viewportSize: CGSize = .zero
    @State private var hasPerformedInitialLayout: Bool = false

    private let logger = Logger(subsystem: "com.notenous.app", category: "DeskCanvas")

    // MARK: - Fetch request

    @FetchRequest(
        sortDescriptors: [
            NSSortDescriptor(keyPath: \NoteEntity.isPinned, ascending: false),
            NSSortDescriptor(keyPath: \NoteEntity.updatedAt, ascending: false)
        ],
        predicate: NSPredicate(format: "isArchived == NO"),
        animation: .default
    )
    private var allNotes: FetchedResults<NoteEntity>

    // MARK: - Filtered notes

    private var visibleNotes: [NoteEntity] {
        let notes = Array(allNotes)
        switch canvasState.filterMode {
        case .none:
            return notes
        case .para:
            guard let filterValue = canvasState.filterValue,
                  let raw = Int16(filterValue),
                  let para = PARACategory(rawValue: raw)
            else { return notes }
            return notes.filter { $0.paraCategory == para }
        case .noteType:
            guard let filterValue = canvasState.filterValue,
                  let raw = Int16(filterValue),
                  let type = NoteType(rawValue: raw)
            else { return notes }
            return notes.filter { $0.noteType == type }
        case .color:
            guard let filterValue = canvasState.filterValue else { return notes }
            return notes.filter { $0.colorHex == filterValue }
        }
    }

    /// Notes that pass visibility culling (within viewport bounds).
    private var culledNotes: [NoteEntity] {
        guard viewportSize.width > 0 else { return visibleNotes }
        return visibleNotes.filter { canvasState.isVisible(note: $0, viewportSize: viewportSize) }
    }

    // MARK: - Links

    private var activeLinks: [NoteLinkEntity] {
        guard canvasState.showConnections else { return [] }
        let noteSet = Set(visibleNotes.compactMap(\.id))
        var links: [NoteLinkEntity] = []
        for note in visibleNotes {
            for link in note.outgoingLinksArray {
                guard let targetId = link.targetNote?.id, noteSet.contains(targetId) else { continue }
                links.append(link)
            }
        }
        return links
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            CanvasToolbar(
                canvasState: canvasState,
                sectionStore: sectionStore,
                selectedCount: canvasState.selectedNoteIds.count,
                totalCount: visibleNotes.count,
                onAddNote: addNoteAtViewportCenter,
                onAutoLayout: performAutoLayout,
                onZoomToFit: { canvasState.zoomToFit(notes: visibleNotes, in: viewportSize) },
                onBulkColorChange: bulkChangeColor,
                onBulkPARAChange: bulkChangePARA,
                onBulkDelete: bulkDelete,
                onToggleSectionPanel: { showSectionPanel.toggle() }
            )

            HStack(spacing: 0) {
                canvasContent
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                if showSectionPanel {
                    Divider()
                    DeskSectionListPanel(
                        sectionStore: sectionStore,
                        notes: Array(allNotes),
                        onSelectSection: { section in
                            // Pan to section
                            canvasState.viewportOffset = CGPoint(
                                x: -section.origin.x * canvasState.zoomLevel + viewportSize.width / 2,
                                y: -section.origin.y * canvasState.zoomLevel + viewportSize.height / 2
                            )
                        }
                    )
                }
            }
        }
        .deskKeyboardShortcuts(
            onDelete: bulkDelete,
            onSelectAll: { canvasState.selectAll(visibleNotes.compactMap(\.id)) },
            onCreateSection: { _ = sectionStore.addSection(at: canvasState.screenToCanvas(CGPoint(x: viewportSize.width / 2, y: viewportSize.height / 2))) },
            onToggleCardMode: cycleCardMode,
            onZoomIn: { canvasState.zoom(by: 1.25, anchor: CGPoint(x: viewportSize.width / 2, y: viewportSize.height / 2)) },
            onZoomOut: { canvasState.zoom(by: 0.8, anchor: CGPoint(x: viewportSize.width / 2, y: viewportSize.height / 2)) },
            onZoomToFit: { canvasState.zoomToFit(notes: visibleNotes, in: viewportSize) },
            onEscape: {
                canvasState.clearSelection()
                canvasState.isCreatingLink = false
                editingNoteId = nil
            }
        )
        .onAppear(perform: initialLayout)
    }

    // MARK: - Canvas content

    private var canvasContent: some View {
        GeometryReader { geometry in
            ZStack {
                // Background + pan gesture
                canvasBackground
                    .gesture(panGesture)
                    .gesture(rubberBandGesture)
                    .onScrollGesture { value in
                        let anchor = CGPoint(x: geometry.size.width / 2, y: geometry.size.height / 2)
                        let factor: CGFloat = value > 0 ? 0.92 : 1.08
                        canvasState.zoom(by: factor, anchor: anchor)
                    }
                    .contextMenu {
                        DeskCanvasContextMenu(
                            canvasPosition: contextMenuPosition,
                            onNewNote: addNoteAt,
                            onPaste: pasteNote,
                            onSelectAll: { canvasState.selectAll(visibleNotes.compactMap(\.id)) },
                            onAutoLayout: { performAutoLayout(.grid) },
                            onAddSection: { pos in _ = sectionStore.addSection(at: pos) }
                        )
                    }

                // Canvas transform group
                ZStack {
                    // Grid overlay (when snap-to-grid is on)
                    if canvasState.snapToGrid {
                        gridOverlay(size: geometry.size)
                    }

                    // Sections (behind cards)
                    ForEach(sectionStore.sections) { section in
                        DeskSectionView(
                            section: section,
                            zoomLevel: canvasState.zoomLevel,
                            isEditing: sectionStore.editingSectionId == section.id,
                            noteCount: section.noteIds.count,
                            onTitleChanged: { section.title = $0 },
                            onDragChanged: { value in
                                let delta = CGSize(
                                    width: value.translation.width / canvasState.zoomLevel,
                                    height: value.translation.height / canvasState.zoomLevel
                                )
                                section.origin = CGPoint(
                                    x: section.origin.x + delta.width,
                                    y: section.origin.y + delta.height
                                )
                            },
                            onDragEnded: { _ in },
                            onDelete: { sectionStore.removeSection(section.id) }
                        )
                        .position(
                            x: section.origin.x * canvasState.zoomLevel + canvasState.viewportOffset.x + section.size.width / 2,
                            y: section.origin.y * canvasState.zoomLevel + canvasState.viewportOffset.y + section.size.height / 2
                        )
                    }

                    // Connection lines
                    ForEach(activeLinks, id: \.objectID) { link in
                        if let sourceNote = link.sourceNote,
                           let targetNote = link.targetNote {
                            DeskConnectionLine(
                                link: link,
                                sourceCenter: cardCenter(for: sourceNote),
                                targetCenter: cardCenter(for: targetNote),
                                zoomLevel: canvasState.zoomLevel
                            )
                        }
                    }

                    // Link creation in-progress line
                    if canvasState.isCreatingLink, let sourceId = canvasState.linkSourceNoteId,
                       let sourceNote = visibleNotes.first(where: { $0.id == sourceId }) {
                        DeskLinkCreationLine(
                            start: cardCenter(for: sourceNote),
                            end: canvasState.linkDragEnd,
                            zoomLevel: canvasState.zoomLevel
                        )
                    }

                    // Note cards (frustum culled)
                    ForEach(culledNotes, id: \.objectID) { note in
                        noteCardView(for: note)
                    }

                    // Rubber-band selection rectangle
                    if canvasState.isRubberBandSelecting {
                        Rectangle()
                            .strokeBorder(Color.accentColor, lineWidth: 1)
                            .background(Color.accentColor.opacity(0.08))
                            .frame(
                                width: canvasState.rubberBandRect.width,
                                height: canvasState.rubberBandRect.height
                            )
                            .position(
                                x: canvasState.rubberBandRect.midX,
                                y: canvasState.rubberBandRect.midY
                            )
                    }
                }
            }
            .clipped()
            .onAppear {
                viewportSize = geometry.size
            }
            .onChange(of: geometry.size) { _, newSize in
                viewportSize = newSize
            }
        }
    }

    // MARK: - Card view

    private func noteCardView(for note: NoteEntity) -> some View {
        let noteId = note.id ?? UUID()
        let isSelected = canvasState.selectedNoteIds.contains(noteId)
        let screenPos = canvasState.canvasToScreen(CGPoint(x: note.positionX, y: note.positionY))
        let dragApplied = canvasState.isDragging && canvasState.draggedNoteIds.contains(noteId)

        let cardWidth: CGFloat = cardSize(for: canvasState.cardDisplayMode).width
        let cardHeight: CGFloat = cardSize(for: canvasState.cardDisplayMode).height

        return DeskNoteCard(
            note: note,
            displayMode: canvasState.cardDisplayMode,
            isSelected: isSelected,
            zoomLevel: canvasState.zoomLevel,
            onTap: { shiftHeld in
                canvasState.toggleSelection(noteId, shiftHeld: shiftHeld)
                appState.selectedNote = note
            },
            onDragChanged: { value in
                if !canvasState.isDragging {
                    canvasState.isDragging = true
                    // If dragging an unselected note, select only it
                    if !canvasState.selectedNoteIds.contains(noteId) {
                        canvasState.selectedNoteIds = [noteId]
                    }
                    canvasState.draggedNoteIds = canvasState.selectedNoteIds
                }
                canvasState.dragOffset = value.translation
            },
            onDragEnded: { value in
                // Apply position change to all dragged notes
                let dx = Double(value.translation.width / canvasState.zoomLevel)
                let dy = Double(value.translation.height / canvasState.zoomLevel)
                for draggedId in canvasState.draggedNoteIds {
                    if let draggedNote = visibleNotes.first(where: { $0.id == draggedId }) {
                        var newPos = CGPoint(
                            x: draggedNote.positionX + dx,
                            y: draggedNote.positionY + dy
                        )
                        newPos = canvasState.snapToGridPoint(newPos)
                        draggedNote.positionX = Double(newPos.x)
                        draggedNote.positionY = Double(newPos.y)

                        // Check if dropped into a section
                        for section in sectionStore.sections {
                            let sectionRect = CGRect(origin: section.origin, size: section.size)
                            if sectionRect.contains(newPos) {
                                sectionStore.assignNote(draggedId, to: section.id)
                            }
                        }
                    }
                }
                try? viewContext.save()
                canvasState.isDragging = false
                canvasState.dragOffset = .zero
                canvasState.draggedNoteIds.removeAll()
            }
        )
        .scaleEffect(canvasState.zoomLevel)
        .offset(
            x: dragApplied ? canvasState.dragOffset.width : 0,
            y: dragApplied ? canvasState.dragOffset.height : 0
        )
        .position(
            x: screenPos.x + cardWidth * canvasState.zoomLevel / 2,
            y: screenPos.y + cardHeight * canvasState.zoomLevel / 2
        )
        .contextMenu {
            DeskCardContextMenu(
                note: note,
                onEdit: {
                    editingNoteId = noteId
                    editingTitle = note.title
                },
                onOpenInEditor: {
                    appState.selectedNote = note
                    appState.selectedView = .stack
                },
                onLinkTo: {
                    canvasState.isCreatingLink = true
                    canvasState.linkSourceNoteId = noteId
                },
                onChangeColor: {
                    showColorPopoverForNote = noteId
                },
                onChangePARA: { para in
                    note.paraCategory = para
                    note.updatedAt = Date()
                    try? viewContext.save()
                },
                onTogglePin: {
                    note.isPinned.toggle()
                    note.updatedAt = Date()
                    try? viewContext.save()
                },
                onArchive: {
                    note.isArchived = true
                    note.paraCategory = .archive
                    note.archivedAt = Date()
                    note.updatedAt = Date()
                    try? viewContext.save()
                },
                onDelete: {
                    viewContext.delete(note)
                    try? viewContext.save()
                }
            )
        }
    }

    // MARK: - Background

    private var canvasBackground: some View {
        Color(nsColor: .controlBackgroundColor)
            .ignoresSafeArea()
    }

    // MARK: - Grid overlay

    private func gridOverlay(size: CGSize) -> some View {
        Canvas { context, canvasSize in
            let gridSpacing = canvasState.gridSize * canvasState.zoomLevel
            guard gridSpacing > 4 else { return } // Skip if too dense

            let offsetX = canvasState.viewportOffset.x.truncatingRemainder(dividingBy: gridSpacing)
            let offsetY = canvasState.viewportOffset.y.truncatingRemainder(dividingBy: gridSpacing)

            var path = Path()

            // Vertical lines
            var x = offsetX
            while x < canvasSize.width {
                path.move(to: CGPoint(x: x, y: 0))
                path.addLine(to: CGPoint(x: x, y: canvasSize.height))
                x += gridSpacing
            }

            // Horizontal lines
            var y = offsetY
            while y < canvasSize.height {
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: canvasSize.width, y: y))
                y += gridSpacing
            }

            context.stroke(path, with: .color(.gray.opacity(0.1)), lineWidth: 0.5)
        }
        .allowsHitTesting(false)
    }

    // MARK: - Gestures

    private var panGesture: some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { value in
                canvasState.viewportOffset = CGPoint(
                    x: canvasState.viewportOffset.x + value.translation.width,
                    y: canvasState.viewportOffset.y + value.translation.height
                )
            }
    }

    private var rubberBandGesture: some Gesture {
        DragGesture(minimumDistance: 10)
            .modifiers(.shift)
            .onChanged { value in
                if !canvasState.isRubberBandSelecting {
                    canvasState.isRubberBandSelecting = true
                    canvasState.rubberBandOrigin = value.startLocation
                }
                canvasState.rubberBandCurrent = value.location
                canvasState.selectedNoteIds = canvasState.notesInRubberBand(
                    visibleNotes,
                    cardSize: cardSize(for: canvasState.cardDisplayMode)
                )
            }
            .onEnded { _ in
                canvasState.isRubberBandSelecting = false
            }
    }

    // MARK: - Helpers

    private func cardCenter(for note: NoteEntity) -> CGPoint {
        let size = cardSize(for: canvasState.cardDisplayMode)
        let screen = canvasState.canvasToScreen(CGPoint(x: note.positionX, y: note.positionY))
        return CGPoint(
            x: screen.x + size.width * canvasState.zoomLevel / 2,
            y: screen.y + size.height * canvasState.zoomLevel / 2
        )
    }

    private func cardSize(for mode: DeskCanvasState.CardDisplayMode) -> CGSize {
        switch mode {
        case .compact: CGSize(width: 200, height: 60)
        case .normal: CGSize(width: 200, height: 140)
        case .expanded: CGSize(width: 260, height: 220)
        }
    }

    // MARK: - Actions

    private func initialLayout() {
        guard !hasPerformedInitialLayout else { return }
        hasPerformedInitialLayout = true

        // Auto-layout notes that still have the default (0,0) position
        let unpositioned = allNotes.filter { $0.positionX == 0 && $0.positionY == 0 }
        if !unpositioned.isEmpty {
            canvasState.layoutGrid(notes: Array(unpositioned), context: viewContext)
        }

        // Fit all into view after a short delay to allow geometry reader
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            if viewportSize.width > 0 {
                canvasState.zoomToFit(notes: Array(allNotes), in: viewportSize)
            }
        }
    }

    private func addNoteAtViewportCenter() {
        let centerCanvas = canvasState.screenToCanvas(
            CGPoint(x: viewportSize.width / 2, y: viewportSize.height / 2)
        )
        addNoteAt(centerCanvas)
    }

    private func addNoteAt(_ canvasPoint: CGPoint) {
        let snapped = canvasState.snapToGridPoint(canvasPoint)
        let noteService = NoteService(context: viewContext)
        let note = noteService.createNote(title: "New Note")
        note.positionX = Double(snapped.x)
        note.positionY = Double(snapped.y)
        try? viewContext.save()
        canvasState.selectedNoteIds = [note.id ?? UUID()]
        appState.selectedNote = note
    }

    private func pasteNote() {
        guard let content = NSPasteboard.general.string(forType: .string), !content.isEmpty else { return }
        let centerCanvas = canvasState.screenToCanvas(
            CGPoint(x: viewportSize.width / 2, y: viewportSize.height / 2)
        )
        let snapped = canvasState.snapToGridPoint(centerCanvas)
        let noteService = NoteService(context: viewContext)
        let firstLine = content.components(separatedBy: .newlines).first ?? content
        let title = String(firstLine.prefix(80))
        let note = noteService.createNote(title: title, content: content)
        note.positionX = Double(snapped.x)
        note.positionY = Double(snapped.y)
        try? viewContext.save()
    }

    private func performAutoLayout(_ mode: CanvasToolbar.AutoLayoutMode) {
        let notes = Array(visibleNotes)
        switch mode {
        case .grid:
            canvasState.layoutGrid(notes: notes, context: viewContext)
        case .byPARA:
            canvasState.layoutByPARA(notes: notes, context: viewContext)
        case .byTag:
            canvasState.layoutByTag(notes: notes, context: viewContext)
        }
        canvasState.zoomToFit(notes: notes, in: viewportSize)
    }

    private func cycleCardMode() {
        let modes = DeskCanvasState.CardDisplayMode.allCases
        guard let currentIndex = modes.firstIndex(of: canvasState.cardDisplayMode) else { return }
        let nextIndex = (currentIndex + 1) % modes.count
        canvasState.cardDisplayMode = modes[nextIndex]
    }

    private func bulkChangeColor(_ hex: String?) {
        for noteId in canvasState.selectedNoteIds {
            if let note = visibleNotes.first(where: { $0.id == noteId }) {
                note.colorHex = hex
                note.updatedAt = Date()
            }
        }
        try? viewContext.save()
    }

    private func bulkChangePARA(_ para: PARACategory) {
        for noteId in canvasState.selectedNoteIds {
            if let note = visibleNotes.first(where: { $0.id == noteId }) {
                note.paraCategory = para
                note.updatedAt = Date()
            }
        }
        try? viewContext.save()
    }

    private func bulkDelete() {
        for noteId in canvasState.selectedNoteIds {
            if let note = visibleNotes.first(where: { $0.id == noteId }) {
                viewContext.delete(note)
            }
        }
        canvasState.clearSelection()
        try? viewContext.save()
    }
}

// MARK: - Scroll gesture modifier

private struct ScrollGestureModifier: ViewModifier {
    let action: (CGFloat) -> Void

    func body(content: Content) -> some View {
        content
            .onContinuousHover { phase in
                // Hover tracking for scroll anchor (no-op, just enables the view for events)
            }
            .background(
                ScrollGestureRepresentable(action: action)
            )
    }
}

private struct ScrollGestureRepresentable: NSViewRepresentable {
    let action: (CGFloat) -> Void

    func makeNSView(context: Context) -> ScrollCaptureView {
        let view = ScrollCaptureView()
        view.onScroll = action
        return view
    }

    func updateNSView(_ nsView: ScrollCaptureView, context: Context) {
        nsView.onScroll = action
    }
}

final class ScrollCaptureView: NSView {
    var onScroll: ((CGFloat) -> Void)?

    override func scrollWheel(with event: NSEvent) {
        let delta = event.scrollingDeltaY
        if event.hasPreciseScrollingDeltas {
            onScroll?(delta)
        } else {
            onScroll?(delta * 10)
        }
    }
}

extension View {
    func onScrollGesture(action: @escaping (CGFloat) -> Void) -> some View {
        modifier(ScrollGestureModifier(action: action))
    }
}
