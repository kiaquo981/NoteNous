import SwiftUI

struct CanvasToolbar: View {
    @Bindable var canvasState: DeskCanvasState
    let sectionStore: DeskSectionStore
    let selectedCount: Int
    let totalCount: Int
    let onAddNote: () -> Void
    let onAutoLayout: (AutoLayoutMode) -> Void
    let onZoomToFit: () -> Void
    let onBulkColorChange: (String?) -> Void
    let onBulkPARAChange: (PARACategory) -> Void
    let onBulkDelete: () -> Void
    let onToggleSectionPanel: () -> Void

    @State private var showColorPopover: Bool = false
    @State private var showAutoLayoutMenu: Bool = false
    @State private var showBulkColorPopover: Bool = false
    @State private var showBulkPARAMenu: Bool = false
    @State private var selectedColorHex: String?

    enum AutoLayoutMode: String, CaseIterable {
        case grid = "Grid"
        case byPARA = "By PARA"
        case byTag = "By Tag"

        var icon: String {
            switch self {
            case .grid: "square.grid.3x3"
            case .byPARA: "folder"
            case .byTag: "tag"
            }
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            // Left group: add + filter
            Group {
                addNoteButton
                Rectangle().fill(Moros.border).frame(width: 1, height: 20)
                filterControls
                Rectangle().fill(Moros.border).frame(width: 1, height: 20)
                displayModeControl
            }

            Spacer()

            // Center: selection info or section toggle
            if selectedCount > 0 {
                selectionActions
            } else {
                sectionToggle
            }

            Spacer()

            // Right group: connections + layout + zoom
            Group {
                connectionsToggle
                Rectangle().fill(Moros.border).frame(width: 1, height: 20)
                layoutControls
                Rectangle().fill(Moros.border).frame(width: 1, height: 20)
                zoomControls
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Moros.limit01)
    }

    // MARK: - Add note

    private var addNoteButton: some View {
        Button(action: onAddNote) {
            Label("Add Note", systemImage: "plus.rectangle")
                .font(.system(size: 12))
                .foregroundStyle(Moros.oracle)
        }
        .buttonStyle(.plain)
        .help("Add a new note at the center of the viewport")
    }

    // MARK: - Filter controls

    private var filterControls: some View {
        HStack(spacing: 6) {
            Picker("", selection: $canvasState.filterMode) {
                ForEach(DeskCanvasState.FilterMode.allCases) { mode in
                    Text(mode.label).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 180)

            if canvasState.filterMode == .color {
                Button {
                    showColorPopover.toggle()
                } label: {
                    Image(systemName: "paintpalette")
                        .font(.system(size: 12))
                        .foregroundStyle(Moros.textSub)
                }
                .buttonStyle(.plain)
                .popover(isPresented: $showColorPopover) {
                    DeskColorPicker(selectedHex: $selectedColorHex) { hex in
                        canvasState.filterValue = hex
                    }
                }
            }
        }
    }

    // MARK: - Display mode

    private var displayModeControl: some View {
        Picker("", selection: $canvasState.cardDisplayMode) {
            ForEach(DeskCanvasState.CardDisplayMode.allCases) { mode in
                Label(mode.label, systemImage: mode.icon).tag(mode)
            }
        }
        .pickerStyle(.segmented)
        .frame(width: 180)
        .help("Card display mode")
    }

    // MARK: - Selection actions

    private var selectionActions: some View {
        HStack(spacing: 8) {
            Text("\(selectedCount) selected")
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(Moros.textSub)

            Button {
                showBulkColorPopover.toggle()
            } label: {
                Image(systemName: "paintpalette")
                    .font(.system(size: 11))
                    .foregroundStyle(Moros.textSub)
            }
            .buttonStyle(.plain)
            .popover(isPresented: $showBulkColorPopover) {
                DeskColorPicker(selectedHex: $selectedColorHex) { hex in
                    onBulkColorChange(hex)
                    showBulkColorPopover = false
                }
            }
            .help("Change color of selected cards")

            Menu {
                ForEach(PARACategory.allCases) { para in
                    Button {
                        onBulkPARAChange(para)
                    } label: {
                        Label(para.label, systemImage: para.icon)
                    }
                }
            } label: {
                Image(systemName: "folder")
                    .font(.system(size: 11))
                    .foregroundStyle(Moros.textSub)
            }
            .menuStyle(.borderlessButton)
            .frame(width: 24)
            .help("Change PARA category of selected cards")

            Button(action: onBulkDelete) {
                Image(systemName: "trash")
                    .font(.system(size: 11))
                    .foregroundStyle(Moros.signal)
            }
            .buttonStyle(.plain)
            .help("Delete selected cards")
        }
    }

    // MARK: - Section toggle

    private var sectionToggle: some View {
        Button(action: onToggleSectionPanel) {
            HStack(spacing: 4) {
                Image(systemName: "sidebar.right")
                    .font(.system(size: 11))
                Text("Sections")
                    .font(.system(size: 11))
                if !sectionStore.sections.isEmpty {
                    Text("(\(sectionStore.sections.count))")
                        .font(Moros.fontMonoSmall)
                        .foregroundStyle(Moros.textDim)
                }
            }
            .foregroundStyle(Moros.textSub)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Connections toggle

    private var connectionsToggle: some View {
        Toggle(isOn: $canvasState.showConnections) {
            Image(systemName: "link")
                .font(.system(size: 11))
        }
        .toggleStyle(.button)
        .help("Show/hide connection lines")
    }

    // MARK: - Layout controls

    private var layoutControls: some View {
        HStack(spacing: 6) {
            Menu {
                ForEach(AutoLayoutMode.allCases, id: \.rawValue) { mode in
                    Button {
                        onAutoLayout(mode)
                    } label: {
                        Label(mode.rawValue, systemImage: mode.icon)
                    }
                }
            } label: {
                Image(systemName: "square.grid.3x3")
                    .font(.system(size: 11))
                    .foregroundStyle(Moros.textSub)
            }
            .menuStyle(.borderlessButton)
            .frame(width: 24)
            .help("Auto-layout cards")

            Toggle(isOn: $canvasState.snapToGrid) {
                Image(systemName: "grid")
                    .font(.system(size: 11))
            }
            .toggleStyle(.button)
            .help("Snap to grid")
        }
    }

    // MARK: - Zoom controls

    private var zoomControls: some View {
        HStack(spacing: 6) {
            Button {
                canvasState.zoom(by: 0.8, anchor: .zero)
            } label: {
                Image(systemName: "minus.magnifyingglass")
                    .font(.system(size: 11))
                    .foregroundStyle(Moros.textSub)
            }
            .buttonStyle(.plain)

            Text("\(Int(canvasState.zoomLevel * 100))%")
                .font(Moros.fontMonoSmall)
                .foregroundStyle(Moros.textDim)
                .frame(width: 42)

            Button {
                canvasState.zoom(by: 1.25, anchor: .zero)
            } label: {
                Image(systemName: "plus.magnifyingglass")
                    .font(.system(size: 11))
                    .foregroundStyle(Moros.textSub)
            }
            .buttonStyle(.plain)

            Button(action: onZoomToFit) {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .font(.system(size: 11))
                    .foregroundStyle(Moros.textSub)
            }
            .buttonStyle(.plain)
            .help("Fit all cards in view")
        }
    }
}
