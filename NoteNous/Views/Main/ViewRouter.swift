import SwiftUI

struct ViewRouter: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        ZStack {
            switch appState.selectedView {
            case .desk:
                DeskCanvasView()
            case .stack:
                StackView()
            case .graph:
                GraphView()
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .principal) {
                Picker("View", selection: $appState.selectedView) {
                    ForEach(ViewMode.allCases) { mode in
                        Label(mode.label, systemImage: mode.icon)
                            .tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 200)
            }
        }
    }
}
