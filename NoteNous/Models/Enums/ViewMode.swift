import Foundation

enum ViewMode: Int, CaseIterable, Identifiable {
    case desk = 1
    case stack = 2
    case graph = 3

    var id: Int { rawValue }

    var label: String {
        switch self {
        case .desk: "Desk"
        case .stack: "Stack"
        case .graph: "Graph"
        }
    }

    var icon: String {
        switch self {
        case .desk: "rectangle.on.rectangle"
        case .stack: "square.stack"
        case .graph: "point.3.connected.trianglepath.dotted"
        }
    }

    var shortcut: String {
        switch self {
        case .desk: "⌘1"
        case .stack: "⌘2"
        case .graph: "⌘3"
        }
    }
}
