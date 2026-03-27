import Foundation

enum LinkType: Int16, CaseIterable, Identifiable, Codable {
    case reference = 0
    case supports = 1
    case contradicts = 2
    case extends = 3
    case example = 4

    var id: Int16 { rawValue }

    var label: String {
        switch self {
        case .reference: "References"
        case .supports: "Supports"
        case .contradicts: "Contradicts"
        case .extends: "Extends"
        case .example: "Example of"
        }
    }
}
