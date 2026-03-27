import SwiftUI

struct MenuBarCaptureView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.managedObjectContext) private var context
    @State private var title: String = ""
    @State private var content: String = ""
    @State private var didCapture: Bool = false

    var body: some View {
        VStack(spacing: 12) {
            // Header
            HStack {
                Image(systemName: "bolt.fill")
                    .foregroundStyle(.yellow)
                Text("NoteNous Capture")
                    .font(.headline)
                Spacer()
            }

            // Title
            TextField("Title (optional)", text: $title)
                .textFieldStyle(.roundedBorder)

            // Content
            TextEditor(text: $content)
                .font(.body.monospaced())
                .scrollContentBackground(.hidden)
                .padding(6)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
                .frame(minHeight: 80, maxHeight: 120)

            // Footer
            HStack {
                if didCapture {
                    Label("Captured!", systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.green)
                } else {
                    Text("\u{2318}\u{21A9} to capture")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Capture") { capture() }
                    .keyboardShortcut(.return, modifiers: .command)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                              && content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(16)
        .frame(width: 320)
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

        title = ""
        content = ""
        didCapture = true

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            didCapture = false
        }
    }
}
