import SwiftUI

enum EditorMode: String, CaseIterable, Identifiable {
    case edit
    case preview
    case split

    var id: String { rawValue }

    var label: String {
        switch self {
        case .edit: "Edit"
        case .preview: "Preview"
        case .split: "Split"
        }
    }

    var icon: String {
        switch self {
        case .edit: "pencil"
        case .preview: "eye"
        case .split: "rectangle.split.2x1"
        }
    }
}

struct EditorModeToggle: View {
    @Binding var mode: EditorMode

    var body: some View {
        Picker("Editor Mode", selection: $mode) {
            ForEach(EditorMode.allCases) { editorMode in
                Label(editorMode.label, systemImage: editorMode.icon)
                    .tag(editorMode)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .frame(width: 180)
    }
}
