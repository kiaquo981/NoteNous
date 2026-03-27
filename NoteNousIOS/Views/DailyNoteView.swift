import SwiftUI
import CoreData

struct DailyNoteView: View {
    @Environment(\.managedObjectContext) private var viewContext

    @State private var dailyNote: NoteEntity?
    @State private var title = ""
    @State private var content = ""
    @State private var hasLoaded = false

    var body: some View {
        NavigationStack {
            ZStack {
                MorosIOS.void.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: MorosIOS.spacing16) {
                        // Date header
                        Text(todayFormatted)
                            .font(MorosIOS.fontDisplay)
                            .foregroundColor(MorosIOS.textMain)
                            .padding(.bottom, MorosIOS.spacing8)

                        // Title
                        TextField("Daily Title", text: $title)
                            .font(MorosIOS.fontH3)
                            .foregroundColor(MorosIOS.textMain)
                            .padding(MorosIOS.spacing12)
                            .background(MorosIOS.limit02)
                            .clipShape(RoundedRectangle(cornerRadius: 4))

                        // Content editor
                        ZStack(alignment: .topLeading) {
                            if content.isEmpty {
                                Text("## Captures\n\n## Tasks\n\n## Reflections")
                                    .font(MorosIOS.fontBody)
                                    .foregroundColor(MorosIOS.textGhost)
                                    .padding(MorosIOS.spacing16)
                                    .padding(.top, 2)
                            }
                            TextEditor(text: $content)
                                .font(MorosIOS.fontBody)
                                .foregroundColor(MorosIOS.textSub)
                                .scrollContentBackground(.hidden)
                                .padding(MorosIOS.spacing12)
                                .frame(minHeight: 400)
                        }
                        .background(MorosIOS.limit02)
                        .clipShape(RoundedRectangle(cornerRadius: 4))

                        // Tags
                        if let note = dailyNote, !note.tagsArray.isEmpty {
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
            .navigationTitle("Today")
            .navigationBarTitleDisplayMode(.large)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        saveNote()
                    } label: {
                        Text("Save")
                            .foregroundColor(MorosIOS.oracle)
                    }
                }
            }
            .onAppear {
                if !hasLoaded {
                    loadOrCreateDailyNote()
                    hasLoaded = true
                }
            }
        }
    }

    // MARK: - Helpers

    private var todayFormatted: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, MMM d"
        return formatter.string(from: Date())
    }

    private func loadOrCreateDailyNote() {
        let service = DailyNoteService(context: viewContext)
        let note = service.todayNote()
        dailyNote = note
        title = note.title
        content = note.content
    }

    private func saveNote() {
        guard let note = dailyNote else { return }
        let noteService = NoteService(context: viewContext)
        noteService.updateNote(note, title: title, content: content)
    }
}
