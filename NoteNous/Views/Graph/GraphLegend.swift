import SwiftUI

// MARK: - Graph Legend

struct GraphLegend: View {
    let colorMode: GraphColorMode

    @State private var isExpanded: Bool = true

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header with collapse toggle
            Button {
                withAnimation(.easeInOut(duration: Moros.animFast)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "list.bullet.rectangle")
                        .font(Moros.fontCaption)
                    Text("LEGEND")
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                    Spacer()
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(Moros.fontMicro)
                        .foregroundStyle(Moros.textDim)
                }
                .foregroundStyle(Moros.textSub)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)

            if isExpanded {
                Rectangle().fill(Moros.border).frame(height: 1)

                VStack(alignment: .leading, spacing: 10) {
                    // Node colors section
                    nodeColorLegend

                    Rectangle().fill(Moros.border).frame(height: 1)

                    // Edge types section
                    edgeTypeLegend

                    Rectangle().fill(Moros.border).frame(height: 1)

                    // Size meaning
                    sizeLegend
                }
                .padding(10)
            }
        }
        .frame(width: 200)
        .background(Moros.limit02)
        .clipShape(Rectangle())
        .overlay(
            Rectangle()
                .stroke(Moros.borderLit, lineWidth: 1)
        )
    }

    // MARK: - Node Color Legend

    @ViewBuilder
    private var nodeColorLegend: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("NODE COLORS (\(colorMode.label.uppercased()))")
                .font(.system(size: 8, weight: .medium, design: .monospaced))
                .foregroundStyle(Moros.textDim)

            switch colorMode {
            case .para:
                legendRow(color: Moros.ambient, label: "Inbox")
                legendRow(color: Moros.oracle, label: "Projects")
                legendRow(color: Moros.verdit, label: "Areas")
                legendRow(color: Moros.ambient.opacity(0.7), label: "Resources")
                legendRow(color: Moros.textDim, label: "Archive")

            case .noteType:
                legendRow(color: Moros.ambient, label: "Fleeting")
                legendRow(color: Moros.oracle, label: "Literature")
                legendRow(color: Moros.verdit, label: "Permanent")

            case .code:
                legendRow(color: Moros.signal, label: "Captured")
                legendRow(color: Moros.ambient, label: "Organized")
                legendRow(color: Moros.verdit, label: "Distilled")
                legendRow(color: Moros.oracle, label: "Expressed")

            case .custom:
                Text("Using note custom colors")
                    .font(Moros.fontMicro)
                    .foregroundStyle(Moros.textDim)
                    .italic()
            }
        }
    }

    // MARK: - Edge Type Legend

    private var edgeTypeLegend: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("EDGE TYPES")
                .font(.system(size: 8, weight: .medium, design: .monospaced))
                .foregroundStyle(Moros.textDim)

            edgeLegendRow(color: Moros.ambient, label: "Reference", dashed: false)
            edgeLegendRow(color: Moros.verdit, label: "Supports", dashed: false)
            edgeLegendRow(color: Moros.signal, label: "Contradicts", dashed: false)
            edgeLegendRow(color: Moros.oracle, label: "Extends", dashed: false)
            edgeLegendRow(color: Moros.ambient.opacity(0.7), label: "Example", dashed: false)

            HStack(spacing: 6) {
                dashedLine(color: Moros.textDim)
                    .frame(width: 12, height: 1)
                Text("Unconfirmed / AI-suggested")
                    .font(Moros.fontMicro)
                    .foregroundStyle(Moros.textDim)
            }
        }
    }

    // MARK: - Size Legend

    private var sizeLegend: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("NODE SIZE")
                .font(.system(size: 8, weight: .medium, design: .monospaced))
                .foregroundStyle(Moros.textDim)

            HStack(spacing: 8) {
                Circle()
                    .fill(Moros.textDim)
                    .frame(width: 10, height: 10)
                Text("Few links")
                    .font(Moros.fontMicro)
                    .foregroundStyle(Moros.textDim)

                Spacer()

                Circle()
                    .fill(Moros.textDim)
                    .frame(width: 22, height: 22)
                Text("Many links")
                    .font(Moros.fontMicro)
                    .foregroundStyle(Moros.textDim)
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
                .font(Moros.fontMicro)
                .foregroundStyle(Moros.textSub)
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
            }
            Text(label)
                .font(Moros.fontMicro)
                .foregroundStyle(Moros.textSub)
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
