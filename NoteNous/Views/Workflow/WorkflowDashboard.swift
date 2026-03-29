import SwiftUI
import CoreData

/// Overview dashboard of the knowledge management system.
/// Shows inbox status, sources, atomicity health, connections, index coverage, and CODE pipeline.
struct WorkflowDashboard: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.managedObjectContext) private var context
    @ObservedObject var sourceService: SourceService
    @ObservedObject var indexService: IndexService

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Top row: Inbox + Sources
                HStack(spacing: 16) {
                    inboxCard
                    sourcesCard
                }

                // Middle row: Atomicity + Connections
                HStack(spacing: 16) {
                    atomicityCard
                    connectionsCard
                }

                // Bottom row: Index + CODE Pipeline
                HStack(spacing: 16) {
                    indexCard
                    codePipelineCard
                }

                // Weekly activity
                weeklyActivityCard
            }
            .padding()
        }

    }

    // MARK: - Inbox Card

    private var inboxCard: some View {
        DashboardCard(title: "Inbox", icon: "tray.full", color: Moros.ambient) {
            let fleetingCount = countNotes(type: .fleeting)

            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline) {
                    Text("\(fleetingCount)")
                        .font(.system(size: 36, weight: .light))
                        .foregroundStyle(Moros.textMain)
                    Text("fleeting notes")
                        .font(Moros.fontBody)
                        .foregroundStyle(Moros.textSub)
                }

                if fleetingCount > 0 {
                    let ages = fleetingNoteAges()
                    HStack(spacing: 8) {
                        AgeBar(label: "<24h", count: ages.fresh, color: Moros.verdit)
                        AgeBar(label: "1-7d", count: ages.review, color: Moros.ambient)
                        AgeBar(label: ">7d", count: ages.stale, color: Moros.signal)
                    }

                    if let oldest = ages.oldestDays {
                        Text("Oldest: \(oldest) days")
                            .font(Moros.fontCaption)
                            .foregroundStyle(Moros.textDim)
                    }
                } else {
                    Label("Inbox zero", systemImage: "checkmark.circle")
                        .font(Moros.fontCaption)
                        .foregroundStyle(Moros.verdit)
                }
            }
        }
    }

    // MARK: - Sources Card

    private var sourcesCard: some View {
        let stats = sourceService.stats()

        return DashboardCard(title: "Sources", icon: "books.vertical", color: Moros.oracle) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline) {
                    Text("\(stats.totalSources)")
                        .font(.system(size: 36, weight: .light))
                        .foregroundStyle(Moros.textMain)
                    Text("total sources")
                        .font(Moros.fontBody)
                        .foregroundStyle(Moros.textSub)
                }

                HStack(spacing: 16) {
                    StatPill(label: "Waiting", value: stats.waitingCount, color: Moros.ambient)
                    StatPill(label: "Ready", value: stats.readyToCardCount, color: Moros.verdit)
                    StatPill(label: "Carded", value: stats.cardedCount, color: Moros.oracle)
                }

                Text("\(stats.totalCardsGenerated) cards generated")
                    .font(Moros.fontCaption)
                    .foregroundStyle(Moros.textDim)
            }
        }
    }

    // MARK: - Atomicity Card

    private var atomicityCard: some View {
        let atomicService = AtomicNoteService(context: context)
        let percentage = atomicService.atomicityPercentage()
        let permanentCount = countNotes(type: .permanent)

        return DashboardCard(title: "Atomicity", icon: "atom", color: atomicityColor(percentage)) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline) {
                    Text("\(Int(percentage))%")
                        .font(.system(size: 36, weight: .light))
                        .foregroundStyle(atomicityColor(percentage))
                    Text("of permanent notes atomic")
                        .font(Moros.fontBody)
                        .foregroundStyle(Moros.textSub)
                }

                Text("\(permanentCount) permanent notes total")
                    .font(Moros.fontCaption)
                    .foregroundStyle(Moros.textDim)

                // Progress bar
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Rectangle()
                            .fill(Moros.limit03)
                            .frame(height: 6)
                        Rectangle()
                            .fill(atomicityColor(percentage))
                            .frame(width: geo.size.width * CGFloat(percentage / 100), height: 6)
                    }
                }
                .frame(height: 6)
            }
        }
    }

    // MARK: - Connections Card

    private var connectionsCard: some View {
        let atomicService = AtomicNoteService(context: context)
        let avgLinks = atomicService.averageLinkDensity()
        let orphans = atomicService.orphanNoteCount()

        return DashboardCard(title: "Connections", icon: "link", color: Moros.oracle) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline) {
                    Text(String(format: "%.1f", avgLinks))
                        .font(.system(size: 36, weight: .light))
                        .foregroundStyle(Moros.textMain)
                    Text("avg links/note")
                        .font(Moros.fontBody)
                        .foregroundStyle(Moros.textSub)
                }

                if orphans > 0 {
                    Label("\(orphans) orphan notes", systemImage: "exclamationmark.triangle")
                        .font(Moros.fontCaption)
                        .foregroundStyle(Moros.ambient)
                } else {
                    Label("No orphan notes", systemImage: "checkmark.circle")
                        .font(Moros.fontCaption)
                        .foregroundStyle(Moros.verdit)
                }
            }
        }
    }

    // MARK: - Index Card

    private var indexCard: some View {
        let stats = indexService.stats()
        let permanentCount = countNotes(type: .permanent)
        let coverage = permanentCount > 0 ? Double(stats.totalEntryNotes) / Double(permanentCount) * 100 : 0

        return DashboardCard(title: "Index", icon: "text.book.closed", color: Moros.verdit) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline) {
                    Text("\(stats.totalKeywords)")
                        .font(.system(size: 36, weight: .light))
                        .foregroundStyle(Moros.textMain)
                    Text("keywords")
                        .font(Moros.fontBody)
                        .foregroundStyle(Moros.textSub)
                }

                HStack(spacing: 16) {
                    VStack(alignment: .leading) {
                        Text("\(stats.totalEntryNotes)")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Moros.textMain)
                        Text("entry notes")
                            .font(Moros.fontMicro)
                            .foregroundStyle(Moros.textDim)
                    }
                    VStack(alignment: .leading) {
                        Text(String(format: "%.0f%%", min(coverage, 100)))
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Moros.textMain)
                        Text("coverage")
                            .font(Moros.fontMicro)
                            .foregroundStyle(Moros.textDim)
                    }
                }

                if stats.overloadedKeywords > 0 {
                    Label("\(stats.overloadedKeywords) keywords with >3 entries", systemImage: "exclamationmark.triangle")
                        .font(Moros.fontCaption)
                        .foregroundStyle(Moros.ambient)
                }
            }
        }
    }

    // MARK: - CODE Pipeline Card

    private var codePipelineCard: some View {
        DashboardCard(title: "CODE Pipeline", icon: "arrow.right.arrow.left", color: Moros.oracle) {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(CODEStage.allCases) { stage in
                    let count = countNotesByStage(stage)
                    HStack {
                        Image(systemName: stage.icon)
                            .frame(width: 16)
                            .foregroundStyle(Moros.textDim)
                        Text(stage.label)
                            .font(Moros.fontBody)
                            .foregroundStyle(Moros.textSub)
                        Spacer()
                        Text("\(count)")
                            .font(.system(size: 13, weight: .semibold, design: .monospaced))
                            .foregroundStyle(Moros.textMain)
                    }
                }
            }
        }
    }

    // MARK: - Weekly Activity Card

    private var weeklyActivityCard: some View {
        let weekStats = weeklyStats()

        return DashboardCard(title: "This Week", icon: "calendar", color: Moros.verdit) {
            HStack(spacing: 24) {
                VStack {
                    Text("\(weekStats.created)")
                        .font(.system(size: 28, weight: .light))
                        .foregroundStyle(Moros.textMain)
                    Text("Created")
                        .font(Moros.fontCaption)
                        .foregroundStyle(Moros.textDim)
                }
                VStack {
                    Text("\(weekStats.promoted)")
                        .font(.system(size: 28, weight: .light))
                        .foregroundStyle(Moros.textMain)
                    Text("Promoted")
                        .font(Moros.fontCaption)
                        .foregroundStyle(Moros.textDim)
                }
                VStack {
                    Text("\(weekStats.archived)")
                        .font(.system(size: 28, weight: .light))
                        .foregroundStyle(Moros.textMain)
                    Text("Archived")
                        .font(Moros.fontCaption)
                        .foregroundStyle(Moros.textDim)
                }
            }
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: - Data Queries

    private func countNotes(type: NoteType) -> Int {
        let request = NoteEntity.fetchRequest() as! NSFetchRequest<NoteEntity>
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            NSPredicate(format: "noteTypeRaw == %d", type.rawValue),
            NSPredicate(format: "isArchived == NO")
        ])
        return (try? context.count(for: request)) ?? 0
    }

    private func countNotesByStage(_ stage: CODEStage) -> Int {
        let request = NoteEntity.fetchRequest() as! NSFetchRequest<NoteEntity>
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            NSPredicate(format: "codeStageRaw == %d", stage.rawValue),
            NSPredicate(format: "isArchived == NO")
        ])
        return (try? context.count(for: request)) ?? 0
    }

    private func fleetingNoteAges() -> (fresh: Int, review: Int, stale: Int, oldestDays: Int?) {
        let request = NoteEntity.fetchRequest() as! NSFetchRequest<NoteEntity>
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            NSPredicate(format: "noteTypeRaw == %d", NoteType.fleeting.rawValue),
            NSPredicate(format: "isArchived == NO")
        ])

        let notes = (try? context.fetch(request)) ?? []
        var fresh = 0, review = 0, stale = 0
        var oldestDays: Int?

        for note in notes {
            guard let created = note.createdAt else { continue }
            let days = Calendar.current.dateComponents([.day], from: created, to: Date()).day ?? 0

            if days < 1 { fresh += 1 }
            else if days <= 7 { review += 1 }
            else { stale += 1 }

            if let current = oldestDays {
                oldestDays = max(current, days)
            } else {
                oldestDays = days
            }
        }

        return (fresh, review, stale, oldestDays)
    }

    private func weeklyStats() -> (created: Int, promoted: Int, archived: Int) {
        let calendar = Calendar.current
        let weekAgo = calendar.date(byAdding: .day, value: -7, to: Date()) ?? Date()

        let createdRequest = NoteEntity.fetchRequest() as! NSFetchRequest<NoteEntity>
        createdRequest.predicate = NSPredicate(format: "createdAt >= %@", weekAgo as NSDate)
        let created = (try? context.count(for: createdRequest)) ?? 0

        let promotedRequest = NoteEntity.fetchRequest() as! NSFetchRequest<NoteEntity>
        promotedRequest.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            NSPredicate(format: "noteTypeRaw == %d", NoteType.permanent.rawValue),
            NSPredicate(format: "updatedAt >= %@", weekAgo as NSDate)
        ])
        let promoted = (try? context.count(for: promotedRequest)) ?? 0

        let archivedRequest = NoteEntity.fetchRequest() as! NSFetchRequest<NoteEntity>
        archivedRequest.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            NSPredicate(format: "isArchived == YES"),
            NSPredicate(format: "archivedAt >= %@", weekAgo as NSDate)
        ])
        let archived = (try? context.count(for: archivedRequest)) ?? 0

        return (created, promoted, archived)
    }

    private func atomicityColor(_ percentage: Double) -> Color {
        if percentage >= 80 { return Moros.verdit }
        if percentage >= 50 { return Moros.ambient }
        return Moros.signal
    }
}

// MARK: - Dashboard Card

struct DashboardCard<Content: View>: View {
    let title: String
    let icon: String
    let color: Color
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: icon)
                    .foregroundStyle(color)
                Text(title.uppercased())
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundStyle(Moros.textDim)
                Spacer()
            }

            content()
        }
        .padding()
        .background(Moros.limit02, in: Rectangle())
        .overlay(
            Rectangle()
                .strokeBorder(Moros.border, lineWidth: 1)
        )
    }
}

// MARK: - Supporting Views

struct AgeBar: View {
    let label: String
    let count: Int
    let color: Color

    var body: some View {
        VStack(spacing: 4) {
            Text("\(count)")
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                .foregroundStyle(Moros.textMain)
            Text(label)
                .font(Moros.fontMicro)
                .foregroundStyle(Moros.textDim)
            Rectangle()
                .fill(color.opacity(0.6))
                .frame(height: 4)
        }
    }
}

struct StatPill: View {
    let label: String
    let value: Int
    let color: Color

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
            Text("\(value)")
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundStyle(Moros.textMain)
            Text(label)
                .font(Moros.fontCaption)
                .foregroundStyle(Moros.textDim)
        }
    }
}
