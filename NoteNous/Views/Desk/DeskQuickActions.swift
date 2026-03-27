import SwiftUI

// MARK: - Context menu for a single note card

struct DeskCardContextMenu: View {
    let note: NoteEntity
    let onEdit: () -> Void
    let onOpenInEditor: () -> Void
    let onLinkTo: () -> Void
    let onChangeColor: () -> Void
    let onChangePARA: (PARACategory) -> Void
    let onTogglePin: () -> Void
    let onArchive: () -> Void
    let onDelete: () -> Void

    var body: some View {
        Group {
            Button(action: onEdit) {
                Label("Edit Title", systemImage: "pencil")
            }

            Button(action: onOpenInEditor) {
                Label("Open in Editor", systemImage: "doc.text")
            }

            Divider()

            Button(action: onLinkTo) {
                Label("Link to...", systemImage: "link.badge.plus")
            }

            Button(action: onChangeColor) {
                Label("Change Color", systemImage: "paintpalette")
            }

            Menu("Change PARA") {
                ForEach(PARACategory.allCases) { para in
                    Button {
                        onChangePARA(para)
                    } label: {
                        Label(para.label, systemImage: para.icon)
                    }
                    .disabled(note.paraCategory == para)
                }
            }

            Divider()

            Button(action: onTogglePin) {
                Label(
                    note.isPinned ? "Unpin" : "Pin",
                    systemImage: note.isPinned ? "pin.slash" : "pin"
                )
            }

            Button(action: onArchive) {
                Label("Archive", systemImage: "archivebox")
            }

            Divider()

            Button(role: .destructive, action: onDelete) {
                Label("Delete", systemImage: "trash")
            }
        }
    }
}

// MARK: - Context menu for the canvas background

struct DeskCanvasContextMenu: View {
    let canvasPosition: CGPoint
    let onNewNote: (CGPoint) -> Void
    let onPaste: () -> Void
    let onSelectAll: () -> Void
    let onAutoLayout: () -> Void
    let onAddSection: (CGPoint) -> Void

    var body: some View {
        Group {
            Button {
                onNewNote(canvasPosition)
            } label: {
                Label("New Note Here", systemImage: "plus.rectangle")
            }

            Button {
                onAddSection(canvasPosition)
            } label: {
                Label("New Section Here", systemImage: "folder.badge.plus")
            }

            Divider()

            Button(action: onPaste) {
                Label("Paste", systemImage: "doc.on.clipboard")
            }

            Button(action: onSelectAll) {
                Label("Select All", systemImage: "checkmark.circle")
            }

            Divider()

            Button(action: onAutoLayout) {
                Label("Auto-layout", systemImage: "square.grid.3x3")
            }
        }
    }
}

// MARK: - Keyboard shortcut handler

struct DeskKeyboardShortcuts: ViewModifier {
    let onDelete: () -> Void
    let onSelectAll: () -> Void
    let onCreateSection: () -> Void
    let onToggleCardMode: () -> Void
    let onZoomIn: () -> Void
    let onZoomOut: () -> Void
    let onZoomToFit: () -> Void
    let onEscape: () -> Void

    func body(content: Content) -> some View {
        content
            .background {
                // Hidden buttons to capture keyboard shortcuts (macOS 14 compatible)
                VStack(spacing: 0) {
                    Button("") { onDelete() }
                        .keyboardShortcut(.delete, modifiers: [])
                    Button("") { onSelectAll() }
                        .keyboardShortcut("a", modifiers: .command)
                    Button("") { onCreateSection() }
                        .keyboardShortcut("g", modifiers: .command)
                    Button("") { onZoomIn() }
                        .keyboardShortcut("=", modifiers: .command)
                    Button("") { onZoomOut() }
                        .keyboardShortcut("-", modifiers: .command)
                    Button("") { onZoomToFit() }
                        .keyboardShortcut("0", modifiers: .command)
                    Button("") { onEscape() }
                        .keyboardShortcut(.escape, modifiers: [])
                }
                .frame(width: 0, height: 0)
                .opacity(0)
            }
    }
}

extension View {
    func deskKeyboardShortcuts(
        onDelete: @escaping () -> Void,
        onSelectAll: @escaping () -> Void,
        onCreateSection: @escaping () -> Void,
        onToggleCardMode: @escaping () -> Void,
        onZoomIn: @escaping () -> Void,
        onZoomOut: @escaping () -> Void,
        onZoomToFit: @escaping () -> Void,
        onEscape: @escaping () -> Void
    ) -> some View {
        modifier(DeskKeyboardShortcuts(
            onDelete: onDelete,
            onSelectAll: onSelectAll,
            onCreateSection: onCreateSection,
            onToggleCardMode: onToggleCardMode,
            onZoomIn: onZoomIn,
            onZoomOut: onZoomOut,
            onZoomToFit: onZoomToFit,
            onEscape: onEscape
        ))
    }
}
