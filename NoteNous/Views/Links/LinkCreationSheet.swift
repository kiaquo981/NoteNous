import SwiftUI
import CoreData

struct LinkCreationSheet: View {
    let sourceNote: NoteEntity

    @Environment(\.managedObjectContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var searchQuery = ""
    @State private var searchResults: [NoteEntity] = []
    @State private var selectedTarget: NoteEntity?
    @State private var selectedLinkType: LinkType = .reference
    @State private var linkContext = ""
    @State private var strength: Float = 0.5
    @State private var showError = false
    @State private var errorMessage = ""

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Create Link")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Moros.textMain)
                Spacer()
                Button("Cancel") { dismiss() }
                    .buttonStyle(.plain)
                    .foregroundStyle(Moros.textDim)
            }
            .padding()

            Rectangle().fill(Moros.border).frame(height: 1)

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Source Note (read-only)
                    sourceNoteSection

                    Rectangle().fill(Moros.border).frame(height: 1)

                    // Target Note (searchable)
                    targetNoteSection

                    Rectangle().fill(Moros.border).frame(height: 1)

                    // Link Type
                    linkTypeSection

                    // Context
                    contextSection

                    // Strength
                    strengthSection
                }
                .padding()
            }

            Rectangle().fill(Moros.border).frame(height: 1)

            // Footer
            HStack {
                if showError {
                    Text(errorMessage)
                        .font(Moros.fontCaption)
                        .foregroundStyle(Moros.signal)
                }

                Spacer()

                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.escape)

                Button("Create Link") { createLink() }
                    .keyboardShortcut(.return)
                    .buttonStyle(.borderedProminent)
                    .disabled(selectedTarget == nil)
            }
            .padding()
        }
        .frame(width: 480, height: 560)

    }

    // MARK: - Source Note Section

    private var sourceNoteSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("FROM")
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .foregroundStyle(Moros.textDim)

            HStack(spacing: 8) {
                Image(systemName: "doc.text")
                    .foregroundStyle(Moros.oracle)
                VStack(alignment: .leading, spacing: 2) {
                    Text(sourceNote.title.isEmpty ? "Untitled" : sourceNote.title)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Moros.textMain)
                    if let zettelId = sourceNote.zettelId {
                        Text(zettelId)
                            .font(Moros.fontMonoSmall)
                            .foregroundStyle(Moros.textDim)
                    }
                }
                Spacer()
                NoteTypeBadge(type: sourceNote.noteType)
            }
            .padding(8)
            .background(Moros.limit02, in: Rectangle())
        }
    }

    // MARK: - Target Note Section

    private var targetNoteSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("TO")
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .foregroundStyle(Moros.textDim)

            // Search field
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(Moros.textDim)
                TextField("Search for a note...", text: $searchQuery)
                    .textFieldStyle(.plain)
                    .foregroundStyle(Moros.textMain)
                    .onChange(of: searchQuery) { performSearch() }
            }
            .padding(8)
            .background(Moros.limit02, in: Rectangle())

            // Selected target display
            if let target = selectedTarget {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Moros.verdit)
                    Text(target.title.isEmpty ? "Untitled" : target.title)
                        .font(Moros.fontBody)
                        .foregroundStyle(Moros.textMain)
                    Spacer()
                    Button {
                        selectedTarget = nil
                        searchQuery = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(Moros.textDim)
                    }
                    .buttonStyle(.plain)
                }
                .padding(8)
                .background(Moros.verdit.opacity(0.08), in: Rectangle())
            }

            // Search results
            if !searchQuery.isEmpty && selectedTarget == nil {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(searchResults, id: \.objectID) { note in
                        Button {
                            selectedTarget = note
                            searchQuery = note.title
                        } label: {
                            HStack(spacing: 8) {
                                NoteTypeBadge(type: note.noteType)
                                Text(note.title.isEmpty ? "Untitled" : note.title)
                                    .font(Moros.fontBody)
                                    .foregroundStyle(Moros.textMain)
                                    .lineLimit(1)
                                Spacer()
                                if let zettelId = note.zettelId {
                                    Text(zettelId)
                                        .font(Moros.fontMonoSmall)
                                        .foregroundStyle(Moros.textDim)
                                }
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 6)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)

                        if note.objectID != searchResults.last?.objectID {
                            Rectangle().fill(Moros.border).frame(height: 1)
                        }
                    }
                }
                .background(Moros.limit02, in: Rectangle())
                .overlay(
                    Rectangle()
                        .stroke(Moros.borderLit, lineWidth: 1)
                )

                if searchResults.isEmpty {
                    Text("No matching notes found")
                        .font(Moros.fontCaption)
                        .foregroundStyle(Moros.textDim)
                        .padding(.vertical, 4)
                }
            }
        }
    }

    // MARK: - Link Type Section

    private var linkTypeSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("LINK TYPE")
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .foregroundStyle(Moros.textDim)

            Picker("Link Type", selection: $selectedLinkType) {
                ForEach(LinkType.allCases) { type in
                    Text(type.label).tag(type)
                }
            }
            .pickerStyle(.segmented)
        }
    }

    // MARK: - Context Section

    private var contextSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("CONTEXT")
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .foregroundStyle(Moros.textDim)

            TextField("Why does this link exist?", text: $linkContext, axis: .vertical)
                .textFieldStyle(.plain)
                .foregroundStyle(Moros.textMain)
                .lineLimit(2...4)
                .padding(8)
                .background(Moros.limit02, in: Rectangle())
        }
    }

    // MARK: - Strength Section

    private var strengthSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("STRENGTH")
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundStyle(Moros.textDim)
                Spacer()
                Text("\(Int(strength * 100))%")
                    .font(Moros.fontMonoSmall)
                    .foregroundStyle(Moros.textDim)
            }

            Slider(value: $strength, in: 0...1, step: 0.1)

            HStack {
                Text("Weak")
                    .font(Moros.fontMicro)
                    .foregroundStyle(Moros.textDim)
                Spacer()
                Text("Strong")
                    .font(Moros.fontMicro)
                    .foregroundStyle(Moros.textDim)
            }
        }
    }

    // MARK: - Actions

    private func performSearch() {
        guard !searchQuery.isEmpty else {
            searchResults = []
            return
        }

        let parser = WikilinkParser(context: context)
        searchResults = parser.searchNotes(matching: searchQuery, limit: 10)
            .filter { $0.objectID != sourceNote.objectID }
    }

    private func createLink() {
        guard let target = selectedTarget else {
            errorMessage = "Please select a target note."
            showError = true
            return
        }

        let linkService = LinkService(context: context)
        let result = linkService.createLink(
            from: sourceNote,
            to: target,
            type: selectedLinkType,
            context: linkContext.isEmpty ? nil : linkContext,
            strength: strength
        )

        if result == nil {
            errorMessage = "Link already exists or cannot link to self."
            showError = true
            return
        }

        dismiss()
    }
}
