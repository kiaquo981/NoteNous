import SwiftUI

struct TagBadge: View {
    let name: String
    var onRemove: (() -> Void)?

    var body: some View {
        HStack(spacing: 2) {
            Text("#\(name)")
                .font(.caption)
            if let onRemove {
                Button(action: onRemove) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.caption2)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(.blue.opacity(0.1), in: Capsule())
        .foregroundStyle(.blue)
    }
}
