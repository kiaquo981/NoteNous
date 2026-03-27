import SwiftUI
import CoreSpotlight

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
                .morosTheme()
                .tint(Color(red: 0.267, green: 0.467, blue: 0.800)) // ORACLE blue
                .sheet(isPresented: $appState.isQuickCaptureVisible) {
                    QuickCapturePanel()
                        .environmentObject(appState)
                        .environment(\.managedObjectContext, appState.viewContext)
                        .morosTheme()
                }
                .sheet(isPresented: $appState.isCallNoteVisible) {
                    CallNoteSheet(
                        callNoteService: CallNoteService(),
                        callNoteId: appState.activeCallNote
                    )
                    .environmentObject(appState)
                    .environment(\.managedObjectContext, appState.viewContext)
                    .morosTheme()
                    .frame(minWidth: 600, minHeight: 500)
                }
                .sheet(isPresented: $appState.isSemanticSearchVisible) {
                    SemanticSearchView(embeddingService: EmbeddingService.shared)
                        .environmentObject(appState)
                        .environment(\.managedObjectContext, appState.viewContext)
                        .morosTheme()
                        .frame(minWidth: 600, minHeight: 500)
                }
                .onAppear {
                    // Apply theme mode from settings
                    let mode = MorosThemeMode.current
                    switch mode {
                    case .dark:
                        NSApp.appearance = NSAppearance(named: .darkAqua)
                    case .light:
                        NSApp.appearance = NSAppearance(named: .aqua)
                    case .auto:
                        NSApp.appearance = nil  // follows system
                    }
                    OnboardingService.runIfNeeded(context: appState.viewContext)
                    SpotlightService.shared.indexAllNotes(context: appState.viewContext)
                    ClipServer.shared.start()

                    // Start VoiceInk auto-sync if enabled
                    if VoiceInkAutoSync.shared.isEnabled {
                        VoiceInkAutoSync.shared.startAutoSync(context: appState.viewContext)
                    }

                    // Start nightly Zettelkasten Agent scheduler
                    NightlyAgentScheduler.shared.start()
                }
                .onDisappear {
                    ClipServer.shared.stop()
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
                .morosTheme()
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
