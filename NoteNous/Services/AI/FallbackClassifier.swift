import Foundation

struct FallbackClassifier {
    static func classify(title: String, content: String, sourceURL: String?) -> (PARACategory, NoteType, CODEStage) {
        let text = "\(title) \(content)".lowercased()
        let length = content.count

        // PARA Category
        let para: PARACategory
        if sourceURL != nil && !sourceURL!.isEmpty {
            para = .resource
        } else if text.contains("todo") || text.contains("prazo") || text.contains("deadline") || text.contains("entregar") {
            para = .project
        } else if length < 50 {
            para = .inbox
        } else {
            para = .inbox
        }

        // Note Type
        let noteType: NoteType
        if sourceURL != nil && !sourceURL!.isEmpty {
            noteType = .literature
        } else if length < 100 {
            noteType = .fleeting
        } else if content.contains("[[") || content.components(separatedBy: "\n").count > 10 {
            noteType = .permanent
        } else {
            noteType = .fleeting
        }

        // CODE Stage
        let codeStage: CODEStage = .captured

        return (para, noteType, codeStage)
    }
}
