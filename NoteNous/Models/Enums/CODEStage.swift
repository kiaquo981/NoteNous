import Foundation

enum CODEStage: Int16, CaseIterable, Identifiable, Codable {
    case captured = 0
    case organized = 1
    case distilled = 2
    case expressed = 3

    var id: Int16 { rawValue }

    var label: String {
        switch self {
        case .captured: "Captured"
        case .organized: "Organized"
        case .distilled: "Distilled"
        case .expressed: "Expressed"
        }
    }

    var icon: String {
        switch self {
        case .captured: "square.and.arrow.down"
        case .organized: "folder.badge.gearshape"
        case .distilled: "text.badge.star"
        case .expressed: "paperplane"
        }
    }
}
