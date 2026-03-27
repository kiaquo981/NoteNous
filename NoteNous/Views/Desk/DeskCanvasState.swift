import SwiftUI
import CoreData

// MARK: - Canvas State

@Observable
@MainActor
final class DeskCanvasState {

    // MARK: Viewport

    var viewportOffset: CGPoint = .zero
    var zoomLevel: CGFloat = 1.0

    // MARK: Selection

    var selectedNoteIds: Set<UUID> = []
    var isRubberBandSelecting: Bool = false
    var rubberBandOrigin: CGPoint = .zero
    var rubberBandCurrent: CGPoint = .zero

    // MARK: Dragging

    var isDragging: Bool = false
    var dragOffset: CGSize = .zero
    var draggedNoteIds: Set<UUID> = []

    // MARK: Link creation

    var isCreatingLink: Bool = false
    var linkSourceNoteId: UUID?
    var linkDragEnd: CGPoint = .zero

    // MARK: Display

    var showConnections: Bool = true
    var snapToGrid: Bool = false
    var gridSize: CGFloat = 20
    var cardDisplayMode: CardDisplayMode = .normal
    var filterMode: FilterMode = .none
    var filterValue: String?

    // MARK: Zoom limits

    static let minZoom: CGFloat = 0.1
    static let maxZoom: CGFloat = 5.0

    // MARK: Enums

    enum CardDisplayMode: String, CaseIterable, Identifiable {
        case compact, normal, expanded
        var id: String { rawValue }

        var label: String {
            switch self {
            case .compact: "Compact"
            case .normal: "Normal"
            case .expanded: "Expanded"
            }
        }

        var icon: String {
            switch self {
            case .compact: "rectangle.compress.vertical"
            case .normal: "rectangle"
            case .expanded: "rectangle.expand.vertical"
            }
        }
    }

    enum FilterMode: String, CaseIterable, Identifiable {
        case none, para, noteType, color
        var id: String { rawValue }

        var label: String {
            switch self {
            case .none: "All"
            case .para: "PARA"
            case .noteType: "Type"
            case .color: "Color"
            }
        }
    }

    // MARK: - Coordinate Transforms

    /// Convert a point in screen (view) coordinates to canvas coordinates.
    func screenToCanvas(_ point: CGPoint) -> CGPoint {
        CGPoint(
            x: (point.x - viewportOffset.x) / zoomLevel,
            y: (point.y - viewportOffset.y) / zoomLevel
        )
    }

    /// Convert a point in canvas coordinates to screen (view) coordinates.
    func canvasToScreen(_ point: CGPoint) -> CGPoint {
        CGPoint(
            x: point.x * zoomLevel + viewportOffset.x,
            y: point.y * zoomLevel + viewportOffset.y
        )
    }

    /// Snap a canvas-space point to the nearest grid intersection.
    func snapToGridPoint(_ point: CGPoint) -> CGPoint {
        guard snapToGrid else { return point }
        return CGPoint(
            x: (point.x / gridSize).rounded() * gridSize,
            y: (point.y / gridSize).rounded() * gridSize
        )
    }

    // MARK: - Zoom

    /// Zoom toward a specific screen-space anchor point.
    func zoom(by factor: CGFloat, anchor: CGPoint) {
        let newZoom = min(Self.maxZoom, max(Self.minZoom, zoomLevel * factor))
        let scale = newZoom / zoomLevel
        viewportOffset = CGPoint(
            x: anchor.x - (anchor.x - viewportOffset.x) * scale,
            y: anchor.y - (anchor.y - viewportOffset.y) * scale
        )
        zoomLevel = newZoom
    }

    /// Adjust viewport to fit all supplied notes within the given view size.
    func zoomToFit(notes: [NoteEntity], in size: CGSize, padding: CGFloat = 80) {
        guard !notes.isEmpty else { return }

        let cardWidth: CGFloat = 200
        let cardHeight: CGFloat = 140
        var minX = CGFloat.greatestFiniteMagnitude
        var minY = CGFloat.greatestFiniteMagnitude
        var maxX = -CGFloat.greatestFiniteMagnitude
        var maxY = -CGFloat.greatestFiniteMagnitude

        for note in notes {
            let nx = CGFloat(note.positionX)
            let ny = CGFloat(note.positionY)
            minX = min(minX, nx)
            minY = min(minY, ny)
            maxX = max(maxX, nx + cardWidth)
            maxY = max(maxY, ny + cardHeight)
        }

        let contentWidth = maxX - minX + padding * 2
        let contentHeight = maxY - minY + padding * 2

        guard contentWidth > 0, contentHeight > 0 else { return }

        let scaleX = size.width / contentWidth
        let scaleY = size.height / contentHeight
        let newZoom = min(Self.maxZoom, max(Self.minZoom, min(scaleX, scaleY)))

        zoomLevel = newZoom
        viewportOffset = CGPoint(
            x: (size.width - (maxX + minX) * newZoom) / 2,
            y: (size.height - (maxY + minY) * newZoom) / 2
        )
    }

    // MARK: - Selection helpers

    func toggleSelection(_ noteId: UUID, shiftHeld: Bool) {
        if shiftHeld {
            if selectedNoteIds.contains(noteId) {
                selectedNoteIds.remove(noteId)
            } else {
                selectedNoteIds.insert(noteId)
            }
        } else {
            selectedNoteIds = [noteId]
        }
    }

    func clearSelection() {
        selectedNoteIds.removeAll()
    }

    func selectAll(_ noteIds: [UUID]) {
        selectedNoteIds = Set(noteIds)
    }

    // MARK: - Rubber-band selection

    var rubberBandRect: CGRect {
        let origin = CGPoint(
            x: min(rubberBandOrigin.x, rubberBandCurrent.x),
            y: min(rubberBandOrigin.y, rubberBandCurrent.y)
        )
        let size = CGSize(
            width: abs(rubberBandCurrent.x - rubberBandOrigin.x),
            height: abs(rubberBandCurrent.y - rubberBandOrigin.y)
        )
        return CGRect(origin: origin, size: size)
    }

    /// Returns the IDs of notes whose canvas rects intersect the rubber-band region.
    func notesInRubberBand(_ notes: [NoteEntity], cardSize: CGSize = CGSize(width: 200, height: 140)) -> Set<UUID> {
        let selectionRect = rubberBandRect
        var ids = Set<UUID>()
        for note in notes {
            guard let noteId = note.id else { continue }
            let noteRect = CGRect(
                x: CGFloat(note.positionX) * zoomLevel + viewportOffset.x,
                y: CGFloat(note.positionY) * zoomLevel + viewportOffset.y,
                width: cardSize.width * zoomLevel,
                height: cardSize.height * zoomLevel
            )
            if selectionRect.intersects(noteRect) {
                ids.insert(noteId)
            }
        }
        return ids
    }

    // MARK: - Auto-layout helpers

    /// Arrange notes in a grid pattern, saving positions to Core Data.
    func layoutGrid(notes: [NoteEntity], columns: Int = 5, spacing: CGFloat = 40, context: NSManagedObjectContext) {
        let cardWidth: CGFloat = 200
        let cardHeight: CGFloat = 140
        for (index, note) in notes.enumerated() {
            let col = index % columns
            let row = index / columns
            note.positionX = Double(CGFloat(col) * (cardWidth + spacing))
            note.positionY = Double(CGFloat(row) * (cardHeight + spacing))
        }
        try? context.save()
    }

    /// Cluster notes by PARA category in columns.
    func layoutByPARA(notes: [NoteEntity], spacing: CGFloat = 40, context: NSManagedObjectContext) {
        let cardWidth: CGFloat = 200
        let cardHeight: CGFloat = 140
        let columnSpacing: CGFloat = 300

        let grouped = Dictionary(grouping: notes) { $0.paraCategory }
        for (categoryIndex, category) in PARACategory.allCases.enumerated() {
            guard let categoryNotes = grouped[category] else { continue }
            let baseX = CGFloat(categoryIndex) * columnSpacing
            for (row, note) in categoryNotes.enumerated() {
                note.positionX = Double(baseX)
                note.positionY = Double(CGFloat(row) * (cardHeight + spacing))
            }
        }
        try? context.save()
    }

    /// Cluster notes by tag.
    func layoutByTag(notes: [NoteEntity], spacing: CGFloat = 40, context: NSManagedObjectContext) {
        let cardWidth: CGFloat = 200
        let cardHeight: CGFloat = 140
        let clusterSpacing: CGFloat = 350

        var tagGroups: [String: [NoteEntity]] = [:]
        var untagged: [NoteEntity] = []

        for note in notes {
            let tags = note.tagsArray
            if let firstTag = tags.first?.name {
                tagGroups[firstTag, default: []].append(note)
            } else {
                untagged.append(note)
            }
        }

        var clusterIndex = 0
        let allGroups = tagGroups.sorted(by: { $0.key < $1.key }).map(\.value) + (untagged.isEmpty ? [] : [untagged])

        for group in allGroups {
            let baseX = CGFloat(clusterIndex) * clusterSpacing
            for (row, note) in group.enumerated() {
                note.positionX = Double(baseX)
                note.positionY = Double(CGFloat(row) * (cardHeight + spacing))
            }
            clusterIndex += 1
        }
        try? context.save()
    }

    // MARK: - Visibility culling

    /// Returns true if a note's card is (at least partially) visible in the given viewport size.
    func isVisible(note: NoteEntity, viewportSize: CGSize, cardSize: CGSize = CGSize(width: 200, height: 140)) -> Bool {
        let screenPos = canvasToScreen(CGPoint(x: note.positionX, y: note.positionY))
        let scaledWidth = cardSize.width * zoomLevel
        let scaledHeight = cardSize.height * zoomLevel
        let margin: CGFloat = 50 * zoomLevel
        return screenPos.x + scaledWidth + margin > 0
            && screenPos.x - margin < viewportSize.width
            && screenPos.y + scaledHeight + margin > 0
            && screenPos.y - margin < viewportSize.height
    }
}
