import SwiftUI
import CoreData

@MainActor
final class AppState: ObservableObject {
    @Published var selectedView: ViewMode = .stack
    @Published var selectedNote: NoteEntity?
    @Published var searchQuery: String = ""
    @Published var selectedPARAFilter: PARACategory?
    @Published var selectedCODEFilter: CODEStage?
    @Published var isQuickCaptureVisible: Bool = false
    @Published var isCommandPaletteVisible: Bool = false

    let coreData = CoreDataStack.shared

    var viewContext: NSManagedObjectContext {
        coreData.viewContext
    }
}
