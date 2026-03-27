import SwiftUI

struct MainTabView: View {
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            CaptureView()
                .tabItem {
                    Label("Capture", systemImage: "plus.circle.fill")
                }
                .tag(0)

            InboxView()
                .tabItem {
                    Label("Inbox", systemImage: "tray.fill")
                }
                .tag(1)

            ReviewView()
                .tabItem {
                    Label("Review", systemImage: "brain.head.profile")
                }
                .tag(2)

            DailyNoteView()
                .tabItem {
                    Label("Today", systemImage: "calendar")
                }
                .tag(3)
        }
        .tint(MorosIOS.oracle)
    }
}
