import SwiftUI

// MARK: - Graph Legend

struct GraphLegend: View {
    let colorMode: GraphColorMode

    @State private var isExpanded: Bool = true

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header with collapse toggle
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "list.bullet.rectangle")
                        .font(.caption)
                    Text("Legend")
                        .font(.caption)
                        .fontWeight(.medium)
                    Spacer()
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)

            if isExpanded {
                Divider()

                VStack(alignment: .leading, spacing: 10) {
                    // Node colors section
                    nodeColorLegend

                    Divider()

                    // Edge types section
                    edgeTypeLegend

                    Divider()

                    // Size meaning
                    sizeLegend
                }
                .padding(10)
            }
        }
        .frame(width: 200)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(.separator, lineWidth: 0.5)
        )
    }

    // MARK: - Node Color Legend

    @ViewBuilder
    private var nodeColorLegend: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Node Colors (\(colorMode.label))")
                .font(.caption2)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)

            switch colorMode {
            case .para:
                legendRow(color: .gray, label: "Inbox")
                legendRow(color: .blue, label: "Projects")
                legendRow(color: .green, label: "Areas")
                legendRow(color: .orange, label: "Resources")
                legendRow(color: .secondary, label: "Archive")

            case .noteType:
                legendRow(color: .yellow, label: "Fleeting")
                legendRow(color: .cyan, label: "Literature")
                legendRow(color: .purple, label: "Permanent")

            case .code:
                legendRow(color: .red.opacity(0.8), label: "Captured")
                legendRow(color: .orange, label: "Organized")
                legendRow(color: .green, label: "Distilled")
                legendRow(color: .blue, label: "Expressed")

            case .custom:
                Text("Using note custom colors")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .italic()
            }
        }
    }

    // MARK: - Edge Type Legend

    private var edgeTypeLegend: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Edge Types")
                .font(.caption2)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)

            edgeLegendRow(color: .gray, label: "Reference", dashed: false)
            edgeLegendRow(color: .green, label: "Supports", dashed: false)
            edgeLegendRow(color: .red, label: "Contradicts", dashed: false)
            edgeLegendRow(color: .blue, label: "Extends", dashed: false)
            edgeLegendRow(color: .orange, label: "Example", dashed: false)

            HStack(spacing: 6) {
                dashedLine(color: .secondary)
                    .frame(width: 12, height: 1)
                Text("Unconfirmed / AI-suggested")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    // MARK: - Size Legend

    private var sizeLegend: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Node Size")
                .font(.caption2)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                Circle()
                    .fill(.secondary.opacity(0.5))
                    .frame(width: 10, height: 10)
                Text("Few links")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)

                Spacer()

                Circle()
                    .fill(.secondary.opacity(0.5))
                    .frame(width: 22, height: 22)
                Text("Many links")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    // MARK: - Row Helpers

    private func legendRow(color: Color, label: String) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.primary)
        }
    }

    private func edgeLegendRow(color: Color, label: String, dashed: Bool) -> some View {
        HStack(spacing: 6) {
            if dashed {
                dashedLine(color: color)
                    .frame(width: 12, height: 1)
            } else {
                Rectangle()
                    .fill(color)
                    .frame(width: 12, height: 2)
                    .clipShape(Capsule())
            }
            Text(label)
                .font(.caption2)
                .foregroundStyle(.primary)
        }
    }

    private func dashedLine(color: Color) -> some View {
        GeometryReader { geo in
            Path { path in
                path.move(to: .zero)
                path.addLine(to: CGPoint(x: geo.size.width, y: 0))
            }
            .stroke(color, style: StrokeStyle(lineWidth: 1.5, dash: [3, 2]))
        }
    }
}
