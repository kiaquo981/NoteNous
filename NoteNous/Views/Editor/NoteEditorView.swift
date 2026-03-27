import SwiftUI

struct NoteEditorView: View {
    @ObservedObject var note: NoteEntity
    @Environment(\.managedObjectContext) private var context
    @EnvironmentObject var appState: AppState
    @State private var title: String = ""
    @State private var content: String = ""
    @State private var showBacklinks: Bool = true
    @State private var showLinkBrowser: Bool = false
    @State private var showLinkCreation: Bool = false
    @State private var showLocalGraph: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            // Sequence Navigator
            if let zettelId = note.zettelId {
                SequenceNavigator(zettelId: zettelId)
                    .padding(.horizontal)
                    .padding(.top, 6)
            }

            // Header
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    if let zettelId = note.zettelId {
                        Text(zettelId)
                            .font(.caption)
                            .monospaced()
                            .foregroundStyle(.tertiary)
                            .textSelection(.enabled)
                    }
                    Spacer()
                    NoteAtomicityIndicator(note: note)
                    NoteTypeBadge(type: note.noteType)
                    CODEStageBadge(stage: note.codeStage)
                    PARABadge(category: note.paraCategory)
                }

                TextField("What is this note's claim?", text: $title)
                    .textFieldStyle(.plain)
                    .font(.title2.weight(.bold))
                    .onSubmit { saveChanges() }
            }
            .padding()

            Divider()

            // Content Editor
            TextEditor(text: $content)
                .font(.body.monospaced())
                .scrollContentBackground(.hidden)
                .padding()

            Divider()

            // Footer — Tags + Actions
            HStack {
                Image(systemName: "tag")
                    .foregroundStyle(.secondary)
                ForEach(note.tagsArray, id: \.objectID) { tag in
                    if let name = tag.name {
                        TagBadge(name: name)
                    }
                }
                Spacer()

                Button(action: { showLinkCreation = true }) {
                    Label("Link", systemImage: "link.badge.plus")
                }
                .buttonStyle(.plain)
                .font(.caption)

                Button(action: { showLinkBrowser.toggle() }) {
                    Label("\(note.totalLinkCount)", systemImage: "arrow.triangle.branch")
                }
                .buttonStyle(.plain)
                .font(.caption)

                Button(action: { showLocalGraph.toggle() }) {
                    Image(systemName: "point.3.connected.trianglepath.dotted")
                }
                .buttonStyle(.plain)
                .font(.caption)

                if note.aiClassified {
                    HStack(spacing: 4) {
                        Image(systemName: "brain")
                        Text("\(Int(note.aiConfidence * 100))%")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)

            // Local Graph Panel (toggleable)
            if showLocalGraph {
                Divider()
                LocalGraphView(centerNote: note)
                    .frame(height: 260)
            }

            // Backlinks Panel
            if showBacklinks {
                Divider()
                BacklinksPanel(note: note)
            }
        }
        .onAppear { loadNote() }
        .onChange(of: note.objectID) { loadNote() }
        .onChange(of: title) { saveChanges() }
        .onChange(of: content) { saveChanges() }
        .sheet(isPresented: $showLinkCreation) {
            LinkCreationSheet(sourceNote: note)
                .environment(\.managedObjectContext, context)
        }
        .sheet(isPresented: $showLinkBrowser) {
            LinkBrowserView(note: note)
                .environment(\.managedObjectContext, context)
                .environmentObject(appState)
                .frame(minWidth: 500, minHeight: 400)
        }
    }

    private func loadNote() {
        title = note.title
        content = note.content
    }

    private func saveChanges() {
        guard title != note.title || content != note.content else { return }
        let service = NoteService(context: context)
        service.updateNote(note, title: title, content: content)
    }
}
