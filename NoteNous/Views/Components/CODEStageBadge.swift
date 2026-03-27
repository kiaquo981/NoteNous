import SwiftUI

struct CODEStageBadge: View {
    let stage: CODEStage

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: stage.icon)
            Text(stage.label.uppercased())
        }
        .font(.system(size: 9, weight: .medium, design: .monospaced))
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(Moros.oracle.opacity(0.12), in: Rectangle())
        .foregroundStyle(Moros.oracle)
    }
}
