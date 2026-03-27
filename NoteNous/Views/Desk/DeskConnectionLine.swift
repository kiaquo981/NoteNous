import SwiftUI

// MARK: - Connection line between two notes on the canvas

struct DeskConnectionLine: View {
    let link: NoteLinkEntity
    let sourceCenter: CGPoint
    let targetCenter: CGPoint
    let zoomLevel: CGFloat

    @State private var isHovered: Bool = false

    private var linkType: LinkType {
        link.linkType
    }

    var body: some View {
        ZStack {
            connectionPath
                .stroke(
                    lineColor,
                    style: StrokeStyle(
                        lineWidth: lineWidth,
                        lineCap: .round,
                        lineJoin: .round,
                        dash: dashPattern
                    )
                )

            arrowHead

            if isHovered {
                tooltip
            }
        }
        .contentShape(connectionPath.stroke(style: StrokeStyle(lineWidth: 12)))
        .onHover { isHovered = $0 }
    }

    // MARK: - Path

    private var connectionPath: Path {
        Path { path in
            path.move(to: sourceCenter)

            let dx = targetCenter.x - sourceCenter.x
            let dy = targetCenter.y - sourceCenter.y
            let distance = hypot(dx, dy)

            // Use a cubic bezier with control points offset perpendicular to the line
            // This creates a gentle curve that is easier to visually trace
            let curvature: CGFloat = min(distance * 0.3, 80) * zoomLevel
            let midX = (sourceCenter.x + targetCenter.x) / 2
            let midY = (sourceCenter.y + targetCenter.y) / 2

            // Offset control points perpendicular to the midpoint
            let angle = atan2(dy, dx)
            let perpX = -sin(angle) * curvature * 0.3
            let perpY = cos(angle) * curvature * 0.3

            let cp1 = CGPoint(x: midX + perpX, y: midY + perpY)

            path.addQuadCurve(to: targetCenter, control: cp1)
        }
    }

    // MARK: - Arrow head

    private var arrowHead: some View {
        let dx = targetCenter.x - sourceCenter.x
        let dy = targetCenter.y - sourceCenter.y
        let angle = atan2(dy, dx)
        let arrowSize: CGFloat = 8 * zoomLevel

        return Path { path in
            let tip = targetCenter
            let left = CGPoint(
                x: tip.x - arrowSize * cos(angle - .pi / 6),
                y: tip.y - arrowSize * sin(angle - .pi / 6)
            )
            let right = CGPoint(
                x: tip.x - arrowSize * cos(angle + .pi / 6),
                y: tip.y - arrowSize * sin(angle + .pi / 6)
            )
            path.move(to: tip)
            path.addLine(to: left)
            path.move(to: tip)
            path.addLine(to: right)
        }
        .stroke(lineColor, lineWidth: max(1.5, 2 * zoomLevel))
    }

    // MARK: - Tooltip

    private var tooltip: some View {
        let midX = (sourceCenter.x + targetCenter.x) / 2
        let midY = (sourceCenter.y + targetCenter.y) / 2

        return VStack(spacing: 2) {
            Text(linkType.label)
                .font(.system(size: 11, weight: .semibold))
            if let context = link.context, !context.isEmpty {
                Text(context)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Text("Strength: \(Int(link.strength * 100))%")
                .font(.system(size: 9))
                .foregroundStyle(.tertiary)
        }
        .padding(8)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 6))
        .position(x: midX, y: midY - 30)
    }

    // MARK: - Style helpers

    private var lineColor: Color {
        switch linkType {
        case .reference:  .gray
        case .supports:   .green
        case .contradicts: .red
        case .extends:    .blue
        case .example:    .orange
        }
    }

    private var dashPattern: [CGFloat] {
        switch linkType {
        case .reference:   []
        case .supports:    []
        case .contradicts: [6, 4]
        case .extends:     [10, 4]
        case .example:     [3, 3]
        }
    }

    private var lineWidth: CGFloat {
        let base: CGFloat = 1.5 + CGFloat(link.strength) * 1.5
        return max(1, base * zoomLevel)
    }
}

// MARK: - In-progress link creation line

struct DeskLinkCreationLine: View {
    let start: CGPoint
    let end: CGPoint
    let zoomLevel: CGFloat

    var body: some View {
        Path { path in
            path.move(to: start)
            path.addLine(to: end)
        }
        .stroke(
            Color.accentColor.opacity(0.6),
            style: StrokeStyle(
                lineWidth: max(1.5, 2 * zoomLevel),
                lineCap: .round,
                dash: [6, 4]
            )
        )
    }
}
