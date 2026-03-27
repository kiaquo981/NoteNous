import SwiftUI
import CoreData

struct InboxView: View {
    @Environment(\.managedObjectContext) private var viewContext

    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(key: "createdAt", ascending: false)],
        predicate: NSCompoundPredicate(andPredicateWithSubpredicates: [
            NSPredicate(format: "isArchived == NO"),
            NSPredicate(format: "noteTypeRaw == %d", NoteType.fleeting.rawValue)
        ]),
        animation: .default
    )
    private var notes: FetchedResults<NoteEntity>

    @State private var selectedNote: NoteEntity?
    @State private var editTitle = ""
    @State private var editContent = ""

    var body: some View {
        NavigationStack {
            ZStack {
                MorosIOS.void.ignoresSafeArea()

                if notes.isEmpty {
                    emptyState
                } else {
                    notesList
                }
            }
            .navigationTitle("Inbox")
            .navigationBarTitleDisplayMode(.large)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .sheet(item: $selectedNote) { note in
                noteEditor(for: note)
            }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: MorosIOS.spacing16) {
            Image(systemName: "tray")
                .font(.system(size: 48))
                .foregroundColor(MorosIOS.textGhost)
            Text("Inbox Empty")
                .font(MorosIOS.fontH3)
                .foregroundColor(MorosIOS.textDim)
            Text("Fleeting notes appear here")
                .font(MorosIOS.fontSmall)
                .foregroundColor(MorosIOS.textDim)
        }
    }

    // MARK: - Notes List

    private var notesList: some View {
        List {
            ForEach(notes, id: \.objectID) { note in
                noteRow(note)
                    .listRowBackground(MorosIOS.limit01)
                    .listRowSeparatorTint(MorosIOS.border)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        editTitle = note.title
                        editContent = note.content
                        selectedNote = note
                    }
            }
            .onDelete(perform: archiveNotes)
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }

    // MARK: - Note Row

    private func noteRow(_ note: NoteEntity) -> some View {
        HStack(spacing: MorosIOS.spacing12) {
            // Age indicator
            Circle()
                .fill(MorosIOS.ageColor(for: note.createdAt))
                .frame(width: 8, height: 8)

            VStack(alignment: .leading, spacing: MorosIOS.spacing4) {
                Text(note.title.isEmpty ? "Untitled" : note.title)
                    .font(MorosIOS.fontBody)
                    .foregroundColor(MorosIOS.textMain)
                    .lineLimit(1)

                if !note.contentPlainText.isEmpty {
                    Text(note.contentPlainText)
                        .font(MorosIOS.fontSmall)
                        .foregroundColor(MorosIOS.textDim)
                        .lineLimit(2)
                }

                if let date = note.createdAt {
                    Text(date, style: .relative)
                        .font(MorosIOS.fontCaption)
                        .foregroundColor(MorosIOS.textDim)
                }
            }

            Spacer()

            Image(systemName: note.noteType.icon)
                .font(MorosIOS.fontSmall)
                .foregroundColor(MorosIOS.ambient)
        }
        .padding(.vertical, MorosIOS.spacing4)
    }

    // MARK: - Note Editor Sheet

    private func noteEditor(for note: NoteEntity) -> some View {
        NavigationStack {
            ZStack {
                MorosIOS.void.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: MorosIOS.spacing16) {
                        TextField("Title", text: $editTitle)
                            .font(MorosIOS.fontH2)
                            .foregroundColor(MorosIOS.textMain)
                            .padding(MorosIOS.spacing12)
                            .background(MorosIOS.limit02)
                            .clipShape(RoundedRectangle(cornerRadius: 4))

                        ZStack(alignment: .topLeading) {
                            if editContent.isEmpty {
                                Text("Content...")
                                    .font(MorosIOS.fontBody)
                                    .foregroundColor(MorosIOS.textDim)
                                    .padding(MorosIOS.spacing16)
                                    .padding(.top, 2)
                            }
                            TextEditor(text: $editContent)
                                .font(MorosIOS.fontBody)
                                .foregroundColor(MorosIOS.textMain)
                                .scrollContentBackground(.hidden)
                                .padding(MorosIOS.spacing12)
                                .frame(minHeight: 300)
                        }
                        .background(MorosIOS.limit02)
                        .clipShape(RoundedRectangle(cornerRadius: 4))

                        // Tags display
                        if !note.tagsArray.isEmpty {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: MorosIOS.spacing8) {
                                    ForEach(note.tagsArray, id: \.objectID) { tag in
                                        Text("#\(tag.name ?? "")")
                                            .font(MorosIOS.fontCaption)
                                            .foregroundColor(MorosIOS.oracle)
                                            .padding(.horizontal, MorosIOS.spacing8)
                                            .padding(.vertical, MorosIOS.spacing4)
                                            .background(MorosIOS.oracle.opacity(0.12))
                                            .clipShape(RoundedRectangle(cornerRadius: 4))
                                    }
                                }
                            }
                        }
                    }
                    .padding(MorosIOS.spacing16)
                }
            }
            .navigationTitle("Edit Note")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        selectedNote = nil
                    }
                    .foregroundColor(MorosIOS.ambient)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") {
                        let noteService = NoteService(context: viewContext)
                        noteService.updateNote(note, title: editTitle, content: editContent)
                        selectedNote = nil
                    }
                    .foregroundColor(MorosIOS.oracle)
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Actions

    private func archiveNotes(at offsets: IndexSet) {
        let noteService = NoteService(context: viewContext)
        for index in offsets {
            noteService.archiveNote(notes[index])
        }
    }
}
