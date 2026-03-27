import SwiftUI

struct NoteTypeBadge: View {
    let type: NoteType

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: type.icon)
            Text(type.label)
        }
        .font(.caption2)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(.teal.opacity(0.12), in: Capsule())
        .foregroundStyle(.teal)
    }
}
