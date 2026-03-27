import SwiftUI

struct PARABadge: View {
    let category: PARACategory

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: category.icon)
            Text(category.label.uppercased())
        }
        .font(.system(size: 9, weight: .medium, design: .monospaced))
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(backgroundColor, in: Rectangle())
        .foregroundStyle(foregroundColor)
    }

    private var backgroundColor: Color {
        switch category {
        case .inbox: Moros.ambient.opacity(0.12)
        case .project: Moros.oracle.opacity(0.12)
        case .area: Moros.verdit.opacity(0.12)
        case .resource: Moros.ambient.opacity(0.12)
        case .archive: Moros.textGhost.opacity(0.5)
        }
    }

    private var foregroundColor: Color {
        switch category {
        case .inbox: Moros.ambient
        case .project: Moros.oracle
        case .area: Moros.verdit
        case .resource: Moros.ambient
        case .archive: Moros.textDim
        }
    }
}
