import SwiftUI

struct DailyNoteButton: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.managedObjectContext) private var context

    var body: some View {
        Button(action: openTodayNote) {
            HStack(spacing: 8) {
                ZStack {
                    Image(systemName: "calendar")
                        .font(.body)
                    Text(DailyNoteService.todayDateNumber)
                        .font(.system(size: 7, weight: .bold))
                        .offset(y: 2)
                }
                .frame(width: 20)

                Text("Today's Note")
            }
            .foregroundStyle(Moros.oracle)
        }
        .buttonStyle(.plain)
    }

    private func openTodayNote() {
        let service = DailyNoteService(context: context)
        let dailyNote = service.todayNote()
        appState.selectedNote = dailyNote
    }
}
