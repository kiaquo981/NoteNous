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
        .background(Moros.oracle.opacity(0.1), in: Rectangle())
        .overlay(Rectangle().stroke(Moros.oracle.opacity(0.25), lineWidth: 1))
        .foregroundStyle(Moros.oracle)
    }
}
