import SwiftUI
import CoreData

/// Specialized literature note creator following the Holiday/Greene reading workflow.
/// Source picker, waiting period status, "write in YOUR words" enforcement.
struct LiteratureNoteSheet: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.managedObjectContext) private var context
    @Environment(\.dismiss) private var dismiss

    @StateObject private var sourceService = SourceService()

    // Optionally pre-fill from an existing fleeting note
    var existingNote: NoteEntity?

    @State private var selectedSource: Source?
    @State private var showNewSourceForm: Bool = false
    @State private var newSourceTitle: String = ""
    @State private var newSourceAuthor: String = ""
    @State private var newSourceType: SourceType = .book

    @State private var title: String = ""
    @State private var content: String = ""
    @State private var pageReference: String = ""

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Literature Note")
                        .font(Moros.fontH2)
                        .foregroundStyle(Moros.textMain)
                    Text("From a source, in your own words")
                        .font(Moros.fontCaption)
                        .foregroundStyle(Moros.oracle)
                }
                Spacer()
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Moros.textDim)
                }
                .buttonStyle(.plain)
            }
            .padding()

            Rectangle().fill(Moros.border).frame(height: 1)

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Source Selection
                    sourceSection

                    Rectangle().fill(Moros.border).frame(height: 1)

                    // Reminder
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.bubble")
                            .foregroundStyle(Moros.oracle)
                        Text("Write in YOUR words, not the author's. If you can't rephrase it, you don't understand it yet.")
                            .font(Moros.fontSmall)
                            .foregroundStyle(Moros.textSub)
                    }
                    .padding(10)
                    .background(Moros.oracle.opacity(0.06), in: Rectangle())

                    // Page reference
                    VStack(alignment: .leading, spacing: 4) {
                        Text("PAGE / CHAPTER")
                            .font(.system(size: 9, weight: .medium, design: .monospaced))
                            .foregroundStyle(Moros.textDim)
                        TextField("e.g., p. 42, Chapter 3", text: $pageReference)
                            .textFieldStyle(.plain)
                            .font(Moros.fontBody)
                            .foregroundStyle(Moros.textMain)
                            .padding(8)
                            .background(Moros.limit02, in: Rectangle())
                    }

                    // Title
                    VStack(alignment: .leading, spacing: 4) {
                        Text("KEY INSIGHT (TITLE)")
                            .font(.system(size: 9, weight: .medium, design: .monospaced))
                            .foregroundStyle(Moros.textDim)
                        TextField("The main takeaway in one sentence", text: $title)
                            .textFieldStyle(.plain)
                            .font(.system(size: 18, weight: .light))
                            .foregroundStyle(Moros.textMain)
                            .padding(10)
                            .background(Moros.limit02, in: Rectangle())
                    }

                    // Content
                    VStack(alignment: .leading, spacing: 4) {
                        Text("YOUR NOTES")
                            .font(.system(size: 9, weight: .medium, design: .monospaced))
                            .foregroundStyle(Moros.textDim)
                        TextEditor(text: $content)
                            .font(.system(size: 13, weight: .regular, design: .monospaced))
                            .foregroundStyle(Moros.textMain)
                            .scrollContentBackground(.hidden)
                            .padding(10)
                            .background(Moros.limit02, in: Rectangle())
                            .frame(minHeight: 140)

                        let wordCount = content.split(separator: " ").filter { !$0.isEmpty }.count
                        Text("\(wordCount) words")
                            .font(Moros.fontMonoSmall)
                            .foregroundStyle(Moros.textDim)
                    }
                }
                .padding()
            }

            Rectangle().fill(Moros.border).frame(height: 1)

            // Footer
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .foregroundStyle(Moros.textSub)
                Button("Create Literature Note") {
                    createLiteratureNote()
                }
                .keyboardShortcut(.return, modifiers: .command)
                .buttonStyle(.borderedProminent)
                .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding()
        }
        .frame(minWidth: 500, minHeight: 550)
        .morosBackground(Moros.limit01)
        .preferredColorScheme(.dark)
        .onAppear {
            if let note = existingNote {
                title = note.title
                content = note.content
            }
        }
    }

    // MARK: - Source Section

    private var sourceSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("SOURCE")
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .foregroundStyle(Moros.textDim)

            if !sourceService.sources.isEmpty && !showNewSourceForm {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(sourceService.sources, id: \.id) { source in
                            Button {
                                selectedSource = source
                            } label: {
                                HStack(spacing: 10) {
                                    Image(systemName: source.sourceType.icon)
                                        .foregroundStyle(Moros.textDim)
                                        .frame(width: 20)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(source.title)
                                            .font(Moros.fontBody)
                                            .foregroundStyle(Moros.textMain)
                                        HStack(spacing: 8) {
                                            if let author = source.author {
                                                Text(author)
                                                    .font(Moros.fontCaption)
                                                    .foregroundStyle(Moros.textDim)
                                            }
                                            if let days = source.waitingPeriodDays {
                                                Text("\(days)d waiting")
                                                    .font(Moros.fontMonoSmall)
                                                    .foregroundStyle(source.isReadyToCard ? Moros.verdit : Moros.ambient)
                                            }
                                        }
                                    }
                                    Spacer()
                                    if selectedSource?.id == source.id {
                                        Image(systemName: "checkmark")
                                            .foregroundStyle(Moros.oracle)
                                    }
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(selectedSource?.id == source.id ? Moros.oracle.opacity(0.08) : .clear)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .frame(maxHeight: 160)
                .background(Moros.limit02, in: Rectangle())
                .overlay(Rectangle().stroke(Moros.border, lineWidth: 1))
            }

            Button(action: { showNewSourceForm.toggle() }) {
                Label(showNewSourceForm ? "Select existing" : "Add new source", systemImage: showNewSourceForm ? "list.bullet" : "plus.circle")
                    .font(Moros.fontBody)
                    .foregroundStyle(Moros.oracle)
            }
            .buttonStyle(.plain)

            if showNewSourceForm {
                VStack(alignment: .leading, spacing: 8) {
                    TextField("Source title", text: $newSourceTitle)
                        .textFieldStyle(.plain)
                        .font(Moros.fontBody)
                        .foregroundStyle(Moros.textMain)
                        .padding(8)
                        .background(Moros.limit02, in: Rectangle())

                    TextField("Author", text: $newSourceAuthor)
                        .textFieldStyle(.plain)
                        .font(Moros.fontBody)
                        .foregroundStyle(Moros.textMain)
                        .padding(8)
                        .background(Moros.limit02, in: Rectangle())

                    Picker("Type", selection: $newSourceType) {
                        ForEach(SourceType.allCases) { type in
                            Label(type.label, systemImage: type.icon).tag(type)
                        }
                    }
                    .pickerStyle(.menu)
                }
                .padding(10)
                .background(Moros.limit03, in: Rectangle())
            }
        }
    }

    // MARK: - Create

    private func createLiteratureNote() {
        let noteService = NoteService(context: context)

        let noteTitle = title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "Literature Note"
            : title.trimmingCharacters(in: .whitespacesAndNewlines)

        var noteContent = content.trimmingCharacters(in: .whitespacesAndNewlines)
        if !pageReference.isEmpty {
            noteContent = "**Ref:** \(pageReference)\n\n\(noteContent)"
        }

        if let note = existingNote {
            // Convert existing note
            noteService.updateNote(note, title: noteTitle, content: noteContent)
            note.noteType = .literature

            applySource(to: note)
            try? context.save()
            appState.selectedNote = note
        } else {
            // Create new note
            let note = noteService.createNote(title: noteTitle, content: noteContent, paraCategory: .resource)
            note.noteType = .literature

            applySource(to: note)
            try? context.save()
            appState.selectedNote = note
        }

        dismiss()
    }

    private func applySource(to note: NoteEntity) {
        if let source = selectedSource {
            note.sourceTitle = source.title
            note.sourceURL = source.url
            if let noteId = note.id {
                sourceService.linkNote(noteId: noteId, to: source.id)
            }
        } else if !newSourceTitle.isEmpty {
            let source = sourceService.addSource(
                title: newSourceTitle,
                author: newSourceAuthor.isEmpty ? nil : newSourceAuthor,
                sourceType: newSourceType,
                dateConsumed: Date()
            )
            note.sourceTitle = source.title
            if let noteId = note.id {
                sourceService.linkNote(noteId: noteId, to: source.id)
            }
        }
    }
}
