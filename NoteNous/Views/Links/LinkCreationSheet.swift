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
                    .font(.headline)
                Spacer()
                Button("Cancel") { dismiss() }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
            }
            .padding()

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Source Note (read-only)
                    sourceNoteSection

                    Divider()

                    // Target Note (searchable)
                    targetNoteSection

                    Divider()

                    // Link Type
                    linkTypeSection

                    // Context
                    contextSection

                    // Strength
                    strengthSection
                }
                .padding()
            }

            Divider()

            // Footer
            HStack {
                if showError {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
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
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                Image(systemName: "doc.text")
                    .foregroundStyle(.blue)
                VStack(alignment: .leading, spacing: 2) {
                    Text(sourceNote.title.isEmpty ? "Untitled" : sourceNote.title)
                        .font(.callout.weight(.medium))
                    if let zettelId = sourceNote.zettelId {
                        Text(zettelId)
                            .font(.caption2)
                            .monospaced()
                            .foregroundStyle(.tertiary)
                    }
                }
                Spacer()
                NoteTypeBadge(type: sourceNote.noteType)
            }
            .padding(8)
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 6))
        }
    }

    // MARK: - Target Note Section

    private var targetNoteSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("TO")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            // Search field
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search for a note...", text: $searchQuery)
                    .textFieldStyle(.plain)
                    .onChange(of: searchQuery) { performSearch() }
            }
            .padding(8)
            .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 6))

            // Selected target display
            if let target = selectedTarget {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text(target.title.isEmpty ? "Untitled" : target.title)
                        .font(.callout)
                    Spacer()
                    Button {
                        selectedTarget = nil
                        searchQuery = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(8)
                .background(.green.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
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
                                    .font(.callout)
                                    .lineLimit(1)
                                Spacer()
                                if let zettelId = note.zettelId {
                                    Text(zettelId)
                                        .font(.caption2)
                                        .monospaced()
                                        .foregroundStyle(.tertiary)
                                }
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 6)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)

                        if note.objectID != searchResults.last?.objectID {
                            Divider()
                        }
                    }
                }
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 6))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(.separator, lineWidth: 0.5)
                )

                if searchResults.isEmpty {
                    Text("No matching notes found")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 4)
                }
            }
        }
    }

    // MARK: - Link Type Section

    private var linkTypeSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("LINK TYPE")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

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
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            TextField("Why does this link exist?", text: $linkContext, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(2...4)
                .padding(8)
                .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 6))
        }
    }

    // MARK: - Strength Section

    private var strengthSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("STRENGTH")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(Int(strength * 100))%")
                    .font(.caption)
                    .monospaced()
                    .foregroundStyle(.secondary)
            }

            Slider(value: $strength, in: 0...1, step: 0.1)

            HStack {
                Text("Weak")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                Spacer()
                Text("Strong")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
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
