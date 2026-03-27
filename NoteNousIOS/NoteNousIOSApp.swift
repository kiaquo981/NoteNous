import SwiftUI
import CoreData

@main
struct NoteNousIOSApp: App {
    @StateObject private var coreDataStack = IOSCoreDataStack.shared

    var body: some Scene {
        WindowGroup {
            MainTabView()
                .environment(\.managedObjectContext, coreDataStack.viewContext)
                .environmentObject(coreDataStack)
                .preferredColorScheme(.dark)
        }
    }
}
