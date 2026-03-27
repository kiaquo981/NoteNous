import SwiftUI
import CoreData

struct SequenceNavigator: View {
    let zettelId: String

    @Environment(\.managedObjectContext) private var context
    @EnvironmentObject var appState: AppState

    @State private var previousSibling: String?
    @State private var nextSibling: String?
    @State private var parentId: String?
    @State private var firstChild: String?
    @State private var depth: Int = 1

    var body: some View {
        HStack(spacing: 2) {
            // Parent navigation
            navigationButton(
                icon: "arrow.up",
                targetId: parentId,
                help: parentId.map { "Parent: \($0)" } ?? "No parent (root note)"
            )

            Rectangle()
                .fill(Moros.border)
                .frame(width: 1, height: 16)
                .padding(.horizontal, 2)

            // Previous sibling
            navigationButton(
                icon: "arrow.left",
                targetId: previousSibling,
                help: previousSibling.map { "Previous: \($0)" } ?? "No previous sibling"
            )

            // Current ID
            Text(zettelId)
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundStyle(Moros.textMain)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Moros.limit03, in: Rectangle())
                .help("Depth: \(depth)")

            // Next sibling
            navigationButton(
                icon: "arrow.right",
                targetId: nextSibling,
                help: nextSibling.map { "Next: \($0)" } ?? "No next sibling"
            )

            Rectangle()
                .fill(Moros.border)
                .frame(width: 1, height: 16)
                .padding(.horizontal, 2)

            // First child navigation
            navigationButton(
                icon: "arrow.down",
                targetId: firstChild,
                help: firstChild.map { "Child: \($0)" } ?? "No children"
            )
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Moros.limit02, in: Rectangle())
        .onAppear { loadNavigation() }
        .onChange(of: zettelId) { loadNavigation() }
    }

    // MARK: - Navigation Button

    private func navigationButton(icon: String, targetId: String?, help: String) -> some View {
        Button {
            if let targetId {
                navigateTo(zettelId: targetId)
            }
        } label: {
            Image(systemName: icon)
                .font(.caption)
                .frame(width: 24, height: 24)
                .foregroundStyle(targetId != nil ? Moros.oracle : Moros.textGhost)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(targetId == nil)
        .help(help)
    }

    // MARK: - Data Loading

    private func loadNavigation() {
        let service = FolgezettelService(context: context)

        previousSibling = service.previousSibling(of: zettelId)
        nextSibling = service.nextSibling(of: zettelId)
        parentId = service.parentId(of: zettelId)
        firstChild = service.firstChild(of: zettelId)
        depth = service.depth(of: zettelId)
    }

    // MARK: - Navigation

    private func navigateTo(zettelId: String) {
        let service = FolgezettelService(context: context)
        if let note = service.findNote(byFolgezettelId: zettelId, in: context) {
            appState.selectedNote = note
        }
    }
}
