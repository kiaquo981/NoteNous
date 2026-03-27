import Foundation

enum ViewMode: Int, CaseIterable, Identifiable {
    case desk = 1
    case stack = 2
    case cards = 4
    case graph = 3

    var id: Int { rawValue }

    var label: String {
        switch self {
        case .desk: "Desk"
        case .stack: "Stack"
        case .cards: "Cards"
        case .graph: "Graph"
        }
    }

    var icon: String {
        switch self {
        case .desk: "rectangle.on.rectangle"
        case .stack: "square.stack"
        case .cards: "rectangle.grid.2x2"
        case .graph: "point.3.connected.trianglepath.dotted"
        }
    }

    var shortcut: String {
        switch self {
        case .desk: "⌘1"
        case .stack: "⌘2"
        case .cards: "⌘3"
        case .graph: "⌘4"
        }
    }
}
