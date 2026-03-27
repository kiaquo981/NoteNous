import SwiftUI
import CoreData

/// Sheet that helps split a non-atomic note into two or more atomic notes.
/// Shows content with heading markers highlighted, lets user pick a split point,
/// and creates two new linked notes from the halves.
struct SplitNoteSheet: View {
    @ObservedObject var note: NoteEntity
    @Environment(\.managedObjectContext) private var context
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var splitIndex: Int = 0
    @State private var leftTitle: String = ""
    @State private var rightTitle: String = ""
    @State private var contentLines: [String] = []
    @State private var suggestedSplits: [Int] = []

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("SPLIT NOTE")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundStyle(Moros.signal)
                    Text("Divide into atomic ideas")
                        .font(Moros.fontCaption)
                        .foregroundStyle(Moros.textDim)
                }
                Spacer()
                Button("Cancel") { dismiss() }
                    .foregroundStyle(Moros.textSub)
                    .buttonStyle(.plain)
            }
            .padding()

            Rectangle().fill(Moros.border).frame(height: 1)

            // Suggested split points
            if !suggestedSplits.isEmpty {
                HStack(spacing: 8) {
                    Text("SUGGESTED SPLITS:")
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundStyle(Moros.textDim)

                    ForEach(suggestedSplits, id: \.self) { idx in
                        Button(action: { splitIndex = idx }) {
                            Text("Line \(idx + 1)")
                                .font(.system(size: 10, weight: .medium, design: .monospaced))
                                .foregroundStyle(splitIndex == idx ? Moros.void : Moros.oracle)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(splitIndex == idx ? Moros.oracle : Moros.oracle.opacity(0.1), in: Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                    Spacer()
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
                .background(Moros.oracle.opacity(0.04))
            }

            // Content with split line
            HStack(alignment: .top, spacing: 0) {
                // Left half preview
                VStack(alignment: .leading, spacing: 6) {
                    Text("NOTE A")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundStyle(Moros.verdit)

                    TextField("Title for first note...", text: $leftTitle)
                        .textFieldStyle(.plain)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Moros.textMain)

                    Rectangle().fill(Moros.border).frame(height: 1)

                    ScrollView {
                        Text(leftContent)
                            .font(.system(size: 11))
                            .foregroundStyle(Moros.textSub)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(12)
                .background(Moros.limit02)
                .overlay(Rectangle().stroke(Moros.verdit.opacity(0.3), lineWidth: 1))

                // Divider with drag
                VStack(spacing: 4) {
                    Spacer()
                    Image(systemName: "scissors")
                        .font(.system(size: 16))
                        .foregroundStyle(Moros.signal)
                    Text("Line \(splitIndex + 1)")
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(Moros.textDim)

                    // Line stepper
                    VStack(spacing: 2) {
                        Button(action: { if splitIndex > 0 { splitIndex -= 1 } }) {
                            Image(systemName: "chevron.up")
                                .font(.system(size: 10))
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(Moros.textSub)

                        Button(action: { if splitIndex < contentLines.count - 1 { splitIndex += 1 } }) {
                            Image(systemName: "chevron.down")
                                .font(.system(size: 10))
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(Moros.textSub)
                    }
                    Spacer()
                }
                .frame(width: 50)
                .background(Moros.signal.opacity(0.06))

                // Right half preview
                VStack(alignment: .leading, spacing: 6) {
                    Text("NOTE B")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundStyle(Moros.oracle)

                    TextField("Title for second note...", text: $rightTitle)
                        .textFieldStyle(.plain)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Moros.textMain)

                    Rectangle().fill(Moros.border).frame(height: 1)

                    ScrollView {
                        Text(rightContent)
                            .font(.system(size: 11))
                            .foregroundStyle(Moros.textSub)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(12)
                .background(Moros.limit02)
                .overlay(Rectangle().stroke(Moros.oracle.opacity(0.3), lineWidth: 1))
            }
            .padding()

            Rectangle().fill(Moros.border).frame(height: 1)

            // Actions
            HStack {
                Text("Original note will be archived. Both new notes will link to each other.")
                    .font(Moros.fontCaption)
                    .foregroundStyle(Moros.textDim)

                Spacer()

                Button(action: executeSplit) {
                    HStack(spacing: 6) {
                        Image(systemName: "scissors")
                        Text("Split into 2 Notes")
                    }
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Moros.void)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Moros.signal, in: Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(leftTitle.isEmpty || rightTitle.isEmpty)
            }
            .padding()
        }
        .frame(minWidth: 700, minHeight: 500)
        .morosBackground(Moros.limit01)
        .onAppear { setupContent() }
    }

    // MARK: - Computed

    private var leftContent: String {
        guard !contentLines.isEmpty else { return "" }
        let endIdx = min(splitIndex + 1, contentLines.count)
        return contentLines[0..<endIdx].joined(separator: "\n")
    }

    private var rightContent: String {
        guard splitIndex + 1 < contentLines.count else { return "" }
        return contentLines[(splitIndex + 1)...].joined(separator: "\n")
    }

    // MARK: - Setup

    private func setupContent() {
        contentLines = note.content.components(separatedBy: "\n")

        // Find heading lines as suggested split points
        suggestedSplits = contentLines.enumerated().compactMap { idx, line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("# ") || trimmed.hasPrefix("## ") {
                // Suggest splitting BEFORE the heading (one line up)
                return max(0, idx - 1)
            }
            return nil
        }

        // If no heading splits, suggest middle
        if suggestedSplits.isEmpty && contentLines.count > 2 {
            suggestedSplits = [contentLines.count / 2]
        }

        // Default split index
        splitIndex = suggestedSplits.first ?? (contentLines.count / 2)

        // Default titles
        leftTitle = note.title + " (Part 1)"
        rightTitle = note.title + " (Part 2)"
    }

    // MARK: - Execute Split

    private func executeSplit() {
        let noteService = NoteService(context: context)
        let linkService = LinkService(context: context)

        // Create Note A
        let noteA = noteService.createNote(
            title: leftTitle,
            content: leftContent,
            paraCategory: note.paraCategory
        )
        noteA.noteType = note.noteType
        noteA.codeStage = note.codeStage
        noteA.sourceURL = note.sourceURL
        noteA.sourceTitle = note.sourceTitle

        // Create Note B
        let noteB = noteService.createNote(
            title: rightTitle,
            content: rightContent,
            paraCategory: note.paraCategory
        )
        noteB.noteType = note.noteType
        noteB.codeStage = note.codeStage
        noteB.sourceURL = note.sourceURL
        noteB.sourceTitle = note.sourceTitle

        // Copy tags
        let tagService = TagService(context: context)
        for tag in note.tagsArray {
            tagService.addTag(tag, to: noteA)
            tagService.addTag(tag, to: noteB)
        }

        // Link them to each other
        linkService.createLink(from: noteA, to: noteB, type: .extends)
        linkService.createLink(from: noteB, to: noteA, type: .extends)

        // Archive original
        noteService.archiveNote(note)

        // Navigate to first new note
        appState.selectedNote = noteA

        try? context.save()
        dismiss()
    }
}
