import SwiftUI
import CoreData

// MARK: - Section model for grouping cards on the canvas

@Observable
@MainActor
final class DeskSection: Identifiable {
    let id: UUID
    var title: String
    var origin: CGPoint
    var size: CGSize
    var noteIds: [UUID]
    var colorHex: String

    init(
        id: UUID = UUID(),
        title: String = "Untitled Section",
        origin: CGPoint = .zero,
        size: CGSize = CGSize(width: 500, height: 400),
        noteIds: [UUID] = [],
        colorHex: String = "6B7280"
    ) {
        self.id = id
        self.title = title
        self.origin = origin
        self.size = size
        self.noteIds = noteIds
        self.colorHex = colorHex
    }
}

// MARK: - Section state manager

@Observable
@MainActor
final class DeskSectionStore {
    var sections: [DeskSection] = []
    var editingSectionId: UUID?

    func addSection(at canvasPoint: CGPoint) -> DeskSection {
        let section = DeskSection(origin: canvasPoint)
        sections.append(section)
        return section
    }

    func removeSection(_ id: UUID) {
        sections.removeAll { $0.id == id }
    }

    func moveSection(_ id: UUID, to origin: CGPoint) {
        guard let section = sections.first(where: { $0.id == id }) else { return }
        section.origin = origin
    }

    func assignNote(_ noteId: UUID, to sectionId: UUID) {
        guard let section = sections.first(where: { $0.id == sectionId }) else { return }
        if !section.noteIds.contains(noteId) {
            section.noteIds.append(noteId)
        }
    }

    func removeNote(_ noteId: UUID, from sectionId: UUID) {
        guard let section = sections.first(where: { $0.id == sectionId }) else { return }
        section.noteIds.removeAll { $0 == noteId }
    }

    func section(containing noteId: UUID) -> DeskSection? {
        sections.first { $0.noteIds.contains(noteId) }
    }

    func reorderSections(from: IndexSet, to: Int) {
        sections.move(fromOffsets: from, toOffset: to)
    }

    /// Color distribution for a section (hex -> count).
    func colorDistribution(for section: DeskSection, notes: [NoteEntity]) -> [(String, Int)] {
        let sectionNotes = notes.filter { note in
            guard let id = note.id else { return false }
            return section.noteIds.contains(id)
        }

        var counts: [String: Int] = [:]
        for note in sectionNotes {
            let hex = note.colorHex ?? "none"
            counts[hex, default: 0] += 1
        }

        return counts.sorted { $0.value > $1.value }
    }

    /// Export sections as an ordered outline.
    func exportOutline(notes: [NoteEntity]) -> String {
        var output = ""
        for (index, section) in sections.enumerated() {
            output += "## \(index + 1). \(section.title)\n\n"
            let sectionNotes = notes.filter { note in
                guard let id = note.id else { return false }
                return section.noteIds.contains(id)
            }
            for note in sectionNotes {
                let zettel = note.zettelId ?? "?"
                output += "- [\(zettel)] \(note.title)\n"
            }
            output += "\n"
        }
        return output
    }
}

// MARK: - Section view rendered on the canvas

struct DeskSectionView: View {
    let section: DeskSection
    let zoomLevel: CGFloat
    let isEditing: Bool
    let noteCount: Int
    let onTitleChanged: (String) -> Void
    let onDragChanged: (DragGesture.Value) -> Void
    let onDragEnded: (DragGesture.Value) -> Void
    let onDelete: () -> Void

    @State private var editTitle: String = ""
    @State private var isHovered: Bool = false

    var body: some View {
        ZStack(alignment: .topLeading) {
            // Section background
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(hex: section.colorHex).opacity(0.06))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(
                            Color(hex: section.colorHex).opacity(0.3),
                            style: StrokeStyle(lineWidth: 1.5, dash: [8, 4])
                        )
                )

            // Header
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Image(systemName: "folder")
                        .font(.system(size: 11))
                        .foregroundStyle(Color(hex: section.colorHex))

                    if isEditing {
                        TextField("Section title", text: $editTitle, onCommit: {
                            onTitleChanged(editTitle)
                        })
                        .textFieldStyle(.plain)
                        .font(.system(size: 13, weight: .semibold))
                        .onAppear { editTitle = section.title }
                    } else {
                        Text(section.title)
                            .font(.system(size: 13, weight: .semibold))
                    }

                    Spacer()

                    Text("\(noteCount) cards")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)

                    if isHovered {
                        Button(action: onDelete) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.top, 10)
            }
        }
        .frame(width: section.size.width, height: section.size.height)
        .onHover { isHovered = $0 }
        .gesture(
            DragGesture(minimumDistance: 4)
                .onChanged(onDragChanged)
                .onEnded(onDragEnded)
        )
    }
}

// MARK: - Section list sidebar panel

struct DeskSectionListPanel: View {
    let sectionStore: DeskSectionStore
    let notes: [NoteEntity]
    let onSelectSection: (DeskSection) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Sections")
                    .font(.system(size: 12, weight: .semibold))
                Spacer()
                Button {
                    _ = sectionStore.addSection(at: CGPoint(x: 100, y: 100))
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 11))
                }
                .buttonStyle(.plain)
            }

            if sectionStore.sections.isEmpty {
                Text("No sections yet. Right-click canvas or press Cmd+G to create one.")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                    .padding(.vertical, 8)
            } else {
                List {
                    ForEach(sectionStore.sections) { section in
                        sectionRow(section)
                            .onTapGesture { onSelectSection(section) }
                    }
                    .onMove { from, to in
                        sectionStore.reorderSections(from: from, to: to)
                    }
                }
                .listStyle(.plain)
            }

            if !sectionStore.sections.isEmpty {
                Divider()
                Button {
                    let outline = sectionStore.exportOutline(notes: notes)
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(outline, forType: .string)
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "doc.on.doc")
                            .font(.system(size: 10))
                        Text("Copy Outline")
                            .font(.system(size: 11))
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(12)
        .frame(width: 220)
    }

    private func sectionRow(_ section: DeskSection) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(Color(hex: section.colorHex))
                .frame(width: 8, height: 8)
            Text(section.title)
                .font(.system(size: 11))
                .lineLimit(1)
            Spacer()
            Text("\(section.noteIds.count)")
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 2)
    }
}
