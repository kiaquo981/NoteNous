import Foundation

enum PARACategory: Int16, CaseIterable, Identifiable, Codable {
    case inbox = 0
    case project = 1
    case area = 2
    case resource = 3
    case archive = 4

    var id: Int16 { rawValue }

    var label: String {
        switch self {
        case .inbox: "Inbox"
        case .project: "Projects"
        case .area: "Areas"
        case .resource: "Resources"
        case .archive: "Archive"
        }
    }

    var icon: String {
        switch self {
        case .inbox: "tray"
        case .project: "folder"
        case .area: "square.stack.3d.up"
        case .resource: "books.vertical"
        case .archive: "archivebox"
        }
    }

    var color: String {
        switch self {
        case .inbox: "gray"
        case .project: "blue"
        case .area: "green"
        case .resource: "orange"
        case .archive: "secondary"
        }
    }
}
