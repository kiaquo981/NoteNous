import SwiftUI
import UniformTypeIdentifiers

struct MainWindowView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.managedObjectContext) private var context
    @State private var isDropTargeted = false

    var body: some View {
        NavigationSplitView {
            SidebarView()
        } content: {
            ViewRouter()
        } detail: {
            if let note = appState.selectedNote {
                NoteEditorView(note: note)
            } else {
                EmptyStateView(
                    icon: "note.text",
                    title: "No Note Selected",
                    subtitle: "Select a note or press \u{2318}N to create one"
                )
            }
        }
        .navigationSplitViewStyle(.balanced)
        .frame(minWidth: 900, minHeight: 600)
        .overlay {
            if isDropTargeted {
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(Color.accentColor, lineWidth: 3)
                    .background(Color.accentColor.opacity(0.05))
                    .allowsHitTesting(false)
            }
        }
        .onDrop(of: [.plainText, .url, .fileURL, .utf8PlainText], isTargeted: $isDropTargeted) { providers in
            handleDrop(providers)
            return true
        }
        .sheet(isPresented: $appState.isCommandPaletteVisible) {
            CommandPaletteView()
                .environmentObject(appState)
                .environment(\.managedObjectContext, context)
        }
    }

    // MARK: - Drop Handling

    private func handleDrop(_ providers: [NSItemProvider]) {
        for provider in providers {
            // File URLs (.txt, .md)
            if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { data, _ in
                    guard let urlData = data as? Data,
                          let url = URL(dataRepresentation: urlData, relativeTo: nil) else { return }
                    let ext = url.pathExtension.lowercased()
                    guard ext == "txt" || ext == "md" else { return }
                    guard let content = try? String(contentsOf: url, encoding: .utf8) else { return }
                    let title = url.deletingPathExtension().lastPathComponent
                    Task { @MainActor in
                        createDroppedNote(title: title, content: content)
                    }
                }
            }
            // Plain text or URL strings
            else if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
                provider.loadItem(forTypeIdentifier: UTType.plainText.identifier, options: nil) { data, _ in
                    guard let text = data as? String ?? (data as? Data).flatMap({ String(data: $0, encoding: .utf8) }) else { return }
                    Task { @MainActor in
                        createDroppedNote(title: "", content: text)
                    }
                }
            }
            else if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
                provider.loadItem(forTypeIdentifier: UTType.url.identifier, options: nil) { data, _ in
                    guard let urlData = data as? Data,
                          let url = URL(dataRepresentation: urlData, relativeTo: nil) else { return }
                    Task { @MainActor in
                        createDroppedNote(title: url.host ?? "Link", content: url.absoluteString)
                    }
                }
            }
        }
    }

    @MainActor
    private func createDroppedNote(title: String, content: String) {
        let service = NoteService(context: context)
        let note = service.createNote(title: title, content: content)
        appState.selectedNote = note
    }
}
