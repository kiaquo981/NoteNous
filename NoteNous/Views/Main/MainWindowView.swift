import SwiftUI

struct MainWindowView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.managedObjectContext) private var context

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
        .sheet(isPresented: $appState.isCommandPaletteVisible) {
            CommandPaletteView()
                .environmentObject(appState)
                .environment(\.managedObjectContext, context)
        }
    }
}
