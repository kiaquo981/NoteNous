import SwiftUI
import CoreData

struct ReviewView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @StateObject private var srsService = SpacedRepetitionService()

    @State private var dueCards: [SpacedRepetitionService.ReviewCard] = []
    @State private var currentIndex = 0
    @State private var isRevealed = false
    @State private var currentNote: NoteEntity?
    @State private var completedCount = 0

    var body: some View {
        NavigationStack {
            ZStack {
                MorosIOS.void.ignoresSafeArea()

                if dueCards.isEmpty {
                    emptyState
                } else if currentIndex >= dueCards.count {
                    completedState
                } else {
                    reviewCard
                }
            }
            .navigationTitle("Review")
            .navigationBarTitleDisplayMode(.large)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    streakBadge
                }
            }
            .onAppear(perform: loadDueCards)
        }
    }

    // MARK: - Streak Badge

    private var streakBadge: some View {
        HStack(spacing: 4) {
            Image(systemName: "flame.fill")
                .foregroundColor(srsService.streak > 0 ? MorosIOS.signal : MorosIOS.textGhost)
            Text("\(srsService.streak)")
                .font(MorosIOS.fontSmall)
                .foregroundColor(srsService.streak > 0 ? MorosIOS.textMain : MorosIOS.textDim)
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: MorosIOS.spacing16) {
            Image(systemName: "brain.head.profile")
                .font(.system(size: 48))
                .foregroundColor(MorosIOS.textGhost)
            Text("No Reviews Due")
                .font(MorosIOS.fontH3)
                .foregroundColor(MorosIOS.textDim)
            Text("Permanent notes enrolled in SRS will appear here")
                .font(MorosIOS.fontSmall)
                .foregroundColor(MorosIOS.textDim)
                .multilineTextAlignment(.center)
                .padding(.horizontal, MorosIOS.spacing32)

            let stats = srsService.stats()
            if stats.enrolled > 0 {
                VStack(spacing: MorosIOS.spacing8) {
                    Text("\(stats.enrolled) enrolled")
                        .font(MorosIOS.fontCaption)
                        .foregroundColor(MorosIOS.ambient)
                    Text("\(stats.dueThisWeek) due this week")
                        .font(MorosIOS.fontCaption)
                        .foregroundColor(MorosIOS.ambient)
                }
                .padding(.top, MorosIOS.spacing8)
            }
        }
    }

    // MARK: - Completed State

    private var completedState: some View {
        VStack(spacing: MorosIOS.spacing16) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 56))
                .foregroundColor(MorosIOS.verdit)
            Text("Session Complete")
                .font(MorosIOS.fontH2)
                .foregroundColor(MorosIOS.textMain)
            Text("\(completedCount) cards reviewed")
                .font(MorosIOS.fontBody)
                .foregroundColor(MorosIOS.textSub)

            if srsService.streak > 0 {
                HStack(spacing: 4) {
                    Image(systemName: "flame.fill")
                        .foregroundColor(MorosIOS.signal)
                    Text("\(srsService.streak) day streak")
                        .font(MorosIOS.fontBody)
                        .foregroundColor(MorosIOS.textSub)
                }
                .padding(.top, MorosIOS.spacing4)
            }

            Button("Done") {
                loadDueCards()
            }
            .font(MorosIOS.fontSubhead)
            .foregroundColor(MorosIOS.oracle)
            .padding(.top, MorosIOS.spacing16)
        }
    }

    // MARK: - Review Card

    private var reviewCard: some View {
        VStack(spacing: MorosIOS.spacing24) {
            // Progress
            HStack {
                Text("\(currentIndex + 1) / \(dueCards.count)")
                    .font(MorosIOS.fontMono)
                    .foregroundColor(MorosIOS.textDim)
                Spacer()
                ProgressView(value: Double(currentIndex), total: Double(dueCards.count))
                    .tint(MorosIOS.oracle)
                    .frame(width: 100)
            }
            .padding(.horizontal, MorosIOS.spacing16)

            Spacer()

            // Card
            VStack(spacing: MorosIOS.spacing16) {
                if let note = currentNote {
                    Text(note.title.isEmpty ? "Untitled" : note.title)
                        .font(MorosIOS.fontH2)
                        .foregroundColor(MorosIOS.textMain)
                        .multilineTextAlignment(.center)

                    if !isRevealed {
                        Text("Tap to reveal")
                            .font(MorosIOS.fontSmall)
                            .foregroundColor(MorosIOS.textDim)
                            .padding(.top, MorosIOS.spacing8)
                    } else {
                        Divider()
                            .background(MorosIOS.border)

                        ScrollView {
                            Text(note.contentPlainText.isEmpty ? note.content : note.contentPlainText)
                                .font(MorosIOS.fontBody)
                                .foregroundColor(MorosIOS.textSub)
                                .multilineTextAlignment(.leading)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .frame(maxHeight: 300)
                    }
                } else {
                    Text("Note not found")
                        .font(MorosIOS.fontBody)
                        .foregroundColor(MorosIOS.textDim)
                }
            }
            .padding(MorosIOS.spacing24)
            .frame(maxWidth: .infinity)
            .background(MorosIOS.limit02)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(MorosIOS.border, lineWidth: 1)
            )
            .padding(.horizontal, MorosIOS.spacing16)
            .onTapGesture {
                withAnimation(.easeInOut(duration: MorosIOS.animBase)) {
                    isRevealed = true
                }
            }

            Spacer()

            // Quality buttons
            if isRevealed {
                qualityButtons
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .padding(.vertical, MorosIOS.spacing16)
    }

    // MARK: - Quality Buttons

    private var qualityButtons: some View {
        HStack(spacing: MorosIOS.spacing12) {
            qualityButton(label: "Again", quality: 1, color: MorosIOS.signal)
            qualityButton(label: "Hard", quality: 2, color: MorosIOS.ambient)
            qualityButton(label: "Good", quality: 4, color: MorosIOS.oracle)
            qualityButton(label: "Easy", quality: 5, color: MorosIOS.verdit)
        }
        .padding(.horizontal, MorosIOS.spacing16)
        .padding(.bottom, MorosIOS.spacing8)
    }

    private func qualityButton(label: String, quality: Int, color: Color) -> some View {
        Button {
            submitReview(quality: quality)
        } label: {
            Text(label)
                .font(MorosIOS.fontSmall)
                .fontWeight(.medium)
                .foregroundColor(color)
                .frame(maxWidth: .infinity)
                .frame(height: MorosIOS.touchTargetMin)
                .background(color.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(color.opacity(0.2), lineWidth: 1)
                )
        }
    }

    // MARK: - Actions

    private func loadDueCards() {
        dueCards = srsService.dueCards()
        currentIndex = 0
        completedCount = 0
        isRevealed = false
        loadCurrentNote()
    }

    private func loadCurrentNote() {
        guard currentIndex < dueCards.count else {
            currentNote = nil
            return
        }
        let card = dueCards[currentIndex]
        let request = NoteEntity.fetchRequest() as! NSFetchRequest<NoteEntity>
        request.predicate = NSPredicate(format: "id == %@", card.id as CVarArg)
        request.fetchLimit = 1
        currentNote = try? viewContext.fetch(request).first
    }

    private func submitReview(quality: Int) {
        guard currentIndex < dueCards.count else { return }
        let card = dueCards[currentIndex]
        srsService.review(noteId: card.id, quality: quality)
        completedCount += 1

        withAnimation(.easeInOut(duration: MorosIOS.animBase)) {
            currentIndex += 1
            isRevealed = false
        }

        loadCurrentNote()
    }
}
