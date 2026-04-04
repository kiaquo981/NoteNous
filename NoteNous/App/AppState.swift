import SwiftUI
import CoreData
import Combine

enum FolgezettelDirection {
    case parent, child, previousSibling, nextSibling
}

@MainActor
final class AppState: ObservableObject {
    @Published var selectedView: ViewMode = .stack
    @Published var selectedNote: NoteEntity?
    @Published var searchQuery: String = ""
    @Published var selectedPARAFilter: PARACategory?
    @Published var selectedCODEFilter: CODEStage?
    @Published var selectedNoteTypeFilter: NoteType?
    @Published var activeToolView: ToolView? = nil
    @Published var isQuickCaptureVisible: Bool = false
    @Published var isCommandPaletteVisible: Bool = false
    @Published var isSidebarVisible: Bool = true
    @Published var isSearchFocused: Bool = false
    @Published var isLinkCreationVisible: Bool = false
    @Published var isBacklinksVisible: Bool = true
    @Published var isLocalGraphVisible: Bool = false
    @Published var shouldOpenDailyNote: Bool = false
    @Published var shouldClassifyNote: Bool = false
    @Published var isImportVisible: Bool = false
    @Published var isExportVisible: Bool = false
    @Published var isZettelCreationVisible: Bool = false
    @Published var navigateFolgezettel: FolgezettelDirection? = nil
    @Published var shouldNavigateBack: Bool = false
    @Published var shouldNavigateForward: Bool = false
    @Published var isSemanticSearchVisible: Bool = false
    @Published var isAIChatVisible: Bool = false
    @Published var isAgentDashboardVisible: Bool = false
    @Published var isVoiceInkDashboardVisible: Bool = false
    @Published var isCallNoteVisible: Bool = false
    @Published var activeCallNote: UUID?
    @Published var isQuickSwitcherVisible: Bool = false
    @Published var recentNoteIds: [UUID] = [] {
        didSet {
            // Persist to UserDefaults
            let strings = recentNoteIds.map { $0.uuidString }
            UserDefaults.standard.set(strings, forKey: "AppState.recentNoteIds")
        }
    }

    // Navigation history (back/forward like a browser)
    private(set) var navBackStack: [NSManagedObjectID] = []
    private(set) var navForwardStack: [NSManagedObjectID] = []
    private var isNavigatingHistory: Bool = false

    var canGoBack: Bool { !navBackStack.isEmpty }
    var canGoForward: Bool { !navForwardStack.isEmpty }

    /// Navigate to a note and push the current note onto the back stack.
    /// Call this instead of setting selectedNote directly when the user
    /// initiates navigation (clicking a note, following a wikilink, etc.).
    func navigateToNote(_ note: NoteEntity) {
        guard note.objectID != selectedNote?.objectID else { return }
        if let current = selectedNote {
            navBackStack.append(current.objectID)
            // Limit history depth
            if navBackStack.count > 50 {
                navBackStack.removeFirst(navBackStack.count - 50)
            }
        }
        navForwardStack.removeAll()
        isNavigatingHistory = true
        selectedNote = note
        isNavigatingHistory = false
        objectWillChange.send()
    }

    func navigateBack() {
        guard let previousID = navBackStack.popLast() else { return }
        if let current = selectedNote {
            navForwardStack.append(current.objectID)
        }
        isNavigatingHistory = true
        selectedNote = fetchNote(by: previousID)
        isNavigatingHistory = false
        objectWillChange.send()
    }

    func navigateForward() {
        guard let nextID = navForwardStack.popLast() else { return }
        if let current = selectedNote {
            navBackStack.append(current.objectID)
        }
        isNavigatingHistory = true
        selectedNote = fetchNote(by: nextID)
        isNavigatingHistory = false
        objectWillChange.send()
    }

    private func fetchNote(by objectID: NSManagedObjectID) -> NoteEntity? {
        try? viewContext.existingObject(with: objectID) as? NoteEntity
    }

    private var cancellables = Set<AnyCancellable>()
    let coreData = CoreDataStack.shared

    var viewContext: NSManagedObjectContext {
        coreData.viewContext
    }

    init() {
        // Restore recent note IDs from UserDefaults
        if let strings = UserDefaults.standard.stringArray(forKey: "AppState.recentNoteIds") {
            recentNoteIds = strings.compactMap { UUID(uuidString: $0) }
        }

        // Track recent notes when selectedNote changes
        $selectedNote
            .compactMap { $0?.id }
            .removeDuplicates()
            .sink { [weak self] noteId in
                self?.trackRecentNote(noteId)
            }
            .store(in: &cancellables)
    }

    func trackRecentNote(_ noteId: UUID) {
        recentNoteIds.removeAll { $0 == noteId }
        recentNoteIds.insert(noteId, at: 0)
        if recentNoteIds.count > 10 {
            recentNoteIds = Array(recentNoteIds.prefix(10))
        }
    }

    enum ToolView: String, Identifiable {
        case sources, readyToCard, cardView
        case index, dashboard, processingQueue, pipeline
        case zettelkastenAgent, aiChat, voiceInk, callNotes
        var id: String { rawValue }
    }
}
