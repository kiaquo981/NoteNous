import SwiftUI
import CoreData

struct SimilarNotesPanel: View {
    @ObservedObject var note: NoteEntity
    @Environment(\.managedObjectContext) private var context
    @EnvironmentObject var appState: AppState
    @ObservedObject var embeddingService: EmbeddingService

    @State private var isExpanded = true
    @State private var similarNotes: [(note: NoteEntity, similarity: Float)] = []
    @State private var updateTask: Task<Void, Never>?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            headerView

            if isExpanded {
                Rectangle().fill(Moros.border).frame(height: 1)

                if similarNotes.isEmpty {
                    emptyState
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(similarNotes, id: \.note.objectID) { item in
                                SimilarNoteRow(
                                    note: item.note,
                                    similarity: item.similarity,
                                    onNavigate: {
                                        appState.navigateToNote(item.note)
                                    },
                                    onLink: {
                                        createWikilink(to: item.note)
                                    }
                                )
                                Rectangle().fill(Moros.border).frame(height: 1)
                            }
                        }
                    }
                    .frame(maxHeight: 250)
                }
            }
        }
        .background(Moros.limit01)
        .clipShape(Rectangle())
        .onAppear { loadSimilarNotes() }
        .onChange(of: note.objectID) { loadSimilarNotes() }
        .onChange(of: note.content) { debouncedUpdate() }
    }

    // MARK: - Header

    private var headerView: some View {
        Button {
            withAnimation(.easeInOut(duration: Moros.animFast)) {
                isExpanded.toggle()
            }
        } label: {
            HStack {
                Image(systemName: "sparkles")
                    .foregroundStyle(Moros.oracle)
                Text("Similar Notes")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Moros.textMain)

                if !similarNotes.isEmpty {
                    Text("\(similarNotes.count)")
                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Moros.oracle.opacity(0.15), in: Rectangle())
                        .foregroundStyle(Moros.oracle)
                }

                Spacer()

                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                    .font(.caption)
                    .foregroundStyle(Moros.textDim)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 6) {
            Image(systemName: "sparkles")
                .font(.title2)
                .foregroundStyle(Moros.textGhost)
            Text("No similar notes found")
                .font(Moros.fontBody)
                .foregroundStyle(Moros.textDim)
            if !embeddingService.hasEmbeddings {
                Text("Index your notes to discover connections.")
                    .font(Moros.fontCaption)
                    .foregroundStyle(Moros.textDim)
                    .multilineTextAlignment(.center)
                Button("Index Notes") {
                    Task {
                        await embeddingService.indexAllNotes(context: context)
                        loadSimilarNotes()
                    }
                }
                .font(Moros.fontCaption)
                .foregroundStyle(Moros.oracle)
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
    }

    // MARK: - Logic

    private func loadSimilarNotes() {
        similarNotes = embeddingService.findSimilar(to: note, context: context, limit: 5)
    }

    private func debouncedUpdate() {
        updateTask?.cancel()
        updateTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_000_000_000) // 2s debounce
            guard !Task.isCancelled else { return }
            await embeddingService.indexNote(note)
            loadSimilarNotes()
        }
    }

    private func createWikilink(to targetNote: NoteEntity) {
        let targetTitle = targetNote.title.isEmpty ? "Untitled" : targetNote.title
        let wikilink = "[[\(targetTitle)]]"

        // Append wikilink to current note content
        let currentContent = note.content
        let newContent = currentContent.isEmpty ? wikilink : currentContent + "\n\n" + wikilink
        let service = NoteService(context: context)
        service.updateNote(note, content: newContent)
    }
}

// MARK: - Similar Note Row

struct SimilarNoteRow: View {
    let note: NoteEntity
    let similarity: Float
    let onNavigate: () -> Void
    let onLink: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            // Similarity indicator
            Text("\(Int(similarity * 100))%")
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(scoreColor)
                .frame(width: 32, alignment: .trailing)

            // Note info
            Button(action: onNavigate) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(note.title.isEmpty ? "Untitled" : note.title)
                        .font(Moros.fontBody)
                        .foregroundStyle(Moros.textMain)
                        .lineLimit(1)

                    Text(previewLine)
                        .font(Moros.fontCaption)
                        .foregroundStyle(Moros.textDim)
                        .lineLimit(1)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Spacer()

            // Link button
            Button(action: onLink) {
                Image(systemName: "link.badge.plus")
                    .font(.caption)
                    .foregroundStyle(Moros.oracle)
            }
            .buttonStyle(.plain)
            .help("Link this note")

            // Navigate arrow
            Button(action: onNavigate) {
                Image(systemName: "arrow.right")
                    .font(.caption2)
                    .foregroundStyle(Moros.textDim)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    private var previewLine: String {
        let plain = note.contentPlainText
        if plain.isEmpty { return "No content" }
        return String(plain.prefix(80))
    }

    private var scoreColor: Color {
        if similarity > 0.8 { return Moros.verdit }
        if similarity > 0.5 { return Moros.oracle }
        if similarity > 0.3 { return Moros.ambient }
        return Moros.textDim
    }
}
