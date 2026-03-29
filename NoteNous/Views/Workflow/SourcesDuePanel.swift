import SwiftUI

/// Panel showing sources ready to be "carded" (Holiday's 14-day waiting period has passed).
/// Used in the sidebar as a banner and as a standalone view.
struct SourcesDuePanel: View {
    @ObservedObject var sourceService: SourceService
    @EnvironmentObject var appState: AppState
    @Environment(\.managedObjectContext) private var context

    @State private var showLiteratureSheet: Bool = false
    @State private var selectedSource: Source?

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("READY TO CARD")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundStyle(Moros.oracle)
                    Text("Sources past the 14-day waiting period")
                        .font(Moros.fontCaption)
                        .foregroundStyle(Moros.textDim)
                }
                Spacer()
                Text("\(readySources.count)")
                    .font(.system(size: 18, weight: .light, design: .monospaced))
                    .foregroundStyle(Moros.oracle)
            }
            .padding()

            Rectangle().fill(Moros.border).frame(height: 1)

            if readySources.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "checkmark.circle")
                        .font(.system(size: 32))
                        .foregroundStyle(Moros.verdit)
                    Text("All caught up")
                        .font(Moros.fontBody)
                        .foregroundStyle(Moros.textSub)
                    Text("No sources ready to card right now. Sources need 14 days after consumption.")
                        .font(Moros.fontCaption)
                        .foregroundStyle(Moros.textDim)
                        .multilineTextAlignment(.center)
                }
                .padding(32)
            } else {
                ScrollView {
                    LazyVStack(spacing: 1) {
                        ForEach(readySources) { source in
                            SourceDueRow(source: source) {
                                selectedSource = source
                                showLiteratureSheet = true
                            }
                        }
                    }
                }
            }

            // Waiting sources count
            if waitingCount > 0 {
                Rectangle().fill(Moros.border).frame(height: 1)
                HStack {
                    Image(systemName: "clock")
                        .font(.system(size: 10))
                        .foregroundStyle(Moros.ambient)
                    Text("\(waitingCount) source\(waitingCount == 1 ? "" : "s") still waiting")
                        .font(Moros.fontCaption)
                        .foregroundStyle(Moros.textDim)
                    Spacer()
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
                .background(Moros.ambient.opacity(0.04))
            }
        }

        .sheet(isPresented: $showLiteratureSheet) {
            if let source = selectedSource {
                LiteratureNoteSheet()
                    .environment(\.managedObjectContext, context)
                    .environmentObject(appState)
                    .onAppear {
                        // Mark as carding started
                        sourceService.startCarding(id: source.id)
                    }
            }
        }
    }

    // MARK: - Computed

    private var readySources: [Source] {
        sourceService.sourcesReadyToCard()
    }

    private var waitingCount: Int {
        sourceService.sources.filter { $0.waitingStatus == .waiting }.count
    }
}

// MARK: - Source Due Row

struct SourceDueRow: View {
    let source: Source
    let onCard: () -> Void
    @State private var isHovered: Bool = false

    var body: some View {
        HStack(spacing: 12) {
            // Type icon
            Image(systemName: source.sourceType.icon)
                .font(.system(size: 14))
                .foregroundStyle(Moros.oracle)
                .frame(width: 24)

            // Info
            VStack(alignment: .leading, spacing: 2) {
                Text(source.title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Moros.textMain)
                    .lineLimit(1)

                HStack(spacing: 8) {
                    if let author = source.author {
                        Text(author)
                            .font(Moros.fontCaption)
                            .foregroundStyle(Moros.textSub)
                    }
                    if let days = source.waitingPeriodDays {
                        Text("\(days) days ago")
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundStyle(Moros.verdit)
                    }
                }
            }

            Spacer()

            // Cards already generated
            if source.cardsGenerated > 0 {
                HStack(spacing: 3) {
                    Image(systemName: "rectangle.on.rectangle")
                        .font(.system(size: 9))
                    Text("\(source.cardsGenerated)")
                        .font(.system(size: 10, design: .monospaced))
                }
                .foregroundStyle(Moros.textDim)
            }

            // Card It button
            Button(action: onCard) {
                Text("Card It")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundStyle(Moros.void)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
                    .background(Moros.oracle, in: Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(isHovered ? Moros.limit02 : .clear)
        .onHover { isHovered = $0 }
    }
}

// MARK: - Sidebar Ready-to-Card Badge

/// Compact badge for the sidebar showing count of sources ready to card.
struct ReadyToCardBadge: View {
    @ObservedObject var sourceService: SourceService

    var count: Int {
        sourceService.sourcesReadyToCard().count
    }

    var body: some View {
        if count > 0 {
            Text("\(count)")
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundStyle(Moros.void)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Moros.oracle, in: Rectangle())
        }
    }
}
