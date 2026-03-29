import SwiftUI
import CoreData

/// Visual pipeline showing the Zettelkasten workflow:
/// CAPTURE -> PROCESS -> CONNECT -> EXPRESS
/// Each stage shows count, clicking shows notes, health indicators for stale fleeting notes.
struct ProcessingPipeline: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.managedObjectContext) private var context

    @State private var selectedStage: CODEStage? = nil

    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \NoteEntity.updatedAt, ascending: false)],
        predicate: NSPredicate(format: "isArchived == NO"),
        animation: .default
    ) private var allNotes: FetchedResults<NoteEntity>

    var body: some View {
        VStack(spacing: 0) {
            pipelineHeader
            Rectangle().fill(Moros.border).frame(height: 1)
            pipelineStages
            Rectangle().fill(Moros.border).frame(height: 1)
            healthBar
            Rectangle().fill(Moros.border).frame(height: 1)

            if let stage = selectedStage {
                stageNotesList(stage)
            } else {
                emptyDetail
            }
        }

    }

    // MARK: - Header

    private var pipelineHeader: some View {
        HStack {
            Image(systemName: "arrow.right.arrow.left")
                .foregroundStyle(Moros.oracle)
            Text("Processing Pipeline")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Moros.textMain)
            Spacer()
            Text("\(allNotes.count) total notes")
                .font(Moros.fontMonoSmall)
                .foregroundStyle(Moros.textDim)
        }
        .padding()
    }

    // MARK: - Pipeline Stages

    private var pipelineStages: some View {
        HStack(spacing: 0) {
            stageBlock(
                stage: .captured,
                icon: "bolt.fill",
                label: "CAPTURE",
                subtitle: "Fleeting notes",
                color: Moros.ambient
            )
            arrowSeparator
            stageBlock(
                stage: .organized,
                icon: "folder.badge.gearshape",
                label: "PROCESS",
                subtitle: "Develop & refine",
                color: Moros.oracle
            )
            arrowSeparator
            stageBlock(
                stage: .distilled,
                icon: "link",
                label: "CONNECT",
                subtitle: "Link & index",
                color: Moros.verdit
            )
            arrowSeparator
            stageBlock(
                stage: .expressed,
                icon: "pencil.line",
                label: "EXPRESS",
                subtitle: "Use in writing",
                color: Moros.verdit.opacity(0.7)
            )
        }
        .padding(.vertical, 16)
        .padding(.horizontal, 8)
    }

    private func stageBlock(stage: CODEStage, icon: String, label: String, subtitle: String, color: Color) -> some View {
        let count = notesInStage(stage)
        let isSelected = selectedStage == stage

        return Button {
            if selectedStage == stage {
                selectedStage = nil
            } else {
                selectedStage = stage
            }
        } label: {
            VStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 20))
                    .foregroundStyle(color)

                Text("\(count)")
                    .font(.system(size: 22, weight: .light, design: .monospaced))
                    .foregroundStyle(Moros.textMain)

                Text(label)
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundStyle(color)

                Text(subtitle)
                    .font(Moros.fontMicro)
                    .foregroundStyle(Moros.textDim)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(isSelected ? color.opacity(0.08) : .clear, in: Rectangle())
            .overlay(Rectangle().stroke(isSelected ? color.opacity(0.3) : .clear, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private var arrowSeparator: some View {
        Image(systemName: "chevron.right")
            .font(.system(size: 14))
            .foregroundStyle(Moros.textGhost)
            .frame(width: 20)
    }

    // MARK: - Health Bar

    private var healthBar: some View {
        let staleCount = staleFleetingCount
        let weekProcessed = processedThisWeek

        return HStack(spacing: 16) {
            HStack(spacing: 6) {
                Circle()
                    .fill(staleCount > 0 ? Moros.signal : Moros.verdit)
                    .frame(width: 6, height: 6)
                Text(staleCount > 0 ? "\(staleCount) fleeting notes older than 7 days" : "No stale fleeting notes")
                    .font(Moros.fontCaption)
                    .foregroundStyle(staleCount > 0 ? Moros.signal : Moros.textSub)
            }

            Spacer()

            Text("\(weekProcessed) processed this week")
                .font(Moros.fontMonoSmall)
                .foregroundStyle(Moros.textDim)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    // MARK: - Stage Notes List

    private func stageNotesList(_ stage: CODEStage) -> some View {
        let notes = allNotes.filter { $0.codeStage == stage }

        return Group {
            if notes.isEmpty {
                VStack(spacing: 8) {
                    Text("No notes in \(stage.label)")
                        .font(Moros.fontBody)
                        .foregroundStyle(Moros.textDim)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(notes, id: \.objectID) { note in
                        pipelineNoteRow(note, currentStage: stage)
                            .listRowBackground(Moros.limit01)
                    }
                }
                .listStyle(.inset(alternatesRowBackgrounds: false))
        
            }
        }
    }

    private func pipelineNoteRow(_ note: NoteEntity, currentStage: CODEStage) -> some View {
        HStack(spacing: 10) {
            Image(systemName: note.noteType.icon)
                .font(.system(size: 11))
                .foregroundStyle(noteTypeColor(note.noteType))
                .frame(width: 16)

            VStack(alignment: .leading, spacing: 2) {
                Text(note.title.isEmpty ? "Untitled" : note.title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Moros.textMain)
                    .lineLimit(1)
                HStack(spacing: 8) {
                    Text(note.zettelId ?? "?")
                        .font(Moros.fontMonoSmall)
                        .foregroundStyle(Moros.textDim)
                    Text(note.noteType.label)
                        .font(Moros.fontMicro)
                        .foregroundStyle(Moros.textDim)
                }
            }

            Spacer()

            // Advance button
            if let nextStage = nextStage(after: currentStage) {
                Button {
                    note.codeStage = nextStage
                    note.updatedAt = Date()
                    try? context.save()
                } label: {
                    HStack(spacing: 4) {
                        Text(nextStage.label)
                            .font(Moros.fontMicro)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 8))
                    }
                    .foregroundStyle(Moros.oracle)
                }
                .buttonStyle(.plain)
            }

            // Open button
            Button {
                appState.selectedNote = note
            } label: {
                Image(systemName: "arrow.forward.square")
                    .font(.system(size: 12))
                    .foregroundStyle(Moros.textSub)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 4)
    }

    private var emptyDetail: some View {
        VStack(spacing: 8) {
            Image(systemName: "hand.tap")
                .font(.system(size: 28))
                .foregroundStyle(Moros.textGhost)
            Text("Select a pipeline stage to see its notes")
                .font(Moros.fontBody)
                .foregroundStyle(Moros.textDim)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Helpers

    private func notesInStage(_ stage: CODEStage) -> Int {
        allNotes.filter { $0.codeStage == stage }.count
    }

    private var staleFleetingCount: Int {
        let sevenDaysAgo = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
        return allNotes.filter { note in
            note.noteType == .fleeting &&
            (note.createdAt ?? Date()) < sevenDaysAgo
        }.count
    }

    private var processedThisWeek: Int {
        let weekAgo = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
        return allNotes.filter { note in
            note.codeStage != .captured &&
            (note.updatedAt ?? Date()) > weekAgo
        }.count
    }

    private func nextStage(after stage: CODEStage) -> CODEStage? {
        switch stage {
        case .captured: return .organized
        case .organized: return .distilled
        case .distilled: return .expressed
        case .expressed: return nil
        }
    }

    private func noteTypeColor(_ type: NoteType) -> Color {
        switch type {
        case .fleeting: Moros.ambient
        case .literature: Moros.oracle
        case .permanent: Moros.verdit
        case .structure: Moros.textSub
        }
    }
}
