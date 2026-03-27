import SwiftUI
import CoreData
import os.log

/// Grid of template cards for quick note creation.
/// Shows built-in and custom templates with preview of structure.
struct TemplatePickerView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.managedObjectContext) private var context
    @ObservedObject var templateService: NoteTemplateService

    @State private var showCreateSheet: Bool = false
    @State private var editingTemplate: NoteTemplateService.NoteTemplate?

    private let columns = [
        GridItem(.adaptive(minimum: 180, maximum: 220), spacing: 12)
    ]

    var body: some View {
        VStack(spacing: 0) {
            headerBar

            Rectangle().fill(Moros.border).frame(height: 1)

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Built-in templates
                    sectionHeader(title: "BUILT-IN TEMPLATES", count: NoteTemplateService.builtInTemplates.count)

                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(NoteTemplateService.builtInTemplates) { template in
                            TemplateCard(template: template) {
                                createNoteFrom(template: template)
                            }
                        }
                    }

                    // Custom templates
                    if !templateService.customTemplates.isEmpty {
                        sectionHeader(title: "CUSTOM TEMPLATES", count: templateService.customTemplates.count)

                        LazyVGrid(columns: columns, spacing: 12) {
                            ForEach(templateService.customTemplates) { template in
                                TemplateCard(template: template) {
                                    createNoteFrom(template: template)
                                }
                                .contextMenu {
                                    Button("Edit") {
                                        editingTemplate = template
                                    }
                                    Button("Delete", role: .destructive) {
                                        templateService.deleteCustomTemplate(id: template.id)
                                    }
                                }
                            }
                        }
                    }

                    // Create new template button
                    Button {
                        showCreateSheet = true
                    } label: {
                        HStack {
                            Image(systemName: "plus.square.dashed")
                                .font(.system(size: 20))
                            Text("Create Custom Template")
                                .font(.system(size: 12, weight: .medium))
                        }
                        .foregroundStyle(Moros.oracle)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(Moros.oracle.opacity(0.05), in: Rectangle())
                        .overlay(
                            Rectangle()
                                .strokeBorder(Moros.oracle.opacity(0.2), style: StrokeStyle(lineWidth: 1, dash: [6, 4]))
                        )
                    }
                    .buttonStyle(.plain)
                }
                .padding(16)
            }
        }
        .morosBackground(Moros.limit02)
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showCreateSheet) {
            TemplateEditorSheet(templateService: templateService)
        }
        .sheet(item: $editingTemplate) { template in
            TemplateEditorSheet(templateService: templateService, existing: template)
        }
    }

    // MARK: - Header

    private var headerBar: some View {
        HStack(spacing: 16) {
            Label("NOTE TEMPLATES", systemImage: "doc.text")
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(Moros.oracle)

            Spacer()

            Text("\(templateService.allTemplates.count) templates")
                .font(Moros.fontMonoSmall)
                .foregroundStyle(Moros.textDim)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(Moros.limit01)
    }

    // MARK: - Section Header

    private func sectionHeader(title: String, count: Int) -> some View {
        HStack {
            Text(title)
                .font(Moros.fontLabel)
                .foregroundStyle(Moros.textDim)
            Text("(\(count))")
                .font(Moros.fontMonoSmall)
                .foregroundStyle(Moros.textGhost)
            Spacer()
        }
    }

    // MARK: - Actions

    private func createNoteFrom(template: NoteTemplateService.NoteTemplate) {
        let rendered = templateService.render(template: template, values: [:])

        let noteService = NoteService(context: context)
        let note = noteService.createNote(
            title: "",
            content: rendered.content,
            paraCategory: template.defaultPARA
        )
        note.noteType = template.noteType
        note.contextNote = template.contextPlaceholder
        do {
            try context.save()
        } catch {
            Logger(subsystem: "com.notenous.app", category: "TemplatePickerView")
                .error("Failed to save note from template: \(error.localizedDescription)")
        }
        appState.selectedNote = note
    }
}

// MARK: - Template Card

struct TemplateCard: View {
    let template: NoteTemplateService.NoteTemplate
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: template.iconName)
                        .font(.system(size: 16))
                        .foregroundStyle(typeColor)

                    Spacer()

                    NoteTypeBadge(type: template.noteType)
                }

                Text(template.name)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Moros.textMain)

                // Preview of structure
                Text(templatePreview)
                    .font(Moros.fontMonoSmall)
                    .foregroundStyle(Moros.textDim)
                    .lineLimit(4)
                    .frame(maxWidth: .infinity, alignment: .leading)

                // Tags
                if !template.defaultTags.isEmpty {
                    HStack(spacing: 4) {
                        ForEach(template.defaultTags, id: \.self) { tag in
                            Text(tag)
                                .font(Moros.fontMicro)
                                .foregroundStyle(Moros.ambient)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(Moros.ambient.opacity(0.1), in: Rectangle())
                        }
                    }
                }

                if !template.isBuiltIn {
                    Text("CUSTOM")
                        .font(Moros.fontMicro)
                        .foregroundStyle(Moros.verdit)
                }
            }
            .padding(12)
            .background(Moros.limit01, in: Rectangle())
            .overlay(
                Rectangle()
                    .strokeBorder(Moros.border, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private var typeColor: Color {
        switch template.noteType {
        case .fleeting: Moros.ambient
        case .literature: Moros.oracle
        case .permanent: Moros.verdit
        case .structure: Moros.signal
        }
    }

    private var templatePreview: String {
        // Show section headers from the template
        template.contentTemplate
            .components(separatedBy: "\n")
            .filter { line in
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                return trimmed.hasPrefix("## ") || trimmed.hasPrefix("**")
            }
            .prefix(4)
            .joined(separator: "\n")
    }
}

// MARK: - Template Editor Sheet

struct TemplateEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var templateService: NoteTemplateService

    var existing: NoteTemplateService.NoteTemplate?

    @State private var name: String = ""
    @State private var noteType: NoteType = .fleeting
    @State private var titlePlaceholder: String = ""
    @State private var contentTemplate: String = ""
    @State private var contextPlaceholder: String = ""
    @State private var defaultPARA: PARACategory = .inbox
    @State private var tagsText: String = ""
    @State private var iconName: String = "doc"

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text(existing == nil ? "CREATE TEMPLATE" : "EDIT TEMPLATE")
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Moros.oracle)
                Spacer()
                Button("Cancel") { dismiss() }
                    .font(Moros.fontCaption)
                    .foregroundStyle(Moros.textSub)
                    .buttonStyle(.plain)
            }
            .padding()

            Rectangle().fill(Moros.border).frame(height: 1)

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Name
                    field(label: "NAME") {
                        TextField("Template name", text: $name)
                            .textFieldStyle(.plain)
                            .font(Moros.fontBody)
                            .foregroundStyle(Moros.textMain)
                    }

                    // Note type
                    field(label: "NOTE TYPE") {
                        Picker("", selection: $noteType) {
                            ForEach(NoteType.allCases) { type in
                                Text(type.label).tag(type)
                            }
                        }
                        .pickerStyle(.segmented)
                    }

                    // PARA category
                    field(label: "DEFAULT PARA") {
                        Picker("", selection: $defaultPARA) {
                            ForEach(PARACategory.allCases) { cat in
                                Text(cat.label).tag(cat)
                            }
                        }
                        .pickerStyle(.segmented)
                    }

                    // Icon
                    field(label: "SF SYMBOL ICON") {
                        TextField("e.g. doc, lightbulb, brain", text: $iconName)
                            .textFieldStyle(.plain)
                            .font(Moros.fontMono)
                            .foregroundStyle(Moros.textMain)
                    }

                    // Title placeholder
                    field(label: "TITLE PLACEHOLDER") {
                        TextField("Placeholder for title field", text: $titlePlaceholder)
                            .textFieldStyle(.plain)
                            .font(Moros.fontBody)
                            .foregroundStyle(Moros.textMain)
                    }

                    // Content template
                    field(label: "CONTENT TEMPLATE (use {{title}}, {{content}}, {{date}})") {
                        TextEditor(text: $contentTemplate)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(Moros.textMain)
                            .scrollContentBackground(.hidden)
                            .frame(minHeight: 120)
                            .background(Moros.limit02)
                    }

                    // Context placeholder
                    field(label: "CONTEXT PLACEHOLDER") {
                        TextField("Placeholder for context field", text: $contextPlaceholder)
                            .textFieldStyle(.plain)
                            .font(Moros.fontBody)
                            .foregroundStyle(Moros.textMain)
                    }

                    // Tags
                    field(label: "DEFAULT TAGS (comma separated)") {
                        TextField("tag1, tag2", text: $tagsText)
                            .textFieldStyle(.plain)
                            .font(Moros.fontBody)
                            .foregroundStyle(Moros.textMain)
                    }
                }
                .padding(16)
            }

            Rectangle().fill(Moros.border).frame(height: 1)

            // Save button
            HStack {
                Spacer()
                Button {
                    saveTemplate()
                    dismiss()
                } label: {
                    Text(existing == nil ? "Create" : "Save")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(name.isEmpty ? Moros.textDim : Moros.verdit)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 8)
                        .background(name.isEmpty ? Moros.limit02 : Moros.verdit.opacity(0.1), in: Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(name.isEmpty)
            }
            .padding()
        }
        .frame(width: 500, height: 600)
        .morosBackground(Moros.limit01)
        .preferredColorScheme(.dark)
        .onAppear {
            if let t = existing {
                name = t.name
                noteType = t.noteType
                titlePlaceholder = t.titlePlaceholder
                contentTemplate = t.contentTemplate
                contextPlaceholder = t.contextPlaceholder
                defaultPARA = t.defaultPARA
                tagsText = t.defaultTags.joined(separator: ", ")
                iconName = t.iconName
            }
        }
    }

    private func field(label: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(Moros.fontLabel)
                .foregroundStyle(Moros.textDim)
            content()
                .padding(6)
                .background(Moros.limit02, in: Rectangle())
        }
    }

    private func saveTemplate() {
        let tags = tagsText
            .components(separatedBy: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        if var t = existing {
            t.name = name
            t.noteType = noteType
            t.titlePlaceholder = titlePlaceholder
            t.contentTemplate = contentTemplate
            t.contextPlaceholder = contextPlaceholder
            t.defaultPARA = defaultPARA
            t.defaultTags = tags
            t.iconName = iconName
            templateService.updateCustomTemplate(t)
        } else {
            templateService.addCustomTemplate(
                name: name,
                noteType: noteType,
                titlePlaceholder: titlePlaceholder,
                contentTemplate: contentTemplate,
                contextPlaceholder: contextPlaceholder,
                defaultPARA: defaultPARA,
                defaultTags: tags,
                iconName: iconName
            )
        }
    }
}
