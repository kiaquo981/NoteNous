import SwiftUI

struct PARABadge: View {
    let category: PARACategory

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: category.icon)
            Text(category.label)
        }
        .font(.caption2)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(backgroundColor, in: Capsule())
        .foregroundStyle(foregroundColor)
    }

    private var backgroundColor: Color {
        switch category {
        case .inbox: .gray.opacity(0.15)
        case .project: .blue.opacity(0.15)
        case .area: .green.opacity(0.15)
        case .resource: .orange.opacity(0.15)
        case .archive: .secondary.opacity(0.1)
        }
    }

    private var foregroundColor: Color {
        switch category {
        case .inbox: .gray
        case .project: .blue
        case .area: .green
        case .resource: .orange
        case .archive: .secondary
        }
    }
}
