import SwiftUI

struct QuickCapturePanel: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.managedObjectContext) private var context
    @State private var title: String = ""
    @State private var content: String = ""

    var body: some View {
        VStack(spacing: 16) {
            // Header
            HStack {
                Image(systemName: "bolt.fill")
                    .foregroundStyle(Moros.oracle)
                Text("Quick Capture")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Moros.textMain)
                Spacer()
                Button(action: dismissPanel) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Moros.textDim)
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.escape, modifiers: [])
            }

            // Title field
            TextField("Title (optional)", text: $title)
                .textFieldStyle(.plain)
                .font(Moros.fontH3)
                .foregroundStyle(Moros.textMain)
                .padding(8)
                .background(Moros.limit02, in: Rectangle())

            // Content field
            TextEditor(text: $content)
                .font(.system(size: 13, weight: .regular, design: .monospaced))
                .foregroundStyle(Moros.textMain)
                .scrollContentBackground(.hidden)
                .padding(8)
                .background(Moros.limit02, in: Rectangle())
                .frame(minHeight: 120)

            // Actions
            HStack {
                Text("FLEETING NOTE IN INBOX")
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundStyle(Moros.textDim)
                Spacer()
                Button("Cancel", action: dismissPanel)
                    .keyboardShortcut(.escape, modifiers: [])
                    .foregroundStyle(Moros.textDim)
                Button("Capture", action: capture)
                    .keyboardShortcut(.return, modifiers: .command)
                    .buttonStyle(.borderedProminent)
                    .disabled(content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(20)
        .frame(minWidth: 440, minHeight: 280)
        .fixedSize(horizontal: true, vertical: false)
        .morosBackground(Moros.limit02)
        .overlay(Rectangle().stroke(Moros.borderLit, lineWidth: 1))
    }

    private func capture() {
        let noteTitle = title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "Quick Capture"
            : title.trimmingCharacters(in: .whitespacesAndNewlines)
        let noteContent = content.trimmingCharacters(in: .whitespacesAndNewlines)

        let service = NoteService(context: context)
        let note = service.createNote(
            title: noteTitle,
            content: noteContent,
            paraCategory: .inbox
        )
        note.noteType = .fleeting
        try? context.save()

        dismissPanel()
    }

    private func dismissPanel() {
        title = ""
        content = ""
        appState.isQuickCaptureVisible = false
    }
}
