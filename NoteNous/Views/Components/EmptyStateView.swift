import SwiftUI

struct EmptyStateView: View {
    let icon: String
    let title: String
    let subtitle: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 48))
                .foregroundStyle(Moros.ambient)
            Text(title)
                .font(Moros.fontH3)
                .foregroundStyle(Moros.textDim)
            Text(subtitle)
                .font(Moros.fontBody)
                .foregroundStyle(Moros.textDim)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .morosBackground()
    }
}
