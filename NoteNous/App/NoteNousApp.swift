import SwiftUI

@main
struct NoteNousApp: App {
    @StateObject private var appState = AppState()

    init() {
        EnvLoader.loadIfNeeded()
    }

    var body: some Scene {
        WindowGroup {
            MainWindowView()
                .environmentObject(appState)
                .environment(\.managedObjectContext, appState.viewContext)
                .sheet(isPresented: $appState.isQuickCaptureVisible) {
                    QuickCapturePanel()
                        .environmentObject(appState)
                        .environment(\.managedObjectContext, appState.viewContext)
                }
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Note") {
                    appState.selectedNote = nil // triggers new note in editor
                }
                .keyboardShortcut("n", modifiers: .command)

                Button("Quick Capture") {
                    appState.isQuickCaptureVisible = true
                }
                .keyboardShortcut("n", modifiers: [.command, .shift])
            }

            CommandMenu("View") {
                Button("Desk") { appState.selectedView = .desk }
                    .keyboardShortcut("1", modifiers: .command)
                Button("Stack") { appState.selectedView = .stack }
                    .keyboardShortcut("2", modifiers: .command)
                Button("Graph") { appState.selectedView = .graph }
                    .keyboardShortcut("3", modifiers: .command)

                Divider()

                Button("Command Palette") { appState.isCommandPaletteVisible.toggle() }
                    .keyboardShortcut("k", modifiers: .command)
            }
        }

        Settings {
            SettingsView()
                .environmentObject(appState)
        }
    }
}
