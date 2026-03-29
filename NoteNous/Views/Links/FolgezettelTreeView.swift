import SwiftUI
import CoreData

struct FolgezettelTreeView: View {
    let rootZettelId: String

    @Environment(\.managedObjectContext) private var context
    @EnvironmentObject var appState: AppState

    @State private var treeNodes: [TreeNode] = []
    @State private var expandedNodes: Set<String> = []
    @State private var isLoading = true

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            headerView
            Rectangle().fill(Moros.border).frame(height: 1)

            if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if treeNodes.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(treeNodes, id: \.zettelId) { node in
                            FolgezettelTreeNodeView(
                                node: node,
                                isExpanded: expandedNodes.contains(node.zettelId),
                                onToggleExpand: { toggleExpand(node.zettelId) },
                                onNavigate: { navigateTo(zettelId: node.zettelId) },
                                onAddContinuation: { addContinuation(from: node.zettelId) },
                                onAddBranch: { addBranch(from: node.zettelId) }
                            )
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }

        .onAppear { buildTree() }
        .onChange(of: rootZettelId) { buildTree() }
    }

    // MARK: - Header

    private var headerView: some View {
        HStack {
            Image(systemName: "list.triangle")
                .foregroundStyle(Moros.oracle)
            Text("Folgezettel Tree")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Moros.textMain)
            Spacer()

            Button {
                withAnimation { expandAll() }
            } label: {
                Image(systemName: "arrow.down.right.and.arrow.up.left")
                    .font(.caption)
                    .foregroundStyle(Moros.textSub)
            }
            .buttonStyle(.plain)
            .help("Expand all")

            Button {
                withAnimation { collapseAll() }
            } label: {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .font(.caption)
                    .foregroundStyle(Moros.textSub)
            }
            .buttonStyle(.plain)
            .help("Collapse all")
        }
        .padding()
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "list.triangle")
                .font(.title)
                .foregroundStyle(Moros.textGhost)
            Text("No Folgezettel structure")
                .font(Moros.fontBody)
                .foregroundStyle(Moros.textDim)
            Text("Add continuations or branches to build the tree.")
                .font(Moros.fontCaption)
                .foregroundStyle(Moros.textDim)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    // MARK: - Tree Building

    private func buildTree() {
        isLoading = true

        let service = FolgezettelService(context: context)

        var currentId = rootZettelId
        while let parent = service.parentId(of: currentId) {
            currentId = parent
        }

        let sequence = service.sequenceFrom(id: currentId, in: context)
        treeNodes = sequence.map { zettelId in
            let note = service.findNote(byFolgezettelId: zettelId, in: context)
            let depth = service.depth(of: zettelId)
            let children = service.childrenIds(of: zettelId, in: context)
            let isCurrentNote = zettelId == rootZettelId

            return TreeNode(
                zettelId: zettelId,
                title: note?.title ?? "Untitled",
                noteType: note?.noteType ?? .fleeting,
                depth: depth,
                hasChildren: !children.isEmpty,
                isCurrentNote: isCurrentNote
            )
        }

        var pathId = rootZettelId
        expandedNodes.insert(pathId)
        while let parent = service.parentId(of: pathId) {
            expandedNodes.insert(parent)
            pathId = parent
        }

        isLoading = false
    }

    // MARK: - Actions

    private func toggleExpand(_ zettelId: String) {
        if expandedNodes.contains(zettelId) {
            expandedNodes.remove(zettelId)
        } else {
            expandedNodes.insert(zettelId)
        }
    }

    private func expandAll() {
        expandedNodes = Set(treeNodes.filter(\.hasChildren).map(\.zettelId))
    }

    private func collapseAll() {
        expandedNodes.removeAll()
    }

    private func navigateTo(zettelId: String) {
        let service = FolgezettelService(context: context)
        if let note = service.findNote(byFolgezettelId: zettelId, in: context) {
            appState.selectedNote = note
        }
    }

    private func addContinuation(from zettelId: String) {
        let fzService = FolgezettelService(context: context)
        let newId = fzService.generateContinuation(of: zettelId)

        let note = NoteEntity(context: context)
        note.id = UUID()
        note.zettelId = newId
        note.title = ""
        note.content = ""
        note.contentPlainText = ""
        note.paraCategory = .inbox
        note.codeStage = .captured
        note.noteType = .fleeting
        note.aiClassified = false
        note.aiConfidence = 0
        note.isPinned = false
        note.isArchived = false
        note.createdAt = Date()
        note.updatedAt = Date()

        try? context.save()
        appState.selectedNote = note
        buildTree()
    }

    private func addBranch(from zettelId: String) {
        let fzService = FolgezettelService(context: context)
        let newId = fzService.generateBranch(from: zettelId)

        let note = NoteEntity(context: context)
        note.id = UUID()
        note.zettelId = newId
        note.title = ""
        note.content = ""
        note.contentPlainText = ""
        note.paraCategory = .inbox
        note.codeStage = .captured
        note.noteType = .fleeting
        note.aiClassified = false
        note.aiConfidence = 0
        note.isPinned = false
        note.isArchived = false
        note.createdAt = Date()
        note.updatedAt = Date()

        try? context.save()
        appState.selectedNote = note
        buildTree()
    }
}

// MARK: - TreeNode Model

struct TreeNode: Identifiable {
    let zettelId: String
    let title: String
    let noteType: NoteType
    let depth: Int
    let hasChildren: Bool
    let isCurrentNote: Bool

    var id: String { zettelId }
}

// MARK: - FolgezettelTreeNodeView

struct FolgezettelTreeNodeView: View {
    let node: TreeNode
    let isExpanded: Bool
    var onToggleExpand: () -> Void
    var onNavigate: () -> Void
    var onAddContinuation: () -> Void
    var onAddBranch: () -> Void

    @State private var isHovered = false

    private var indentation: CGFloat {
        CGFloat(node.depth - 1) * 20
    }

    var body: some View {
        HStack(spacing: 6) {
            // Expand/collapse toggle
            if node.hasChildren {
                Button(action: onToggleExpand) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(Moros.fontMicro)
                        .frame(width: 16, height: 16)
                        .foregroundStyle(Moros.textDim)
                }
                .buttonStyle(.plain)
            } else {
                Color.clear
                    .frame(width: 16, height: 16)
            }

            // Depth indicator dot
            depthIndicator

            // Zettel ID
            Text(node.zettelId)
                .font(.system(size: 10, weight: node.isCurrentNote ? .bold : .regular, design: .monospaced))
                .foregroundStyle(node.isCurrentNote ? Moros.textMain : Moros.textDim)

            // Title
            Button(action: onNavigate) {
                Text(node.title.isEmpty ? "Untitled" : node.title)
                    .font(Moros.fontBody)
                    .lineLimit(1)
                    .foregroundStyle(node.isCurrentNote ? Moros.textMain : Moros.textSub)
            }
            .buttonStyle(.plain)

            Spacer()

            // Actions (visible on hover)
            if isHovered {
                HStack(spacing: 4) {
                    Button(action: onAddContinuation) {
                        Image(systemName: "arrow.right")
                            .font(Moros.fontMicro)
                    }
                    .buttonStyle(.plain)
                    .help("Add continuation (sibling)")

                    Button(action: onAddBranch) {
                        Image(systemName: "arrow.turn.down.right")
                            .font(Moros.fontMicro)
                    }
                    .buttonStyle(.plain)
                    .help("Add branch (child)")
                }
                .foregroundStyle(Moros.oracle)
            }
        }
        .padding(.leading, indentation)
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
        .background(
            node.isCurrentNote
                ? Moros.oracle.opacity(0.08)
                : (isHovered ? Moros.limit03 : .clear)
        )
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
    }

    @ViewBuilder
    private var depthIndicator: some View {
        let colors: [Color] = [Moros.oracle, Moros.verdit, Moros.ambient, Moros.signal, Moros.verdit.opacity(0.6), Moros.oracle.opacity(0.6)]
        let colorIndex = (node.depth - 1) % colors.count

        Circle()
            .fill(colors[colorIndex])
            .frame(width: 6, height: 6)
    }
}
