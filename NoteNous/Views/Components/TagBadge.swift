import SwiftUI

struct TagBadge: View {
    let name: String
    var onRemove: (() -> Void)?

    var body: some View {
        HStack(spacing: 2) {
            Text("#\(name)")
                .font(Moros.fontMonoSmall)
            if let onRemove {
                Button(action: onRemove) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 8))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(
            Rectangle()
                .fill(Color.clear)
                .overlay(Rectangle().stroke(Moros.borderLit, lineWidth: 1))
        )
        .foregroundStyle(Moros.ambient)
    }
}
