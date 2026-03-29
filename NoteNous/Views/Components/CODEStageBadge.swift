import SwiftUI

struct CODEStageBadge: View {
    let stage: CODEStage
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: stage.icon)
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
        switch stage {
        case .captured: "CAP"
        case .organized: "ORG"
        case .distilled: "DST"
        case .expressed: "EXP"
        }
    }

    private var accentColor: Color {
        switch stage {
        case .captured: Moros.ambient
        case .organized: Moros.oracle
        case .distilled: Moros.verdit
        case .expressed: Moros.oracle
        }
    }
}
