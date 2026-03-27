import SwiftUI
import CoreData

// MARK: - Local Graph View (Panel Mode)

/// A compact graph view showing the neighborhood of a single note.
/// Designed to be embedded as a panel alongside the note editor.
struct LocalGraphView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.managedObjectContext) private var context

    let centerNote: NoteEntity

    @State private var layout = ForceDirectedLayout()
    @State private var depth: Int = 1
    @State private var zoom: CGFloat = 1.0
    @State private var offset: CGPoint = .zero
    @State private var dragStartOffset: CGPoint = .zero
    @State private var isDraggingBackground: Bool = false
    @State private var draggingNodeId: UUID?
    @State private var hoveredNodeId: UUID?
    @State private var colorMode: GraphColorMode = .para
    @State private var simulationTimer: Timer?

    private let panelSize = CGSize(width: 320, height: 260)

    var body: some View {
        VStack(spacing: 0) {
            // Header
            header

            Divider()

            // Canvas
            graphCanvas
                .frame(height: panelSize.height)
                .clipped()
                .gesture(panGesture)
                .onTapGesture(count: 2) { location in
                    if let node = layout.nodeAt(point: location, zoom: zoom, offset: offset) {
                        appState.selectedNote = node.note
                    }
                }

            Divider()

            // Footer controls
            footer
        }
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(.separator, lineWidth: 0.5)
        )
        .onAppear {
            loadLocalGraph()
            startTimer()
        }
        .onDisappear {
            stopTimer()
        }
        .onChange(of: depth) { _, _ in
            withAnimation(.easeInOut(duration: 0.3)) {
                loadLocalGraph()
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Image(systemName: "point.3.connected.trianglepath.dotted")
                .foregroundStyle(.secondary)
            Text("Local Graph")
                .font(.caption)
                .fontWeight(.medium)
            Spacer()
            Picker("Depth", selection: $depth) {
                ForEach(1...5, id: \.self) { d in
                    Text("\(d)").tag(d)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 140)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
    }

    // MARK: - Canvas

    private var graphCanvas: some View {
        Canvas { canvasContext, size in
            let transform = CGAffineTransform(translationX: offset.x + size.width / 2, y: offset.y + size.height / 2)
                .scaledBy(x: zoom, y: zoom)

            // Edges
            for edge in layout.edges {
                guard let si = layout.nodeIndex(for: edge.sourceId),
                      let ti = layout.nodeIndex(for: edge.targetId) else { continue }

                let source = layout.nodes[si].position.applying(transform)
                let target = layout.nodes[ti].position.applying(transform)
                let edgeColor = linkTypeColor(edge.linkType)
                let lineWidth = 0.5 + CGFloat(edge.strength) * 2.0

                var path = Path()
                path.move(to: source)
                path.addLine(to: target)

                if !edge.isConfirmed || edge.isAISuggested {
                    canvasContext.stroke(path, with: .color(edgeColor.opacity(0.4)), style: StrokeStyle(lineWidth: lineWidth, dash: [4, 3]))
                } else {
                    canvasContext.stroke(path, with: .color(edgeColor.opacity(0.5)), lineWidth: lineWidth)
                }
            }

            // Nodes
            for node in layout.nodes {
                let screenPos = node.position.applying(transform)
                let r = node.radius * zoom
                let rect = CGRect(x: screenPos.x - r, y: screenPos.y - r, width: r * 2, height: r * 2)

                let isCenter = node.id == centerNote.id
                let isHovered = node.id == hoveredNodeId
                let nodeColor = nodeColorForMode(node)

                // Glow for center node
                if isCenter {
                    let glowRect = rect.insetBy(dx: -4, dy: -4)
                    canvasContext.fill(Circle().path(in: glowRect), with: .color(.accentColor.opacity(0.25)))
                }

                canvasContext.fill(Circle().path(in: rect), with: .color(nodeColor))

                let borderWidth: CGFloat = isCenter ? 2.0 : (isHovered ? 1.5 : 0.5)
                let borderColor: Color = isCenter ? .accentColor : (isHovered ? .white.opacity(0.7) : .white.opacity(0.2))
                canvasContext.stroke(Circle().path(in: rect), with: .color(borderColor), lineWidth: borderWidth)

                // Compact label
                if zoom > 0.6 {
                    let title = node.cachedTitle.isEmpty ? "Untitled" : node.cachedTitle
                    let truncated = title.count > 14 ? String(title.prefix(12)) + ".." : title
                    canvasContext.draw(
                        Text(truncated)
                            .font(.system(size: max(8, 9 * zoom)))
                            .foregroundColor(.primary),
                        at: CGPoint(x: screenPos.x, y: screenPos.y + r + 6 * zoom),
                        anchor: .top
                    )
                }
            }
        }
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            Text("\(layout.nodes.count) nodes")
                .font(.caption2)
                .foregroundStyle(.tertiary)

            Spacer()

            Menu {
                ForEach(GraphColorMode.allCases) { mode in
                    Button {
                        colorMode = mode
                    } label: {
                        Label(mode.label, systemImage: mode.icon)
                    }
                }
            } label: {
                Image(systemName: "paintpalette")
                    .font(.caption2)
            }
            .menuStyle(.borderlessButton)
            .frame(width: 24)

            Button {
                zoom = 1.0
                offset = .zero
            } label: {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .font(.caption2)
            }
            .buttonStyle(.borderless)
            .help("Reset view")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
    }

    // MARK: - Helpers

    private func nodeColorForMode(_ node: ForceDirectedLayout.Node) -> Color {
        switch colorMode {
        case .para:
            return paraColorLocal(node.cachedPARA)
        case .noteType:
            return noteTypeColorLocal(node.cachedNoteType)
        case .code:
            return codeStageColorLocal(node.cachedCODEStage)
        case .custom:
            if let hex = node.cachedColorHex, !hex.isEmpty {
                return Color(hex: hex)
            }
            return paraColorLocal(node.cachedPARA)
        }
    }

    private func paraColorLocal(_ c: PARACategory) -> Color {
        switch c {
        case .inbox: .gray
        case .project: .blue
        case .area: .green
        case .resource: .orange
        case .archive: .secondary
        }
    }

    private func noteTypeColorLocal(_ t: NoteType) -> Color {
        switch t {
        case .fleeting: .yellow
        case .literature: .cyan
        case .permanent: .purple
        }
    }

    private func codeStageColorLocal(_ s: CODEStage) -> Color {
        switch s {
        case .captured: .red.opacity(0.8)
        case .organized: .orange
        case .distilled: .green
        case .expressed: .blue
        }
    }

    private func linkTypeColor(_ type: LinkType) -> Color {
        switch type {
        case .reference: .gray
        case .supports: .green
        case .contradicts: .red
        case .extends: .blue
        case .example: .orange
        }
    }

    private var panGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                if draggingNodeId == nil && !isDraggingBackground {
                    let adjustedPoint = CGPoint(
                        x: value.startLocation.x - panelSize.width / 2,
                        y: value.startLocation.y - panelSize.height / 2
                    )
                    if let node = layout.nodeAt(point: adjustedPoint, zoom: zoom, offset: offset) {
                        draggingNodeId = node.id
                        layout.pinNode(id: node.id, pinned: true)
                    } else {
                        isDraggingBackground = true
                        dragStartOffset = offset
                    }
                }

                if let nodeId = draggingNodeId {
                    let worldPos = CGPoint(
                        x: (value.location.x - panelSize.width / 2 - offset.x) / zoom,
                        y: (value.location.y - panelSize.height / 2 - offset.y) / zoom
                    )
                    layout.moveNode(id: nodeId, to: worldPos)
                    if !layout.isRunning { layout.startSimulation() }
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

    // MARK: - Data

    private func loadLocalGraph() {
        layout.centerPoint = .zero // panel uses center-based transform
        layout.loadFromContext(context, centerNote: centerNote, depth: depth)
    }

    private func startTimer() {
        simulationTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { _ in
            if layout.isRunning {
                layout.step(dt: 1.0 / 60.0)
            }
        }
    }

    private func stopTimer() {
        simulationTimer?.invalidate()
        simulationTimer = nil
    }
}

// Color(hex:) is defined in Utilities/ColorExtensions.swift
