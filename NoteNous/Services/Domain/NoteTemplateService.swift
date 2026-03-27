import Foundation
import os.log

/// Manages note templates for quick note creation.
/// Built-in templates are always available; custom templates persist to JSON.
final class NoteTemplateService: ObservableObject {

    // MARK: - NoteTemplate

    struct NoteTemplate: Identifiable, Codable, Equatable {
        let id: UUID
        var name: String
        var noteType: NoteType
        var titlePlaceholder: String
        var contentTemplate: String  // markdown with {{variables}}
        var contextPlaceholder: String
        var defaultPARA: PARACategory
        var defaultTags: [String]
        var isBuiltIn: Bool
        var iconName: String

        static func == (lhs: NoteTemplate, rhs: NoteTemplate) -> Bool {
            lhs.id == rhs.id
        }
    }

    // MARK: - Published State

    @Published private(set) var customTemplates: [NoteTemplate] = []

    /// All templates: built-in + custom.
    var allTemplates: [NoteTemplate] {
        Self.builtInTemplates + customTemplates
    }

    // MARK: - Private

    private let logger = Logger(subsystem: "com.notenous.app", category: "NoteTemplateService")
    private let fileURL: URL

    // MARK: - Init

    init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("NoteNous", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        self.fileURL = dir.appendingPathComponent("templates.json")

        loadFromDisk()
    }

    // MARK: - Built-In Templates

    static let builtInTemplates: [NoteTemplate] = [
        NoteTemplate(
            id: UUID(uuidString: "00000000-0001-0000-0000-000000000001")!,
            name: "Fleeting",
            noteType: .fleeting,
            titlePlaceholder: "Quick thought...",
            contentTemplate: "# {{title}}\n\n{{content}}\n\n---\n*Captured: {{date}}*",
            contextPlaceholder: "Where did this idea come from?",
            defaultPARA: .inbox,
            defaultTags: [],
            isBuiltIn: true,
            iconName: "bolt"
        ),
        NoteTemplate(
            id: UUID(uuidString: "00000000-0001-0000-0000-000000000002")!,
            name: "Literature",
            noteType: .literature,
            titlePlaceholder: "Source title...",
            contentTemplate: "# {{title}}\n\n**Source:** {{source}}\n**Author:** {{author}}\n**Page:** {{page}}\n\n## Key Ideas\n\n{{content}}\n\n## My Interpretation\n\n",
            contextPlaceholder: "Why is this source important?",
            defaultPARA: .resource,
            defaultTags: ["literature"],
            isBuiltIn: true,
            iconName: "book"
        ),
        NoteTemplate(
            id: UUID(uuidString: "00000000-0001-0000-0000-000000000003")!,
            name: "Permanent",
            noteType: .permanent,
            titlePlaceholder: "Atomic claim...",
            contentTemplate: "# {{title}}\n\n{{content}}\n\n## Evidence\n\n## Connections\n\n## Implications\n\n",
            contextPlaceholder: "How does this connect to your thinking?",
            defaultPARA: .resource,
            defaultTags: [],
            isBuiltIn: true,
            iconName: "diamond"
        ),
        NoteTemplate(
            id: UUID(uuidString: "00000000-0001-0000-0000-000000000004")!,
            name: "Structure (Hub)",
            noteType: .structure,
            titlePlaceholder: "Topic hub...",
            contentTemplate: "# {{title}}\n\n## Overview\n\n{{content}}\n\n## Key Notes\n\n- [[note1]]\n- [[note2]]\n\n## Open Questions\n\n",
            contextPlaceholder: "What theme does this hub organize?",
            defaultPARA: .resource,
            defaultTags: ["hub"],
            isBuiltIn: true,
            iconName: "folder"
        ),
        NoteTemplate(
            id: UUID(uuidString: "00000000-0001-0000-0000-000000000005")!,
            name: "Meeting",
            noteType: .fleeting,
            titlePlaceholder: "Meeting topic...",
            contentTemplate: "# Meeting: {{title}}\n\n**Date:** {{date}}\n**Participants:**\n\n## Agenda\n\n## Notes\n\n## Action Items\n\n- [ ] \n",
            contextPlaceholder: "Meeting purpose or follow-up context",
            defaultPARA: .project,
            defaultTags: ["meeting"],
            isBuiltIn: true,
            iconName: "person.3"
        ),
        NoteTemplate(
            id: UUID(uuidString: "00000000-0001-0000-0000-000000000006")!,
            name: "Book Note",
            noteType: .literature,
            titlePlaceholder: "Book title...",
            contentTemplate: "# {{title}}\n\n**Author:** {{author}}\n**Rating:** /5\n\n## Summary\n\n## Key Quotes\n\n## My Thoughts\n\n",
            contextPlaceholder: "Why did you read this?",
            defaultPARA: .resource,
            defaultTags: ["book"],
            isBuiltIn: true,
            iconName: "text.book.closed"
        ),
        NoteTemplate(
            id: UUID(uuidString: "00000000-0001-0000-0000-000000000007")!,
            name: "Idea",
            noteType: .fleeting,
            titlePlaceholder: "The idea in one sentence...",
            contentTemplate: "# {{title}}\n\n## The Idea\n\n{{content}}\n\n## Why It Matters\n\n## How to Test\n\n",
            contextPlaceholder: "What triggered this idea?",
            defaultPARA: .inbox,
            defaultTags: ["idea"],
            isBuiltIn: true,
            iconName: "lightbulb"
        ),
        NoteTemplate(
            id: UUID(uuidString: "00000000-0001-0000-0000-000000000008")!,
            name: "Argument",
            noteType: .permanent,
            titlePlaceholder: "Claim to argue...",
            contentTemplate: "# {{title}}\n\n## Claim\n\n{{content}}\n\n## Evidence For\n\n## Evidence Against\n\n## Conclusion\n\n",
            contextPlaceholder: "What debate does this contribute to?",
            defaultPARA: .resource,
            defaultTags: ["argument"],
            isBuiltIn: true,
            iconName: "scale.3d"
        ),
        NoteTemplate(
            id: UUID(uuidString: "00000000-0001-0000-0000-000000000009")!,
            name: "Observation",
            noteType: .fleeting,
            titlePlaceholder: "What you observed...",
            contentTemplate: "# {{title}}\n\n## What I Observed\n\n{{content}}\n\n## Context\n\n## Significance\n\n",
            contextPlaceholder: "Where and when was this observed?",
            defaultPARA: .inbox,
            defaultTags: ["observation"],
            isBuiltIn: true,
            iconName: "eye"
        ),
    ]

    // MARK: - Custom Template CRUD

    @discardableResult
    func addCustomTemplate(
        name: String,
        noteType: NoteType,
        titlePlaceholder: String = "",
        contentTemplate: String = "",
        contextPlaceholder: String = "",
        defaultPARA: PARACategory = .inbox,
        defaultTags: [String] = [],
        iconName: String = "doc"
    ) -> NoteTemplate {
        let template = NoteTemplate(
            id: UUID(),
            name: name,
            noteType: noteType,
            titlePlaceholder: titlePlaceholder,
            contentTemplate: contentTemplate,
            contextPlaceholder: contextPlaceholder,
            defaultPARA: defaultPARA,
            defaultTags: defaultTags,
            isBuiltIn: false,
            iconName: iconName
        )
        customTemplates.append(template)
        saveToDisk()
        logger.info("Added custom template: \(name)")
        return template
    }

    func updateCustomTemplate(_ template: NoteTemplate) {
        guard !template.isBuiltIn else {
            logger.warning("Cannot update built-in template: \(template.name)")
            return
        }
        guard let index = customTemplates.firstIndex(where: { $0.id == template.id }) else {
            logger.warning("Template not found: \(template.id.uuidString)")
            return
        }
        customTemplates[index] = template
        saveToDisk()
    }

    func deleteCustomTemplate(id: UUID) {
        customTemplates.removeAll { $0.id == id }
        saveToDisk()
    }

    func template(for id: UUID) -> NoteTemplate? {
        allTemplates.first { $0.id == id }
    }

    // MARK: - Template Rendering

    /// Render a template by substituting {{variables}} with provided values.
    func render(template: NoteTemplate, values: [String: String]) -> (title: String, content: String, context: String) {
        var content = template.contentTemplate
        var title = template.titlePlaceholder
        var contextNote = template.contextPlaceholder

        // Standard variables
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .medium
        dateFormatter.timeStyle = .short
        let dateString = dateFormatter.string(from: Date())

        var allValues = values
        allValues["date"] = allValues["date"] ?? dateString

        for (key, value) in allValues {
            content = content.replacingOccurrences(of: "{{\(key)}}", with: value)
            if key == "title" && !value.isEmpty {
                title = value
            }
        }

        // Clean remaining placeholders
        let placeholderPattern = #"\{\{[^}]+\}\}"#
        if let regex = try? NSRegularExpression(pattern: placeholderPattern) {
            let range = NSRange(content.startIndex..., in: content)
            content = regex.stringByReplacingMatches(in: content, range: range, withTemplate: "")
        }

        return (title, content, contextNote)
    }

    // MARK: - Persistence

    private func saveToDisk() {
        do {
            let data = try JSONEncoder().encode(customTemplates)
            try data.write(to: fileURL, options: .atomicWrite)
        } catch {
            logger.error("Failed to save templates: \(error.localizedDescription)")
        }
    }

    private func loadFromDisk() {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            logger.info("No templates file found, starting fresh")
            return
        }
        do {
            let data = try Data(contentsOf: fileURL)
            customTemplates = try JSONDecoder().decode([NoteTemplate].self, from: data)
            logger.info("Loaded \(self.customTemplates.count) custom templates from disk")
        } catch {
            logger.error("Failed to load templates: \(error.localizedDescription)")
            customTemplates = []
        }
    }
}
