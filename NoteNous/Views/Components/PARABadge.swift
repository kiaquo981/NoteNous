import SwiftUI

struct PARABadge: View {
    let category: PARACategory
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: category.icon)
            Text(shortLabel.uppercased())
        }
        .font(.system(size: 9, weight: .medium, design: .monospaced))
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .frame(height: 20)
        .background(accentColor.opacity(0.15), in: Rectangle())
        .overlay(Rectangle().stroke(accentColor.opacity(0.30), lineWidth: 1))
        .foregroundStyle(colorScheme == .dark ? accentColor : accentColor.opacity(0.85))
    }

    private var shortLabel: String {
        switch category {
        case .inbox: "IN"
        case .project: "PRJ"
        case .area: "AREA"
        case .resource: "RES"
        case .archive: "ARC"
        }
    }

    private var accentColor: Color {
        switch category {
        case .inbox: Moros.ambient
        case .project: Moros.oracle
        case .area: Moros.verdit
        case .resource: Moros.ambient
        case .archive: Moros.textDim
        }
    }
}
