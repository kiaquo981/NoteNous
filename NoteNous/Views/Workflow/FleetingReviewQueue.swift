import SwiftUI
import CoreData

/// A dedicated view for processing fleeting notes into permanent notes.
/// This is the CORE workflow: capture fast -> review later -> develop or discard.
struct FleetingReviewQueue: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.managedObjectContext) private var context

    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \NoteEntity.createdAt, ascending: true)],
        predicate: NSCompoundPredicate(andPredicateWithSubpredicates: [
            NSPredicate(format: "noteTypeRaw == %d", NoteType.fleeting.rawValue),
            NSPredicate(format: "isArchived == NO")
        ]),
        animation: .default
    ) private var fleetingNotes: FetchedResults<NoteEntity>

    @State private var selectedFleetingNote: NoteEntity?
    @State private var showPromotionSheet = false
    @State private var showDiscardAlert = false
    @State private var showLiteratureSheet = false
    @State private var showMergeSheet = false
    @State private var promotionTarget: NoteEntity?
    @State private var literatureTarget: NoteEntity?
    @State private var mergeTarget: NoteEntity?

    var body: some View {
        VStack(spacing: 0) {
            // Stats bar
            statsBar

            Rectangle().fill(Moros.border).frame(height: 1)

            if fleetingNotes.isEmpty {
                emptyState
            } else {
                notesList
            }
        }

        .sheet(isPresented: $showPromotionSheet) {
            if let note = promotionTarget {
                PromotionSheet(note: note)
                    .environmentObject(appState)
            }
        }
        .sheet(isPresented: $showLiteratureSheet) {
            if let note = literatureTarget {
                LiteratureNoteSheet(existingNote: note)
                    .environment(\.managedObjectContext, context)
                    .environmentObject(appState)
            }
        }
        .sheet(isPresented: $showMergeSheet) {
            if let note = mergeTarget {
                MergeNoteSheet(sourceNote: note)
                    .environment(\.managedObjectContext, context)
                    .environmentObject(appState)
            }
        }
        .alert("Discard Note", isPresented: $showDiscardAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Archive", role: .destructive) {
                if let note = selectedFleetingNote {
                    discardNote(note)
                }
            }
        } message: {
            Text("This will archive the note. You can find it later in the Archive.")
        }
    }

    // MARK: - Stats Bar

    private var statsBar: some View {
        HStack(spacing: 16) {
            Label("\(fleetingNotes.count) fleeting", systemImage: "bolt.fill")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Moros.textMain)

            Rectangle().fill(Moros.border).frame(width: 1, height: 16)

            if let avgAge = averageAge {
                Label("Avg age: \(avgAge)", systemImage: "clock")
                    .font(Moros.fontCaption)
                    .foregroundStyle(Moros.textSub)
            }

            if let oldest = oldestAge {
                Label("Oldest: \(oldest)", systemImage: "exclamationmark.clock")
                    .font(Moros.fontCaption)
                    .foregroundStyle(oldestSeverityColor)
            }

            Rectangle().fill(Moros.border).frame(width: 1, height: 16)

            let stale = staleCount
            if stale > 0 {
                Text("\(stale) older than 7d")
                    .font(Moros.fontCaption)
                    .foregroundStyle(Moros.signal)
            }

            Spacer()

            Text("OLDEST FIRST")
                .font(.system(size: 8, weight: .medium, design: .monospaced))
                .foregroundStyle(Moros.textDim)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(Moros.limit01)
    }

    // MARK: - Notes List

    private var notesList: some View {
        List(selection: $selectedFleetingNote) {
            ForEach(fleetingNotes, id: \.objectID) { note in
                FleetingNoteCard(note: note) {
                    promotionTarget = note
                    showPromotionSheet = true
                } onConvertToLiterature: {
                    literatureTarget = note
                    showLiteratureSheet = true
                } onDiscard: {
                    selectedFleetingNote = note
                    showDiscardAlert = true
                } onDevelop: {
                    appState.navigateToNote(note)
                } onMerge: {
                    mergeTarget = note
                    showMergeSheet = true
                }
                .tag(note)
                .listRowBackground(Moros.limit01)
            }
        }
        .listStyle(.inset(alternatesRowBackgrounds: false))

    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 48))
                .foregroundStyle(Moros.verdit)
            Text("Inbox Zero")
                .font(Moros.fontH2)
                .foregroundStyle(Moros.textMain)
            Text("No fleeting notes to process. Capture something new!")
                .font(Moros.fontBody)
                .foregroundStyle(Moros.textSub)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Actions

    private func discardNote(_ note: NoteEntity) {
        let service = NoteService(context: context)
        service.archiveNote(note)
        selectedFleetingNote = nil
    }

    private func convertToLiterature(_ note: NoteEntity) {
        literatureTarget = note
        showLiteratureSheet = true
    }

    private var staleCount: Int {
        let sevenDaysAgo = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
        return fleetingNotes.filter { ($0.createdAt ?? Date()) < sevenDaysAgo }.count
    }

    // MARK: - Computed

    private var averageAge: String? {
        guard !fleetingNotes.isEmpty else { return nil }
        let now = Date()
        let totalHours = fleetingNotes.compactMap { $0.createdAt }
            .reduce(0.0) { $0 + now.timeIntervalSince($1) / 3600 }
        let avgHours = totalHours / Double(fleetingNotes.count)

        if avgHours < 24 {
            return "\(Int(avgHours))h"
        } else {
            return "\(Int(avgHours / 24))d"
        }
    }

    private var oldestAge: String? {
        guard let oldest = fleetingNotes.first?.createdAt else { return nil }
        let hours = Date().timeIntervalSince(oldest) / 3600
        if hours < 24 {
            return "\(Int(hours))h"
        } else {
            return "\(Int(hours / 24))d"
        }
    }

    private var oldestSeverityColor: Color {
        guard let oldest = fleetingNotes.first?.createdAt else { return Moros.textDim }
        let days = Calendar.current.dateComponents([.day], from: oldest, to: Date()).day ?? 0
        if days > 7 { return Moros.signal }
        if days > 1 { return Moros.ambient }
        return Moros.verdit
    }
}

// MARK: - Fleeting Note Card

struct FleetingNoteCard: View {
    @ObservedObject var note: NoteEntity

    let onPromote: () -> Void
    let onConvertToLiterature: () -> Void
    let onDiscard: () -> Void
    let onDevelop: () -> Void
    var onMerge: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                ageBadge
                Text(note.title.isEmpty ? "Untitled" : note.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Moros.textMain)
                    .lineLimit(1)
                Spacer()
                wordCountBadge
            }

            if !note.contentPlainText.isEmpty {
                Text(note.contentPlainText)
                    .font(Moros.fontSmall)
                    .foregroundStyle(Moros.textSub)
                    .lineLimit(3)
            }

            HStack(spacing: 8) {
                Button("Develop", systemImage: "pencil") {
                    onDevelop()
                }
                .buttonStyle(.borderless)
                .font(Moros.fontCaption)
                .foregroundStyle(Moros.textSub)

                Button("Promote", systemImage: "arrow.up.circle") {
                    onPromote()
                }
                .buttonStyle(.borderless)
                .font(Moros.fontCaption)
                .foregroundStyle(Moros.verdit)

                Button("Literature", systemImage: "book") {
                    onConvertToLiterature()
                }
                .buttonStyle(.borderless)
                .font(Moros.fontCaption)
                .foregroundStyle(Moros.oracle)

                if let onMerge = onMerge {
                    Button("Merge", systemImage: "arrow.triangle.merge") {
                        onMerge()
                    }
                    .buttonStyle(.borderless)
                    .font(Moros.fontCaption)
                    .foregroundStyle(Moros.ambient)
                }

                Spacer()

                Button("Discard", systemImage: "archivebox") {
                    onDiscard()
                }
                .buttonStyle(.borderless)
                .font(Moros.fontCaption)
                .foregroundStyle(Moros.signal)
            }
        }
        .padding(.vertical, 4)
    }

    private var ageBadge: some View {
        let color = ageColor
        let text = ageText

        return Text(text)
            .font(.system(size: 9, weight: .semibold, design: .monospaced))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.15), in: Rectangle())
            .foregroundStyle(color)
    }

    private var wordCountBadge: some View {
        let words = note.contentPlainText
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .count

        return Text("\(words)w")
            .font(Moros.fontMonoSmall)
            .foregroundStyle(Moros.textDim)
    }

    private var ageColor: Color {
        guard let created = note.createdAt else { return Moros.ambient }
        let days = Calendar.current.dateComponents([.day], from: created, to: Date()).day ?? 0
        if days > 7 { return Moros.signal }
        if days >= 1 { return Moros.ambient }
        return Moros.verdit
    }

    private var ageText: String {
        guard let created = note.createdAt else { return "?" }
        let hours = Int(Date().timeIntervalSince(created) / 3600)
        if hours < 1 { return "now" }
        if hours < 24 { return "\(hours)h" }
        let days = hours / 24
        return "\(days)d"
    }
}
