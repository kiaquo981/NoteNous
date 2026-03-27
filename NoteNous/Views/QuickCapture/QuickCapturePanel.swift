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
                    .foregroundStyle(.yellow)
                Text("Quick Capture")
                    .font(.headline)
                Spacer()
                Button(action: dismiss) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.escape, modifiers: [])
            }

            // Title field
            TextField("Title (optional)", text: $title)
                .textFieldStyle(.roundedBorder)
                .font(.title3)

            // Content field
            TextEditor(text: $content)
                .font(.body.monospaced())
                .scrollContentBackground(.hidden)
                .padding(8)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
                .frame(minHeight: 120)

            // Actions
            HStack {
                Text("Fleeting note in Inbox")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Cancel", action: dismiss)
                    .keyboardShortcut(.escape, modifiers: [])
                Button("Capture", action: capture)
                    .keyboardShortcut(.return, modifiers: .command)
                    .buttonStyle(.borderedProminent)
                    .disabled(content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(20)
        .frame(minWidth: 440, minHeight: 280)
        .fixedSize(horizontal: true, vertical: false)
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

        dismiss()
    }

    private func dismiss() {
        title = ""
        content = ""
        appState.isQuickCaptureVisible = false
    }
}
