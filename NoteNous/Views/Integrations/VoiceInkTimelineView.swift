import SwiftUI
import CoreData

struct VoiceInkTimelineView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.managedObjectContext) private var context
    @Environment(\.moros) private var moros

    @ObservedObject var voiceInkService: VoiceInkService

    @State private var expandedIds: Set<Int> = []
    @State private var transcriptions: [VoiceInkService.VoiceInkTranscription] = []

    var body: some View {
        VStack(alignment: .leading, spacing: Moros.spacing12) {
            // Mini activity chart
            activityChart

            Divider().background(moros.border)

            // Timeline grouped by day
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(groupedByDay, id: \.key) { day, dayTranscriptions in
                        daySection(day: day, transcriptions: dayTranscriptions)
                    }
                }
            }
        }
        .onAppear { transcriptions = voiceInkService.fetchTranscriptions() }
    }

    // MARK: - Activity Chart

    private var activityChart: some View {
        let dailyCounts = computeDailyCounts()
        let maxCount = dailyCounts.map(\.count).max() ?? 1

        return VStack(alignment: .leading, spacing: 4) {
            Text("VOICE ACTIVITY")
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .foregroundStyle(moros.textDim)

            HStack(alignment: .bottom, spacing: 2) {
                ForEach(dailyCounts, id: \.date) { entry in
                    VStack(spacing: 2) {
                        Rectangle()
                            .fill(entry.count > 0 ? moros.oracle : moros.limit03)
                            .frame(width: 12, height: max(2, CGFloat(entry.count) / CGFloat(maxCount) * 40))

                        Text(dayLabel(entry.date))
                            .font(Moros.fontMicro)
                            .foregroundStyle(moros.textDim)
                    }
                }
            }
            .frame(height: 56)
        }
    }

    // MARK: - Day Section

    private func daySection(day: String, transcriptions: [VoiceInkService.VoiceInkTranscription]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // Day header
            HStack(spacing: 8) {
                Text(day)
                    .font(Moros.fontSmall)
                    .fontWeight(.medium)
                    .foregroundStyle(moros.textMain)

                Text("\(transcriptions.count) entries")
                    .font(Moros.fontCaption)
                    .foregroundStyle(moros.textDim)

                let totalDuration = transcriptions.reduce(0) { $0 + $1.duration }
                Text("\(Int(totalDuration / 60))m")
                    .font(Moros.fontMonoSmall)
                    .foregroundStyle(moros.ambient)

                Spacer()
            }
            .padding(.vertical, 6)
            .padding(.horizontal, Moros.spacing8)
            .background(moros.limit02, in: Rectangle())

            // Timeline entries
            ForEach(transcriptions, id: \.id) { transcription in
                timelineEntry(transcription)
            }
        }
    }

    private func timelineEntry(_ transcription: VoiceInkService.VoiceInkTranscription) -> some View {
        let isImported = voiceInkService.isImported(pk: transcription.id)
        let isExpanded = expandedIds.contains(transcription.id)
        let entryColor: Color = isImported ? moros.verdit : moros.ambient

        return HStack(alignment: .top, spacing: Moros.spacing8) {
            // Timeline line + dot
            VStack(spacing: 0) {
                Circle()
                    .fill(entryColor)
                    .frame(width: 8, height: 8)
                Rectangle()
                    .fill(moros.limit03)
                    .frame(width: 1)
            }
            .frame(width: 16)

            // Duration bar
            Rectangle()
                .fill(entryColor.opacity(0.3))
                .frame(width: max(4, CGFloat(transcription.duration) / 60.0 * 40), height: 4)
                .padding(.top, 6)

            // Content
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(transcription.timestamp, style: .time)
                        .font(Moros.fontMono)
                        .foregroundStyle(moros.textSub)

                    Text(transcription.durationFormatted)
                        .font(Moros.fontMonoSmall)
                        .foregroundStyle(moros.textDim)

                    if let mode = transcription.powerMode, !mode.isEmpty {
                        Text(mode)
                            .font(Moros.fontMicro)
                            .foregroundStyle(moros.oracle.opacity(0.7))
                            .padding(.horizontal, 3)
                            .padding(.vertical, 1)
                            .background(moros.oracle.opacity(0.1), in: Rectangle())
                    }

                    if isImported {
                        Image(systemName: "checkmark.circle.fill")
                            .font(Moros.fontCaption)
                            .foregroundStyle(moros.verdit)
                    }
                }

                Text(isExpanded ? transcription.bestText : String(transcription.bestText.prefix(120)))
                    .font(Moros.fontBody)
                    .foregroundStyle(moros.textMain)
                    .lineLimit(isExpanded ? nil : 2)

                HStack(spacing: 8) {
                    if transcription.bestText.count > 120 {
                        Button(action: {
                            if isExpanded {
                                expandedIds.remove(transcription.id)
                            } else {
                                expandedIds.insert(transcription.id)
                            }
                        }) {
                            Text(isExpanded ? "Show less" : "Show more")
                                .font(Moros.fontCaption)
                                .foregroundStyle(moros.oracle)
                        }
                        .buttonStyle(.plain)
                    }

                    if !isImported {
                        Button(action: {
                            _ = voiceInkService.importTranscriptions([transcription], context: context)
                        }) {
                            HStack(spacing: 2) {
                                Image(systemName: "arrow.down.circle")
                                Text("Import")
                            }
                            .font(Moros.fontCaption)
                            .foregroundStyle(moros.oracle)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            Spacer()
        }
        .padding(.vertical, 4)
        .padding(.horizontal, Moros.spacing8)
    }

    // MARK: - Data Processing

    private var groupedByDay: [(key: String, value: [VoiceInkService.VoiceInkTranscription])] {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium

        let grouped = Dictionary(grouping: transcriptions) { t in
            formatter.string(from: t.timestamp)
        }

        return grouped.sorted { a, b in
            guard let dateA = a.value.first?.timestamp, let dateB = b.value.first?.timestamp else { return false }
            return dateA > dateB
        }
    }

    private struct DailyCount {
        let date: Date
        let count: Int
    }

    private func computeDailyCounts() -> [DailyCount] {
        let calendar = Calendar.current
        guard let oldest = transcriptions.last?.timestamp else { return [] }

        let startDate = calendar.startOfDay(for: oldest)
        let endDate = calendar.startOfDay(for: Date())

        var counts: [DailyCount] = []
        var currentDate = startDate

        while currentDate <= endDate {
            let nextDate = calendar.date(byAdding: .day, value: 1, to: currentDate)!
            let count = transcriptions.filter { t in
                t.timestamp >= currentDate && t.timestamp < nextDate
            }.count
            counts.append(DailyCount(date: currentDate, count: count))
            currentDate = nextDate
        }

        // Show last 14 days max
        return Array(counts.suffix(14))
    }

    private func dayLabel(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "d"
        return formatter.string(from: date)
    }
}
