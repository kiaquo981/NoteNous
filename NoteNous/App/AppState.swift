import SwiftUI
import CoreData

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
    @Published var sidebarNavSelection: String?
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

    let coreData = CoreDataStack.shared

    var viewContext: NSManagedObjectContext {
        coreData.viewContext
    }
}
