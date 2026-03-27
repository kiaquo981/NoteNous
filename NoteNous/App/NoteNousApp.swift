import SwiftUI
import CoreSpotlight

@main
struct NoteNousApp: App {
    @StateObject private var appState = AppState()

    init() {
        EnvLoader.loadIfNeeded()
        // Force dark appearance globally — MOROS is dark-only
        NSApp.appearance = NSAppearance(named: .darkAqua)
    }

    var body: some Scene {
        WindowGroup {
            MainWindowView()
                .environmentObject(appState)
                .environment(\.managedObjectContext, appState.viewContext)
                .preferredColorScheme(.dark)
                .tint(Color(red: 0.267, green: 0.467, blue: 0.800)) // ORACLE blue
                .sheet(isPresented: $appState.isQuickCaptureVisible) {
                    QuickCapturePanel()
                        .environmentObject(appState)
                        .environment(\.managedObjectContext, appState.viewContext)
                        .preferredColorScheme(.dark)
                }
                .onAppear {
                    OnboardingService.runIfNeeded(context: appState.viewContext)
                    SpotlightService.shared.indexAllNotes(context: appState.viewContext)
                }
                .onContinueUserActivity(CSSearchableItemActionType) { activity in
                    handleSpotlightActivity(activity)
                }
        }
        .commands {
            KeyboardCommands(appState: appState)
        }

        Settings {
            SettingsView()
                .environmentObject(appState)
        }

        MenuBarExtra("NoteNous", systemImage: "note.text") {
            MenuBarCaptureView()
                .environmentObject(appState)
                .environment(\.managedObjectContext, appState.viewContext)
        }
        .menuBarExtraStyle(.window)
    }

    // MARK: - Spotlight Handler

    private func handleSpotlightActivity(_ activity: NSUserActivity) {
        guard let noteIdString = SpotlightService.noteIdentifier(from: activity) else { return }
        guard let noteId = UUID(uuidString: noteIdString) else { return }

        let context = appState.viewContext
        let request = NoteEntity.fetchRequest() as! NSFetchRequest<NoteEntity>
        request.predicate = NSPredicate(format: "id == %@", noteId as CVarArg)
        request.fetchLimit = 1

        if let note = try? context.fetch(request).first {
            appState.selectedNote = note
        }
    }
}
