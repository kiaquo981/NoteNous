import SwiftUI

struct CODEStageBadge: View {
    let stage: CODEStage

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: stage.icon)
            Text(stage.label)
        }
        .font(.caption2)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(.purple.opacity(0.12), in: Capsule())
        .foregroundStyle(.purple)
    }
}
