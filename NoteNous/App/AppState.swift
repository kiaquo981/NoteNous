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
