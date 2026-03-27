import SwiftUI

// MARK: - Graph Toolbar

struct GraphToolbar: View {
    @Binding var colorMode: GraphColorMode
    @Binding var isLocalGraph: Bool
    @Binding var localDepth: Int
    @Binding var physicsEnabled: Bool
    @Binding var showLegend: Bool
    @Binding var showMinimap: Bool
    @Binding var graphSearchQuery: String
    @Binding var hiddenPARA: Set<PARACategory>
    @Binding var hiddenNoteTypes: Set<NoteType>
    @Binding var hiddenCODEStages: Set<CODEStage>
    @Binding var zoom: CGFloat

    let nodeCount: Int
    let edgeCount: Int
    let isSimulationRunning: Bool

    var onResetLayout: () -> Void
    var onFitAll: () -> Void
    var onTogglePhysics: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            // Graph mode toggle
            graphModeToggle

            Rectangle().fill(Moros.border).frame(width: 1, height: 20)

            // Color mode picker
            colorModePicker

            Rectangle().fill(Moros.border).frame(width: 1, height: 20)

            // Depth slider (local graph only)
            if isLocalGraph {
                depthControl
                Rectangle().fill(Moros.border).frame(width: 1, height: 20)
            }

            // Filter menu
            filterMenu

            Rectangle().fill(Moros.border).frame(width: 1, height: 20)

            // Layout controls
            layoutControls

            Rectangle().fill(Moros.border).frame(width: 1, height: 20)

            // Search
            searchField

            Spacer()

            // Zoom controls
            zoomControls

            Rectangle().fill(Moros.border).frame(width: 1, height: 20)

            // Stats
            statsDisplay

            // Toggle overlays
            overlayToggles
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Moros.limit01)
    }

    // MARK: - Components

    private var graphModeToggle: some View {
        Picker("Mode", selection: $isLocalGraph) {
            Label("Global", systemImage: "globe")
                .tag(false)
            Label("Local", systemImage: "scope")
                .tag(true)
        }
        .pickerStyle(.segmented)
        .frame(width: 160)
        .help(isLocalGraph ? "Showing neighborhood of selected note" : "Showing all notes")
    }

    private var colorModePicker: some View {
        Menu {
            ForEach(GraphColorMode.allCases) { mode in
                Button {
                    colorMode = mode
                } label: {
                    Label(mode.label, systemImage: mode.icon)
                }
            }
        } label: {
            Label(colorMode.label, systemImage: "paintpalette")
                .font(Moros.fontCaption)
                .foregroundStyle(Moros.textSub)
        }
        .menuStyle(.borderlessButton)
        .frame(width: 100)
        .help("Node color mode")
    }

    private var depthControl: some View {
        HStack(spacing: 4) {
            Text("Depth:")
                .font(Moros.fontCaption)
                .foregroundStyle(Moros.textDim)
            Stepper(
                "\(localDepth)",
                value: $localDepth,
                in: 1...5
            )
            .font(Moros.fontCaption)
            .frame(width: 80)
        }
        .help("Number of hops from center note")
    }

    private var filterMenu: some View {
        Menu {
            Section("PARA Category") {
                ForEach(PARACategory.allCases) { category in
                    Toggle(isOn: Binding(
                        get: { !hiddenPARA.contains(category) },
                        set: { visible in
                            if visible {
                                hiddenPARA.remove(category)
                            } else {
                                hiddenPARA.insert(category)
                            }
                        }
                    )) {
                        Label(category.label, systemImage: category.icon)
                    }
                }
            }

            Section("Note Type") {
                ForEach(NoteType.allCases) { type in
                    Toggle(isOn: Binding(
                        get: { !hiddenNoteTypes.contains(type) },
                        set: { visible in
                            if visible {
                                hiddenNoteTypes.remove(type)
                            } else {
                                hiddenNoteTypes.insert(type)
                            }
                        }
                    )) {
                        Label(type.label, systemImage: type.icon)
                    }
                }
            }

            Section("CODE Stage") {
                ForEach(CODEStage.allCases) { stage in
                    Toggle(isOn: Binding(
                        get: { !hiddenCODEStages.contains(stage) },
                        set: { visible in
                            if visible {
                                hiddenCODEStages.remove(stage)
                            } else {
                                hiddenCODEStages.insert(stage)
                            }
                        }
                    )) {
                        Label(stage.label, systemImage: stage.icon)
                    }
                }
            }

            Divider()

            Button("Show All") {
                hiddenPARA.removeAll()
                hiddenNoteTypes.removeAll()
                hiddenCODEStages.removeAll()
            }
        } label: {
            Label("Filter", systemImage: "line.3.horizontal.decrease.circle")
                .font(Moros.fontCaption)
                .foregroundStyle(Moros.textSub)
        }
        .menuStyle(.borderlessButton)
        .help("Filter visible nodes")
    }

    private var layoutControls: some View {
        HStack(spacing: 4) {
            Button {
                onResetLayout()
            } label: {
                Image(systemName: "arrow.counterclockwise")
                    .foregroundStyle(Moros.textSub)
            }
            .buttonStyle(.borderless)
            .help("Reset layout")

            Button {
                onTogglePhysics()
            } label: {
                Image(systemName: physicsEnabled ? "pause.circle" : "play.circle")
                    .foregroundStyle(isSimulationRunning ? Moros.verdit : Moros.textDim)
            }
            .buttonStyle(.borderless)
            .help(physicsEnabled ? "Pause physics" : "Resume physics")
        }
    }

    private var searchField: some View {
        HStack(spacing: 4) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(Moros.textDim)
                .font(Moros.fontCaption)
            TextField("Search graph...", text: $graphSearchQuery)
                .textFieldStyle(.plain)
                .font(Moros.fontCaption)
                .foregroundStyle(Moros.textMain)
                .frame(width: 120)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(Moros.limit02, in: Rectangle())
    }

    private var zoomControls: some View {
        HStack(spacing: 4) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    zoom = max(0.1, zoom - 0.2)
                }
            } label: {
                Image(systemName: "minus.magnifyingglass")
                    .foregroundStyle(Moros.textSub)
            }
            .buttonStyle(.borderless)

            Text("\(Int(zoom * 100))%")
                .font(Moros.fontMonoSmall)
                .foregroundStyle(Moros.textDim)
                .frame(width: 40)

            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    zoom = min(5.0, zoom + 0.2)
                }
            } label: {
                Image(systemName: "plus.magnifyingglass")
                    .foregroundStyle(Moros.textSub)
            }
            .buttonStyle(.borderless)

            Button {
                onFitAll()
            } label: {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .foregroundStyle(Moros.textSub)
            }
            .buttonStyle(.borderless)
            .help("Fit all nodes")
        }
    }

    private var statsDisplay: some View {
        Text("\(nodeCount) nodes | \(edgeCount) edges")
            .font(Moros.fontMonoSmall)
            .foregroundStyle(Moros.textDim)
            .monospacedDigit()
    }

    private var overlayToggles: some View {
        HStack(spacing: 4) {
            Button {
                showLegend.toggle()
            } label: {
                Image(systemName: showLegend ? "list.bullet.rectangle.fill" : "list.bullet.rectangle")
                    .foregroundStyle(Moros.textSub)
            }
            .buttonStyle(.borderless)
            .help("Toggle legend")

            Button {
                showMinimap.toggle()
            } label: {
                Image(systemName: showMinimap ? "map.fill" : "map")
                    .foregroundStyle(Moros.textSub)
            }
            .buttonStyle(.borderless)
            .help("Toggle minimap")
        }
    }
}
