import Foundation

enum NoteType: Int16, CaseIterable, Identifiable, Codable {
    case fleeting = 0
    case literature = 1
    case permanent = 2

    var id: Int16 { rawValue }

    var label: String {
        switch self {
        case .fleeting: "Fleeting"
        case .literature: "Literature"
        case .permanent: "Permanent"
        }
    }

    var icon: String {
        switch self {
        case .fleeting: "bolt"
        case .literature: "book"
        case .permanent: "diamond"
        }
    }
}
