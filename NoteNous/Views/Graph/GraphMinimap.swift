import SwiftUI

// MARK: - Graph Minimap

struct GraphMinimap: View {
    let nodes: [ForceDirectedLayout.Node]
    let edges: [ForceDirectedLayout.Edge]
    let viewportOffset: CGPoint
    let viewportZoom: CGFloat
    let colorMode: GraphColorMode

    var onNavigate: (CGPoint) -> Void

    private let minimapSize: CGFloat = 100

    var body: some View {
        Canvas { context, size in
            guard !nodes.isEmpty else { return }

            let bounds = graphBounds
            let scale = minimapScale(graphBounds: bounds, canvasSize: size)
            let graphCenter = CGPoint(
                x: (bounds.minX + bounds.maxX) / 2,
                y: (bounds.minY + bounds.maxY) / 2
            )

            // Draw edges as thin lines
            for edge in edges {
                guard let si = nodeIndex(edge.sourceId),
                      let ti = nodeIndex(edge.targetId) else { continue }

                let sp = minimapPoint(nodes[si].position, center: graphCenter, scale: scale, canvasSize: size)
                let tp = minimapPoint(nodes[ti].position, center: graphCenter, scale: scale, canvasSize: size)

                var path = Path()
                path.move(to: sp)
                path.addLine(to: tp)
                context.stroke(path, with: .color(.secondary.opacity(0.15)), lineWidth: 0.5)
            }

            // Draw nodes as tiny dots
            for node in nodes {
                let pos = minimapPoint(node.position, center: graphCenter, scale: scale, canvasSize: size)
                let dotSize: CGFloat = max(2, node.radius * scale * 0.3)
                let rect = CGRect(
                    x: pos.x - dotSize / 2,
                    y: pos.y - dotSize / 2,
                    width: dotSize,
                    height: dotSize
                )
                let color = minimapNodeColor(node)
                context.fill(Circle().path(in: rect), with: .color(color))
            }

            // Draw viewport rectangle
            let viewportRect = computeViewportRect(
                graphCenter: graphCenter,
                scale: scale,
                canvasSize: size
            )
            context.stroke(
                Rectangle().path(in: viewportRect),
                with: .color(.accentColor.opacity(0.8)),
                lineWidth: 1.5
            )
            context.fill(
                Rectangle().path(in: viewportRect),
                with: .color(.accentColor.opacity(0.08))
            )
        }
        .frame(width: minimapSize, height: minimapSize)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(.separator, lineWidth: 0.5)
        )
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    handleMinimapTap(at: value.location)
                }
        )
    }

    // MARK: - Graph Bounds

    private var graphBounds: (minX: CGFloat, maxX: CGFloat, minY: CGFloat, maxY: CGFloat) {
        let xs = nodes.map(\.position.x)
        let ys = nodes.map(\.position.y)
        return (
            minX: (xs.min() ?? 0) - 50,
            maxX: (xs.max() ?? 0) + 50,
            minY: (ys.min() ?? 0) - 50,
            maxY: (ys.max() ?? 0) + 50
        )
    }

    private func minimapScale(
        graphBounds: (minX: CGFloat, maxX: CGFloat, minY: CGFloat, maxY: CGFloat),
        canvasSize: CGSize
    ) -> CGFloat {
        let gw = max(graphBounds.maxX - graphBounds.minX, 1)
        let gh = max(graphBounds.maxY - graphBounds.minY, 1)
        let padding: CGFloat = 8
        let available = minimapSize - padding * 2
        return min(available / gw, available / gh)
    }

    private func minimapPoint(
        _ worldPoint: CGPoint,
        center: CGPoint,
        scale: CGFloat,
        canvasSize: CGSize
    ) -> CGPoint {
        CGPoint(
            x: canvasSize.width / 2 + (worldPoint.x - center.x) * scale,
            y: canvasSize.height / 2 + (worldPoint.y - center.y) * scale
        )
    }

    // MARK: - Viewport Rectangle

    private func computeViewportRect(
        graphCenter: CGPoint,
        scale: CGFloat,
        canvasSize: CGSize
    ) -> CGRect {
        // Approximate the main viewport size (using a reference 800x600)
        let mainViewW: CGFloat = 800
        let mainViewH: CGFloat = 600

        // World-space center of the current viewport
        let worldCenterX = (mainViewW / 2 - viewportOffset.x) / viewportZoom
        let worldCenterY = (mainViewH / 2 - viewportOffset.y) / viewportZoom

        // World-space size of the viewport
        let worldW = mainViewW / viewportZoom
        let worldH = mainViewH / viewportZoom

        // Convert to minimap coords
        let cx = canvasSize.width / 2 + (worldCenterX - graphCenter.x) * scale
        let cy = canvasSize.height / 2 + (worldCenterY - graphCenter.y) * scale
        let w = worldW * scale
        let h = worldH * scale

        return CGRect(x: cx - w / 2, y: cy - h / 2, width: w, height: h)
    }

    // MARK: - Navigation

    private func handleMinimapTap(at point: CGPoint) {
        guard !nodes.isEmpty else { return }

        let bounds = graphBounds
        let scale = minimapScale(graphBounds: bounds, canvasSize: CGSize(width: minimapSize, height: minimapSize))
        let graphCenter = CGPoint(
            x: (bounds.minX + bounds.maxX) / 2,
            y: (bounds.minY + bounds.maxY) / 2
        )

        // Convert minimap point back to world coordinates
        let worldX = graphCenter.x + (point.x - minimapSize / 2) / scale
        let worldY = graphCenter.y + (point.y - minimapSize / 2) / scale

        // Set viewport offset so this world point is centered
        let mainViewW: CGFloat = 800
        let mainViewH: CGFloat = 600
        let newOffset = CGPoint(
            x: mainViewW / 2 - worldX * viewportZoom,
            y: mainViewH / 2 - worldY * viewportZoom
        )

        onNavigate(newOffset)
    }

    // MARK: - Helpers

    private func nodeIndex(_ id: UUID) -> Int? {
        nodes.firstIndex(where: { $0.id == id })
    }

    private func minimapNodeColor(_ node: ForceDirectedLayout.Node) -> Color {
        switch colorMode {
        case .para:
            switch node.cachedPARA {
            case .inbox: return .gray
            case .project: return .blue
            case .area: return .green
            case .resource: return .orange
            case .archive: return .secondary
            }
        case .noteType:
            switch node.cachedNoteType {
            case .fleeting: return .yellow
            case .literature: return .cyan
            case .permanent: return .purple
            }
        case .code:
            switch node.cachedCODEStage {
            case .captured: return .red.opacity(0.8)
            case .organized: return .orange
            case .distilled: return .green
            case .expressed: return .blue
            }
        case .custom:
            return .secondary
        }
    }
}
