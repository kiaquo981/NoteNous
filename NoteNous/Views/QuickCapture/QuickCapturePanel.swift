import SwiftUI

struct QuickCapturePanel: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.managedObjectContext) private var context
    @State private var title: String = ""
    @State private var content: String = ""
    @State private var selectedType: NoteType = .fleeting
    @State private var sourceTitle: String = ""
    @State private var showCapturedConfirmation: Bool = false

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

                // Note type selector
                HStack(spacing: 2) {
                    noteTypeButton(.fleeting, icon: "bolt.fill", color: Moros.ambient)
                    noteTypeButton(.literature, icon: "book.fill", color: Moros.oracle)
                    noteTypeButton(.permanent, icon: "diamond.fill", color: Moros.verdit)
                }

                Spacer().frame(width: 12)

                Button(action: dismissPanel) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Moros.textDim)
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.escape, modifiers: [])
            }

            // Source field (literature only)
            if selectedType == .literature {
                TextField("Source (book, article, video...)", text: $sourceTitle)
                    .textFieldStyle(.plain)
                    .font(Moros.fontBody)
                    .foregroundStyle(Moros.textMain)
                    .padding(8)
                    .background(Moros.oracle.opacity(0.06), in: Rectangle())
                    .overlay(Rectangle().stroke(Moros.oracle.opacity(0.2), lineWidth: 1))
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
        
                .padding(8)
                .background(Moros.limit02, in: Rectangle())
                .frame(minHeight: 120)

            // Actions
            HStack {
                if showCapturedConfirmation {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(Moros.verdit)
                        Text("Captured! Process it in the Fleeting Queue.")
                            .font(Moros.fontCaption)
                            .foregroundStyle(Moros.verdit)
                    }
                } else {
                    Text(typeLabel)
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundStyle(Moros.textDim)
                }
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

        .overlay(Rectangle().stroke(Moros.borderLit, lineWidth: 1))
    }

    private func noteTypeButton(_ type: NoteType, icon: String, color: Color) -> some View {
        Button {
            selectedType = type
        } label: {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundStyle(selectedType == type ? color : Moros.textDim)
                .padding(6)
                .background(selectedType == type ? color.opacity(0.12) : .clear, in: Rectangle())
        }
        .buttonStyle(.plain)
        .help(type.label)
    }

    private var typeLabel: String {
        switch selectedType {
        case .fleeting: "FLEETING NOTE IN INBOX"
        case .literature: "LITERATURE NOTE"
        case .permanent: "PERMANENT NOTE"
        case .structure: "STRUCTURE NOTE"
        }
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
            paraCategory: selectedType == .fleeting ? .inbox : .resource
        )
        note.noteType = selectedType

        // Apply source for literature notes
        if selectedType == .literature && !sourceTitle.isEmpty {
            note.sourceTitle = sourceTitle
            let srcService = SourceService()
            srcService.addSource(title: sourceTitle, dateConsumed: Date())
        }

        try? context.save()

        // Show confirmation briefly then dismiss
        showCapturedConfirmation = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            dismissPanel()
        }
    }

    private func dismissPanel() {
        title = ""
        content = ""
        sourceTitle = ""
        selectedType = .fleeting
        showCapturedConfirmation = false
        appState.isQuickCaptureVisible = false
    }
}
