import SwiftUI
import CoreData

// MARK: - Color Mode for Graph Nodes

enum GraphColorMode: String, CaseIterable, Identifiable {
    case para = "PARA"
    case noteType = "Note Type"
    case code = "CODE"
    case custom = "Custom"

    var id: String { rawValue }

    var label: String { rawValue }

    var icon: String {
        switch self {
        case .para: "folder"
        case .noteType: "doc"
        case .code: "gearshape"
        case .custom: "paintpalette"
        }
    }
}

// MARK: - Graph View

struct GraphView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.managedObjectContext) private var context

    @State private var layout = ForceDirectedLayout()
    @State private var zoom: CGFloat = 1.0
    @State private var offset: CGPoint = .zero
    @State private var dragStartOffset: CGPoint = .zero
    @State private var isDraggingBackground: Bool = false
    @State private var draggingNodeId: UUID?
    @State private var selectedNodeId: UUID?
    @State private var hoveredNodeId: UUID?
    @State private var colorMode: GraphColorMode = .para
    @State private var isLocalGraph: Bool = false
    @State private var localDepth: Int = 2
    @State private var physicsEnabled: Bool = true
    @State private var showLegend: Bool = false
    @State private var showMinimap: Bool = true
    @State private var graphSearchQuery: String = ""

    // Filter toggles
    @State private var hiddenPARA: Set<PARACategory> = []
    @State private var hiddenNoteTypes: Set<NoteType> = []
    @State private var hiddenCODEStages: Set<CODEStage> = []

    // Timer for physics simulation
    @State private var simulationTimer: Timer?

    var body: some View {
        ZStack {
            // Canvas rendering
            graphCanvas
                .gesture(backgroundDragGesture)
                .gesture(scrollZoomGesture)
                .onTapGesture(count: 2) { location in
                    handleDoubleTap(at: location)
                }
                .onTapGesture(count: 1) { location in
                    handleSingleTap(at: location)
                }
                .contextMenu { contextMenuItems }

            // Overlays
            VStack {
                GraphToolbar(
                    colorMode: $colorMode,
                    isLocalGraph: $isLocalGraph,
                    localDepth: $localDepth,
                    physicsEnabled: $physicsEnabled,
                    showLegend: $showLegend,
                    showMinimap: $showMinimap,
                    graphSearchQuery: $graphSearchQuery,
                    hiddenPARA: $hiddenPARA,
                    hiddenNoteTypes: $hiddenNoteTypes,
                    hiddenCODEStages: $hiddenCODEStages,
                    zoom: $zoom,
                    nodeCount: filteredNodes.count,
                    edgeCount: layout.edges.count,
                    isSimulationRunning: layout.isRunning,
                    onResetLayout: { layout.resetLayout() },
                    onFitAll: fitAll,
                    onTogglePhysics: {
                        physicsEnabled.toggle()
                        if physicsEnabled {
                            layout.startSimulation()
                        } else {
                            layout.stopSimulation()
                        }
                    }
                )

                Spacer()
            }

            // Tooltip on hover
            if let hid = hoveredNodeId, let idx = layout.nodeIndex(for: hid) {
                nodeTooltip(for: layout.nodes[idx])
            }

            // Legend overlay
            if showLegend {
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        GraphLegend(colorMode: colorMode)
                            .padding()
                    }
                }
            }

            // Minimap overlay
            if showMinimap {
                VStack {
                    Spacer()
                    HStack {
                        GraphMinimap(
                            nodes: layout.nodes,
                            edges: layout.edges,
                            viewportOffset: offset,
                            viewportZoom: zoom,
                            colorMode: colorMode,
                            onNavigate: { newCenter in
                                offset = newCenter
                            }
                        )
                        .padding()
                        Spacer()
                    }
                }
            }
        }
        .morosBackground()
        .onAppear {
            reloadGraph()
            startSimulationTimer()
        }
        .onDisappear {
            stopSimulationTimer()
        }
        .onChange(of: isLocalGraph) { _, _ in reloadGraph() }
        .onChange(of: localDepth) { _, _ in reloadGraph() }
        .onChange(of: appState.selectedNote) { _, _ in
            if isLocalGraph { reloadGraph() }
        }
    }

    // MARK: - Filtered Data

    private var filteredNodes: [ForceDirectedLayout.Node] {
        layout.nodes.filter { node in
            if hiddenPARA.contains(node.cachedPARA) { return false }
            if hiddenNoteTypes.contains(node.cachedNoteType) { return false }
            if hiddenCODEStages.contains(node.cachedCODEStage) { return false }
            if !graphSearchQuery.isEmpty {
                let q = graphSearchQuery.lowercased()
                if !node.cachedTitle.lowercased().contains(q)
                    && !node.cachedTags.contains(where: { $0.lowercased().contains(q) }) {
                    return false
                }
            }
            return true
        }
    }

    private var filteredNodeIds: Set<UUID> {
        Set(filteredNodes.map(\.id))
    }

    private var filteredEdges: [ForceDirectedLayout.Edge] {
        let ids = filteredNodeIds
        return layout.edges.filter { ids.contains($0.sourceId) && ids.contains($0.targetId) }
    }

    // MARK: - Canvas

    private var graphCanvas: some View {
        Canvas { canvasContext, size in
            // Apply viewport transform
            let transform = CGAffineTransform(translationX: offset.x, y: offset.y)
                .scaledBy(x: zoom, y: zoom)

            // Draw edges
            for edge in filteredEdges {
                guard let si = layout.nodeIndex(for: edge.sourceId),
                      let ti = layout.nodeIndex(for: edge.targetId) else { continue }

                let source = layout.nodes[si].position.applying(transform)
                let target = layout.nodes[ti].position.applying(transform)

                let edgeColor = colorForLinkType(edge.linkType)
                let lineWidth = 1.0 + CGFloat(edge.strength) * 3.0

                var path = Path()
                path.move(to: source)
                path.addLine(to: target)

                if !edge.isConfirmed || edge.isAISuggested {
                    let style = StrokeStyle(lineWidth: lineWidth, dash: [6, 4])
                    canvasContext.stroke(path, with: .color(edgeColor.opacity(0.6)), style: style)
                } else {
                    canvasContext.stroke(path, with: .color(edgeColor.opacity(0.7)), lineWidth: lineWidth)
                }

                // Draw arrowhead
                drawArrowhead(in: &canvasContext, from: source, to: target, color: edgeColor, nodeRadius: layout.nodes[ti].radius * zoom)
            }

            // Draw nodes
            for node in filteredNodes {
                let screenPos = node.position.applying(transform)
                let r = node.radius * zoom
                let rect = CGRect(x: screenPos.x - r, y: screenPos.y - r, width: r * 2, height: r * 2)

                let nodeColor = colorForNode(node)
                let isSelected = node.id == selectedNodeId
                let isHovered = node.id == hoveredNodeId

                // Glow for selected
                if isSelected {
                    let glowRect = rect.insetBy(dx: -4, dy: -4)
                    canvasContext.fill(Circle().path(in: glowRect), with: .color(Moros.oracle.opacity(0.3)))
                }

                // Node circle
                canvasContext.fill(Circle().path(in: rect), with: .color(nodeColor))

                // Border
                let borderColor: Color = isSelected ? Moros.oracle : (isHovered ? Color.white.opacity(0.4) : Moros.borderLit)
                let borderWidth: CGFloat = isSelected ? 2.5 : (isHovered ? 2.0 : 1.0)
                canvasContext.stroke(Circle().path(in: rect), with: .color(borderColor), lineWidth: borderWidth)

                // Label (only if zoomed in enough)
                if zoom > 0.4 {
                    let title = node.cachedTitle.isEmpty ? "Untitled" : node.cachedTitle
                    let truncated = title.count > 20 ? String(title.prefix(18)) + "..." : title
                    let textPoint = CGPoint(x: screenPos.x, y: screenPos.y + r + 8 * zoom)

                    canvasContext.draw(
                        Text(truncated)
                            .font(.system(size: max(9, 11 * zoom), weight: isSelected ? .semibold : .regular))
                            .foregroundColor(Color(Moros.textSub)),
                        at: textPoint,
                        anchor: .top
                    )
                }
            }
        }
    }

    // MARK: - Arrowhead

    private func drawArrowhead(in context: inout GraphicsContext, from source: CGPoint, to target: CGPoint, color: Color, nodeRadius: CGFloat) {
        let dx = target.x - source.x
        let dy = target.y - source.y
        let length = sqrt(dx * dx + dy * dy)
        guard length > 0 else { return }

        let nx = dx / length
        let ny = dy / length

        let arrowTip = CGPoint(x: target.x - nx * nodeRadius, y: target.y - ny * nodeRadius)
        let arrowSize: CGFloat = 8 * zoom

        let leftX = arrowTip.x - nx * arrowSize - ny * arrowSize * 0.4
        let leftY = arrowTip.y - ny * arrowSize + nx * arrowSize * 0.4
        let rightX = arrowTip.x - nx * arrowSize + ny * arrowSize * 0.4
        let rightY = arrowTip.y - ny * arrowSize - nx * arrowSize * 0.4

        var arrow = Path()
        arrow.move(to: arrowTip)
        arrow.addLine(to: CGPoint(x: leftX, y: leftY))
        arrow.addLine(to: CGPoint(x: rightX, y: rightY))
        arrow.closeSubpath()

        context.fill(arrow, with: .color(color.opacity(0.7)))
    }

    // MARK: - Color Helpers

    func colorForNode(_ node: ForceDirectedLayout.Node) -> Color {
        switch colorMode {
        case .para:
            return paraColor(node.cachedPARA)
        case .noteType:
            return noteTypeColor(node.cachedNoteType)
        case .code:
            return codeStageColor(node.cachedCODEStage)
        case .custom:
            if let hex = node.cachedColorHex, !hex.isEmpty {
                return Color(hex: hex)
            }
            return paraColor(node.cachedPARA)
        }
    }

    private func paraColor(_ category: PARACategory) -> Color {
        switch category {
        case .inbox: return Moros.ambient
        case .project: return Moros.oracle
        case .area: return Moros.verdit
        case .resource: return Moros.ambient.opacity(0.7)
        case .archive: return Moros.textDim
        }
    }

    private func noteTypeColor(_ type: NoteType) -> Color {
        switch type {
        case .fleeting: return Moros.ambient
        case .literature: return Moros.oracle
        case .permanent: return Moros.verdit
        }
    }

    private func codeStageColor(_ stage: CODEStage) -> Color {
        switch stage {
        case .captured: return Moros.signal
        case .organized: return Moros.ambient
        case .distilled: return Moros.verdit
        case .expressed: return Moros.oracle
        }
    }

    private func colorForLinkType(_ type: LinkType) -> Color {
        switch type {
        case .reference: return Moros.ambient
        case .supports: return Moros.verdit
        case .contradicts: return Moros.signal
        case .extends: return Moros.oracle
        case .example: return Moros.ambient.opacity(0.7)
        }
    }

    // MARK: - Gestures

    private var backgroundDragGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                if draggingNodeId == nil && !isDraggingBackground {
                    if let node = layout.nodeAt(point: value.startLocation, zoom: zoom, offset: offset) {
                        draggingNodeId = node.id
                        layout.pinNode(id: node.id, pinned: true)
                    } else {
                        isDraggingBackground = true
                        dragStartOffset = offset
                    }
                }

                if let nodeId = draggingNodeId {
                    let worldPos = CGPoint(
                        x: (value.location.x - offset.x) / zoom,
                        y: (value.location.y - offset.y) / zoom
                    )
                    layout.moveNode(id: nodeId, to: worldPos)
                    if physicsEnabled && !layout.isRunning {
                        layout.startSimulation()
                    }
                } else if isDraggingBackground {
                    offset = CGPoint(
                        x: dragStartOffset.x + value.translation.width,
                        y: dragStartOffset.y + value.translation.height
                    )
                }
            }
            .onEnded { _ in
                draggingNodeId = nil
                isDraggingBackground = false
            }
    }

    private var scrollZoomGesture: some Gesture {
        MagnificationGesture()
            .onChanged { scale in
                let newZoom = max(0.1, min(5.0, zoom * scale))
                zoom = newZoom
            }
    }

    // MARK: - Tap Handlers

    private func handleSingleTap(at location: CGPoint) {
        if let node = layout.nodeAt(point: location, zoom: zoom, offset: offset) {
            selectedNodeId = node.id
        } else {
            selectedNodeId = nil
        }
    }

    private func handleDoubleTap(at location: CGPoint) {
        if let node = layout.nodeAt(point: location, zoom: zoom, offset: offset) {
            appState.selectedNote = node.note
        }
    }

    // MARK: - Context Menu

    @ViewBuilder
    private var contextMenuItems: some View {
        if let sid = selectedNodeId, let idx = layout.nodeIndex(for: sid) {
            let node = layout.nodes[idx]
            Button("Open Note") {
                appState.selectedNote = node.note
            }
            Divider()
            Button(node.isFixed ? "Unpin from Graph" : "Pin in Graph") {
                layout.pinNode(id: sid, pinned: !node.isFixed)
            }
            Divider()
            Button("Center on This Note") {
                withAnimation(.easeInOut(duration: 0.3)) {
                    let targetOffset = CGPoint(
                        x: -node.position.x * zoom + 400,
                        y: -node.position.y * zoom + 300
                    )
                    offset = targetOffset
                }
            }
        }
    }

    // MARK: - Tooltip

    private func nodeTooltip(for node: ForceDirectedLayout.Node) -> some View {
        let screenPos = CGPoint(
            x: node.position.x * zoom + offset.x,
            y: node.position.y * zoom + offset.y - node.radius * zoom - 50
        )

        return VStack(alignment: .leading, spacing: 4) {
            Text(node.cachedTitle.isEmpty ? "Untitled" : node.cachedTitle)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Moros.textMain)
                .lineLimit(1)
            HStack(spacing: 8) {
                Label(node.cachedNoteType.label, systemImage: node.cachedNoteType.icon)
                Label(node.cachedPARA.label, systemImage: node.cachedPARA.icon)
            }
            .font(Moros.fontCaption)
            .foregroundStyle(Moros.textSub)

            if !node.cachedTags.isEmpty {
                Text("Tags: " + node.cachedTags.prefix(3).joined(separator: ", "))
                    .font(Moros.fontMicro)
                    .foregroundStyle(Moros.textDim)
            }

            Text("\(node.cachedLinkCount) links")
                .font(Moros.fontMicro)
                .foregroundStyle(Moros.textDim)
        }
        .padding(8)
        .background(Moros.limit02, in: Rectangle())
        .overlay(Rectangle().stroke(Moros.borderLit, lineWidth: 1))
        .position(screenPos)
        .allowsHitTesting(false)
    }

    // MARK: - Fit All

    private func fitAll() {
        guard !layout.nodes.isEmpty else { return }

        let positions = layout.nodes.map(\.position)
        let minX = positions.map(\.x).min()!
        let maxX = positions.map(\.x).max()!
        let minY = positions.map(\.y).min()!
        let maxY = positions.map(\.y).max()!

        let graphWidth = maxX - minX + 100
        let graphHeight = maxY - minY + 100

        let viewWidth: CGFloat = 800
        let viewHeight: CGFloat = 600

        let zoomX = viewWidth / max(graphWidth, 1)
        let zoomY = viewHeight / max(graphHeight, 1)
        let newZoom = max(0.1, min(2.0, min(zoomX, zoomY)))

        let centerX = (minX + maxX) / 2
        let centerY = (minY + maxY) / 2

        withAnimation(.easeInOut(duration: Moros.animSlow)) {
            zoom = newZoom
            offset = CGPoint(
                x: viewWidth / 2 - centerX * newZoom,
                y: viewHeight / 2 - centerY * newZoom
            )
        }
    }

    // MARK: - Simulation Timer

    private func startSimulationTimer() {
        simulationTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { _ in
            if layout.isRunning && physicsEnabled {
                layout.step(dt: 1.0 / 60.0)
            }
        }
    }

    private func stopSimulationTimer() {
        simulationTimer?.invalidate()
        simulationTimer = nil
    }

    // MARK: - Reload

    private func reloadGraph() {
        let center = isLocalGraph ? appState.selectedNote : nil
        let depth = isLocalGraph ? localDepth : 0
        layout.loadFromContext(context, centerNote: center, depth: depth)
        layout.centerPoint = CGPoint(x: 400, y: 300)
    }
}

// Color(hex:) is defined in Utilities/ColorExtensions.swift
