import SwiftUI
import CoreData

/// Daily spaced repetition review session.
/// Shows one card at a time, with quality rating buttons.
struct ReviewSessionView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.managedObjectContext) private var context
    @ObservedObject var srsService: SpacedRepetitionService

    @State private var currentIndex: Int = 0
    @State private var showFullNote: Bool = false
    @State private var sessionCards: [SpacedRepetitionService.ReviewCard] = []
    @State private var reviewedCount: Int = 0
    @State private var totalQuality: Int = 0
    @State private var sessionStartTime: Date = Date()

    var body: some View {
        VStack(spacing: 0) {
            headerBar

            Rectangle().fill(Moros.border).frame(height: 1)

            if sessionCards.isEmpty {
                allCaughtUpView
            } else if currentIndex >= sessionCards.count {
                sessionCompleteView
            } else {
                cardView
            }
        }
        .morosBackground(Moros.void)
        .preferredColorScheme(.dark)
        .onAppear {
            sessionCards = srsService.dueCards()
            sessionStartTime = Date()
        }
    }

    // MARK: - Header

    private var headerBar: some View {
        HStack(spacing: 16) {
            Label("REVIEW SESSION", systemImage: "brain.head.profile")
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(Moros.oracle)

            Rectangle().fill(Moros.border).frame(width: 1, height: 16)

            if !sessionCards.isEmpty && currentIndex < sessionCards.count {
                Text("Card \(currentIndex + 1) of \(sessionCards.count)")
                    .font(Moros.fontCaption)
                    .foregroundStyle(Moros.textSub)
            }

            Spacer()

            if srsService.streak > 0 {
                HStack(spacing: 4) {
                    Image(systemName: "flame.fill")
                        .foregroundStyle(Moros.signal)
                    Text("\(srsService.streak)-day streak")
                        .font(Moros.fontCaption)
                        .foregroundStyle(Moros.textSub)
                }
            }

            if reviewedCount > 0 {
                Text("\(reviewedCount) reviewed")
                    .font(Moros.fontMonoSmall)
                    .foregroundStyle(Moros.verdit)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(Moros.limit01)
    }

    // MARK: - Card View

    private var cardView: some View {
        let card = sessionCards[currentIndex]
        let note = fetchNote(id: card.id)

        return VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Card metadata
                    HStack {
                        if let note = note {
                            Text(note.zettelId ?? "")
                                .font(Moros.fontMono)
                                .foregroundStyle(Moros.oracle)

                            NoteTypeBadge(type: note.noteType)
                        }

                        Spacer()

                        VStack(alignment: .trailing, spacing: 2) {
                            Text("Ease: \(String(format: "%.1f", card.easeFactor))")
                                .font(Moros.fontMonoSmall)
                                .foregroundStyle(Moros.textDim)
                            Text("Rep: \(card.repetitions)")
                                .font(Moros.fontMonoSmall)
                                .foregroundStyle(Moros.textDim)
                        }
                    }

                    // Title (always visible)
                    Text(note?.title ?? "Unknown Note")
                        .font(Moros.fontH2)
                        .foregroundStyle(Moros.textMain)

                    // Preview (first 200 chars)
                    if !showFullNote {
                        let preview = String((note?.contentPlainText ?? "").prefix(200))
                        Text(preview + (preview.count >= 200 ? "..." : ""))
                            .font(Moros.fontBody)
                            .foregroundStyle(Moros.textSub)
                            .lineSpacing(4)

                        Button {
                            withAnimation(.easeInOut(duration: Moros.animBase)) {
                                showFullNote = true
                            }
                        } label: {
                            HStack {
                                Image(systemName: "eye")
                                Text("Show full note")
                            }
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Moros.oracle)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Moros.oracle.opacity(0.1), in: Rectangle())
                        }
                        .buttonStyle(.plain)
                    } else {
                        // Full content
                        Text(note?.content ?? "")
                            .font(Moros.fontBody)
                            .foregroundStyle(Moros.textMain)
                            .lineSpacing(4)
                            .textSelection(.enabled)

                        if let contextNote = note?.contextNote, !contextNote.isEmpty {
                            Rectangle().fill(Moros.border).frame(height: 1)
                            VStack(alignment: .leading, spacing: 4) {
                                Text("CONTEXT")
                                    .font(Moros.fontLabel)
                                    .foregroundStyle(Moros.textDim)
                                Text(contextNote)
                                    .font(Moros.fontSmall)
                                    .foregroundStyle(Moros.textSub)
                            }
                        }
                    }
                }
                .padding(24)
            }

            Rectangle().fill(Moros.border).frame(height: 1)

            // Quality buttons
            qualityButtons(card: card)
        }
        .background(Moros.limit01)
    }

    // MARK: - Quality Buttons

    private func qualityButtons(card: SpacedRepetitionService.ReviewCard) -> some View {
        HStack(spacing: 12) {
            qualityButton(label: "Again", shortLabel: "0", quality: 0, color: Moros.signal)
            qualityButton(label: "Hard", shortLabel: "2", quality: 2, color: Moros.ambient)
            qualityButton(label: "Good", shortLabel: "3", quality: 3, color: Moros.oracle)
            qualityButton(label: "Easy", shortLabel: "5", quality: 5, color: Moros.verdit)
        }
        .padding()
        .background(Moros.limit02)
    }

    private func qualityButton(label: String, shortLabel: String, quality: Int, color: Color) -> some View {
        Button {
            submitReview(quality: quality)
        } label: {
            VStack(spacing: 2) {
                Text(label)
                    .font(.system(size: 12, weight: .semibold))
                Text(shortLabel)
                    .font(Moros.fontMonoSmall)
                    .foregroundStyle(color.opacity(0.6))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(color.opacity(0.1), in: Rectangle())
            .foregroundStyle(color)
        }
        .buttonStyle(.plain)
    }

    private func submitReview(quality: Int) {
        guard currentIndex < sessionCards.count else { return }
        let card = sessionCards[currentIndex]
        srsService.review(noteId: card.id, quality: quality)
        reviewedCount += 1
        totalQuality += quality

        withAnimation(.easeInOut(duration: Moros.animBase)) {
            showFullNote = false
            currentIndex += 1
        }
    }

    // MARK: - All Caught Up

    private var allCaughtUpView: some View {
        VStack(spacing: 12) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 48))
                .foregroundStyle(Moros.verdit)

            Text("All caught up!")
                .font(Moros.fontH2)
                .foregroundStyle(Moros.textMain)

            let upcoming = srsService.upcomingCards(days: 1).count
            if upcoming > 0 {
                Text("Next review: tomorrow (\(upcoming) cards)")
                    .font(Moros.fontBody)
                    .foregroundStyle(Moros.textSub)
            } else {
                Text("No reviews scheduled yet. Enroll permanent notes to start.")
                    .font(Moros.fontBody)
                    .foregroundStyle(Moros.textSub)
            }

            let srsStats = srsService.stats()
            HStack(spacing: 24) {
                statPill(label: "Enrolled", value: "\(srsStats.enrolled)")
                statPill(label: "Due this week", value: "\(srsStats.dueThisWeek)")
                statPill(label: "Avg ease", value: String(format: "%.1f", srsStats.averageEase))
            }
            .padding(.top, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Session Complete

    private var sessionCompleteView: some View {
        let elapsed = Date().timeIntervalSince(sessionStartTime)
        let minutes = Int(elapsed / 60)
        let seconds = Int(elapsed.truncatingRemainder(dividingBy: 60))
        let avgQ = reviewedCount > 0 ? Double(totalQuality) / Double(reviewedCount) : 0

        return VStack(spacing: 16) {
            Image(systemName: "trophy.fill")
                .font(.system(size: 48))
                .foregroundStyle(Moros.verdit)

            Text("Session Complete")
                .font(Moros.fontH2)
                .foregroundStyle(Moros.textMain)

            HStack(spacing: 24) {
                statPill(label: "Cards reviewed", value: "\(reviewedCount)")
                statPill(label: "Avg quality", value: String(format: "%.1f", avgQ))
                statPill(label: "Time", value: "\(minutes)m \(seconds)s")
            }

            if srsService.streak > 0 {
                HStack(spacing: 4) {
                    Image(systemName: "flame.fill")
                        .foregroundStyle(Moros.signal)
                    Text("\(srsService.streak)-day streak!")
                        .font(Moros.fontSubhead)
                        .foregroundStyle(Moros.textMain)
                }
                .padding(.top, 4)
            }

            let upcoming = srsService.upcomingCards(days: 1)
                .filter { !sessionCards.map(\.id).contains($0.id) }
                .count
            if upcoming > 0 {
                Text("Tomorrow: \(upcoming) cards due")
                    .font(Moros.fontBody)
                    .foregroundStyle(Moros.textSub)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Helpers

    private func statPill(label: String, value: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(size: 18, weight: .medium, design: .monospaced))
                .foregroundStyle(Moros.textMain)
            Text(label.uppercased())
                .font(Moros.fontLabel)
                .foregroundStyle(Moros.textDim)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Moros.limit02, in: Rectangle())
    }

    private func fetchNote(id: UUID) -> NoteEntity? {
        let request = NoteEntity.fetchRequest() as! NSFetchRequest<NoteEntity>
        request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        request.fetchLimit = 1
        return try? context.fetch(request).first
    }
}
