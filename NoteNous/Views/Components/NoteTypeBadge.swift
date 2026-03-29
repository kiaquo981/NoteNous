import SwiftUI

struct NoteTypeBadge: View {
    let type: NoteType
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: type.icon)
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
        switch type {
        case .fleeting: "FLT"
        case .literature: "LIT"
        case .permanent: "PRM"
        case .structure: "STR"
        }
    }

    private var accentColor: Color {
        switch type {
        case .fleeting: Moros.ambient
        case .literature: Moros.oracle
        case .permanent: Moros.verdit
        case .structure: Moros.textSub
        }
    }
}
