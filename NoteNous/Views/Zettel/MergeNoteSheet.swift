import SwiftUI
import CoreData

/// Sheet for merging a fleeting note's content into an existing note.
/// Searches for a target note and appends the source note's content.
struct MergeNoteSheet: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.managedObjectContext) private var context
    @Environment(\.dismiss) private var dismiss

    @ObservedObject var sourceNote: NoteEntity

    @State private var searchQuery: String = ""
    @State private var selectedTarget: NoteEntity?

    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \NoteEntity.updatedAt, ascending: false)],
        predicate: NSPredicate(format: "isArchived == NO")
    ) private var allNotes: FetchedResults<NoteEntity>

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Merge into Existing Note")
                        .font(Moros.fontH2)
                        .foregroundStyle(Moros.textMain)
                    Text("Append content from '\(sourceNote.title.isEmpty ? "Untitled" : sourceNote.title)'")
                        .font(Moros.fontCaption)
                        .foregroundStyle(Moros.textDim)
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

            // Source preview
            VStack(alignment: .leading, spacing: 4) {
                Text("CONTENT TO MERGE")
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundStyle(Moros.textDim)
                Text(sourceNote.contentPlainText.isEmpty ? "No content" : String(sourceNote.contentPlainText.prefix(200)))
                    .font(Moros.fontSmall)
                    .foregroundStyle(Moros.textSub)
                    .lineLimit(4)
            }
            .padding()
            .background(Moros.limit02)

            Rectangle().fill(Moros.border).frame(height: 1)

            // Search
            VStack(alignment: .leading, spacing: 8) {
                Text("SELECT TARGET NOTE")
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundStyle(Moros.textDim)

                TextField("Search notes...", text: $searchQuery)
                    .textFieldStyle(.plain)
                    .font(Moros.fontBody)
                    .foregroundStyle(Moros.textMain)
                    .padding(8)
                    .background(Moros.limit02, in: Rectangle())
            }
            .padding()

            // Results
            let results = filteredNotes
            if results.isEmpty {
                VStack {
                    Text("No matching notes")
                        .font(Moros.fontBody)
                        .foregroundStyle(Moros.textDim)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(results.prefix(20), id: \.objectID) { note in
                        Button {
                            selectedTarget = note
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: note.noteType.icon)
                                    .font(.system(size: 10))
                                    .foregroundStyle(Moros.textDim)
                                Text(note.zettelId ?? "?")
                                    .font(Moros.fontMonoSmall)
                                    .foregroundStyle(Moros.textDim)
                                    .frame(width: 50, alignment: .leading)
                                Text(note.title.isEmpty ? "Untitled" : note.title)
                                    .font(Moros.fontBody)
                                    .foregroundStyle(Moros.textMain)
                                    .lineLimit(1)
                                Spacer()
                                if selectedTarget?.objectID == note.objectID {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(Moros.oracle)
                                }
                            }
                            .padding(.vertical, 2)
                        }
                        .buttonStyle(.plain)
                        .listRowBackground(selectedTarget?.objectID == note.objectID ? Moros.oracle.opacity(0.06) : Moros.limit01)
                    }
                }
                .listStyle(.inset(alternatesRowBackgrounds: false))
        
            }

            Rectangle().fill(Moros.border).frame(height: 1)

            // Footer
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .foregroundStyle(Moros.textSub)
                Button("Merge & Archive") {
                    mergeNote()
                }
                .keyboardShortcut(.return, modifiers: .command)
                .buttonStyle(.borderedProminent)
                .disabled(selectedTarget == nil)
            }
            .padding()
        }
        .frame(minWidth: 480, minHeight: 500)

        .preferredColorScheme(.dark)
    }

    private var filteredNotes: [NoteEntity] {
        let notes = allNotes.filter { $0.objectID != sourceNote.objectID }
        if searchQuery.isEmpty { return Array(notes) }
        let q = searchQuery.lowercased()
        return notes.filter { note in
            note.title.lowercased().contains(q) ||
            (note.zettelId?.lowercased().contains(q) == true)
        }
    }

    private func mergeNote() {
        guard let target = selectedTarget else { return }

        // Append source content to target
        let separator = "\n\n---\n*Merged from: \(sourceNote.title.isEmpty ? "Untitled" : sourceNote.title)*\n\n"
        let mergedContent = target.content + separator + sourceNote.content

        let service = NoteService(context: context)
        service.updateNote(target, content: mergedContent)

        // Archive the source note
        service.archiveNote(sourceNote)

        appState.selectedNote = target
        dismiss()
    }
}
