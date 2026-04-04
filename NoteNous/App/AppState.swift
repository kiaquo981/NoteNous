import SwiftUI
import CoreData
import Combine

enum FolgezettelDirection {
    case parent, child, previousSibling, nextSibling
}

enum StackSortMode: String, CaseIterable, Identifiable {
    case updatedAt = "Date Modified"
    case manual = "Manual"

    var id: String { rawValue }
}

@MainActor
final class AppState: ObservableObject {
    @Published var selectedView: ViewMode = .stack
    @Published var selectedNote: NoteEntity?
    @Published var searchQuery: String = ""
    @Published var selectedPARAFilter: PARACategory?
    @Published var selectedCODEFilter: CODEStage?
    @Published var selectedNoteTypeFilter: NoteType?
    @Published var stackSortMode: StackSortMode = .updatedAt
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

    // Split View
    @Published var isSplitActive: Bool = false
    @Published var splitNote: NoteEntity?

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

    // MARK: - Tab State

    @Published var openTabIds: [UUID] = [] {
        didSet {
            let strings = openTabIds.map { $0.uuidString }
            UserDefaults.standard.set(strings, forKey: "AppState.openTabIds")
        }
    }

    @Published var activeTabId: UUID? {
        didSet {
            if let id = activeTabId {
                UserDefaults.standard.set(id.uuidString, forKey: "AppState.activeTabId")
            } else {
                UserDefaults.standard.removeObject(forKey: "AppState.activeTabId")
            }
        }
    }

    static let maxTabs = 10

    var hasOpenTabs: Bool { !openTabIds.isEmpty }

    func openTab(for note: NoteEntity) {
        guard let noteId = note.id else { return }
        if !openTabIds.contains(noteId) {
            openTabIds.append(noteId)
            while openTabIds.count > Self.maxTabs {
                openTabIds.removeFirst()
            }
        }
        activeTabId = noteId
        selectedNote = note
    }

    func closeTab(_ noteId: UUID) {
        guard let index = openTabIds.firstIndex(of: noteId) else { return }
        openTabIds.remove(at: index)
        if activeTabId == noteId {
            if openTabIds.isEmpty {
                activeTabId = nil
                selectedNote = nil
            } else {
                let newIndex = min(index, openTabIds.count - 1)
                let newTabId = openTabIds[newIndex]
                activeTabId = newTabId
                let request = NoteEntity.fetchRequest() as! NSFetchRequest<NoteEntity>
                request.predicate = NSPredicate(format: "id == %@", newTabId as CVarArg)
                request.fetchLimit = 1
                selectedNote = try? viewContext.fetch(request).first
            }
        }
    }

    func closeActiveTab() {
        guard let tabId = activeTabId else { return }
        closeTab(tabId)
    }

    func openCurrentNoteAsTab() {
        guard let note = selectedNote else { return }
        openTab(for: note)
    }

    func switchToTab(_ noteId: UUID) {
        guard openTabIds.contains(noteId) else { return }
        activeTabId = noteId
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

        // Restore open tabs from UserDefaults
        if let tabStrings = UserDefaults.standard.stringArray(forKey: "AppState.openTabIds") {
            openTabIds = tabStrings.compactMap { UUID(uuidString: $0) }
        }
        if let activeStr = UserDefaults.standard.string(forKey: "AppState.activeTabId") {
            activeTabId = UUID(uuidString: activeStr)
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
