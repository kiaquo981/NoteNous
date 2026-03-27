import SwiftUI

struct NoteTypeBadge: View {
    let type: NoteType

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: type.icon)
            Text(type.label.uppercased())
        }
        .font(.system(size: 9, weight: .medium, design: .monospaced))
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(Moros.verdit.opacity(0.12), in: Rectangle())
        .foregroundStyle(Moros.verdit)
    }
}
