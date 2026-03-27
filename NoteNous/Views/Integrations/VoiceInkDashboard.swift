import SwiftUI
import CoreData

struct VoiceInkDashboard: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.managedObjectContext) private var context
    @Environment(\.moros) private var moros

    @StateObject private var voiceInkService = VoiceInkService()
    @StateObject private var agent = ZettelkastenAgent()

    @State private var selectedTranscriptions: Set<Int> = []
    @State private var showingTimeline: Bool = false
    @State private var syncMessage: String = ""
    @State private var autoSyncEnabled: Bool = VoiceInkAutoSync.shared.isEnabled

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Moros.spacing16) {
                // Header
                headerSection

                if voiceInkService.isAvailable {
                    // Stats bar
                    statsSection

                    // Sync controls
                    syncControlsSection

                    Divider().background(moros.border)

                    // Recent transcriptions (unimported)
                    recentTranscriptionsSection

                    // Sync message
                    if !syncMessage.isEmpty {
                        syncMessageBanner
                    }

                } else {
                    notAvailableSection
                }
            }
            .padding(Moros.spacing16)
        }
        .morosBackground(moros.void)
        .navigationTitle("VoiceInk")
    }

    // MARK: - Header

    private var headerSection: some View {
        HStack(spacing: Moros.spacing12) {
            Image(systemName: "mic.fill")
                .font(.system(size: 24))
                .foregroundStyle(moros.oracle)

            VStack(alignment: .leading, spacing: 2) {
                Text("VoiceInk Integration")
                    .font(Moros.fontH3)
                    .foregroundStyle(moros.textMain)
                Text("Voice-to-Zettelkasten pipeline")
                    .font(Moros.fontSmall)
                    .foregroundStyle(moros.textDim)
            }

            Spacer()

            // Status indicator
            HStack(spacing: 6) {
                Circle()
                    .fill(voiceInkService.isAvailable ? Color.green : moros.signal)
                    .frame(width: 8, height: 8)
                Text(voiceInkService.isAvailable ? "Connected" : "Not found")
                    .font(Moros.fontSmall)
                    .foregroundStyle(moros.textSub)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(moros.limit02, in: Rectangle())
        }
    }

    // MARK: - Stats

    private var statsSection: some View {
        let stats = voiceInkService.getStats()
        let hours = stats.totalDuration / 3600
        let dateFormatter: DateFormatter = {
            let f = DateFormatter()
            f.dateStyle = .medium
            return f
        }()

        return HStack(spacing: Moros.spacing16) {
            statCard(label: "Transcriptions", value: "\(stats.count)", icon: "waveform", color: moros.oracle)
            statCard(label: "Total Hours", value: String(format: "%.1f", hours), icon: "clock", color: moros.ambient)
            statCard(label: "Unimported", value: "\(voiceInkService.unimportedCount)", icon: "arrow.down.circle", color: moros.signal)

            if let oldest = stats.oldestDate {
                statCard(label: "Since", value: dateFormatter.string(from: oldest), icon: "calendar", color: moros.verdit)
            }

            if let lastSync = voiceInkService.lastSyncDate {
                statCard(label: "Last Sync", value: relativeTime(lastSync), icon: "arrow.clockwise", color: moros.ambient)
            }
        }
    }

    private func statCard(label: String, value: String, icon: String, color: Color) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundStyle(color)
            Text(value)
                .font(Moros.fontSubhead)
                .foregroundStyle(moros.textMain)
            Text(label)
                .font(Moros.fontCaption)
                .foregroundStyle(moros.textDim)
        }
        .frame(maxWidth: .infinity)
        .padding(Moros.spacing8)
        .background(moros.limit02, in: Rectangle())
    }

    // MARK: - Sync Controls

    private var syncControlsSection: some View {
        HStack(spacing: Moros.spacing8) {
            Button(action: {
                Task {
                    let stats = await voiceInkService.sync(context: context)
                    syncMessage = "Imported \(stats.notesCreated) notes from \(stats.newSinceLastSync) transcriptions"
                }
            }) {
                HStack(spacing: 4) {
                    if voiceInkService.isSyncing {
                        ProgressView()
                            .scaleEffect(0.6)
                            .frame(width: 14, height: 14)
                    } else {
                        Image(systemName: "arrow.clockwise")
                    }
                    Text("Sync Now")
                }
                .font(Moros.fontBody)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(moros.oracle.opacity(0.15), in: Rectangle())
                .foregroundStyle(moros.oracle)
            }
            .buttonStyle(.plain)
            .disabled(voiceInkService.isSyncing)

            Button(action: {
                Task {
                    let stats = await voiceInkService.smartSync(context: context)
                    syncMessage = "Smart sync: \(stats.notesCreated) notes (AI-classified) from \(stats.newSinceLastSync) transcriptions"
                }
            }) {
                HStack(spacing: 4) {
                    Image(systemName: "brain")
                    Text("Smart Sync")
                }
                .font(Moros.fontBody)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(moros.verdit.opacity(0.15), in: Rectangle())
                .foregroundStyle(moros.verdit)
            }
            .buttonStyle(.plain)
            .disabled(voiceInkService.isSyncing)

            Spacer()

            // Auto-sync toggle
            Toggle(isOn: $autoSyncEnabled) {
                HStack(spacing: 4) {
                    Image(systemName: "timer")
                    Text("Auto-sync (5m)")
                }
                .font(Moros.fontSmall)
                .foregroundStyle(moros.textSub)
            }
            .toggleStyle(.switch)
            .tint(moros.oracle)
            .onChange(of: autoSyncEnabled) { _, newValue in
                if newValue {
                    VoiceInkAutoSync.shared.startAutoSync(context: context)
                } else {
                    VoiceInkAutoSync.shared.stopAutoSync()
                }
            }

            // Timeline toggle
            Button(action: { showingTimeline.toggle() }) {
                HStack(spacing: 4) {
                    Image(systemName: "timeline.selection")
                    Text("Timeline")
                }
                .font(Moros.fontBody)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(showingTimeline ? moros.oracle.opacity(0.2) : moros.limit03, in: Rectangle())
                .foregroundStyle(showingTimeline ? moros.oracle : moros.textSub)
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Recent Transcriptions

    private var recentTranscriptionsSection: some View {
        VStack(alignment: .leading, spacing: Moros.spacing8) {
            HStack {
                Text("RECENT TRANSCRIPTIONS")
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundStyle(moros.textDim)

                Spacer()

                if !selectedTranscriptions.isEmpty {
                    Button(action: importSelected) {
                        Text("Import Selected (\(selectedTranscriptions.count))")
                            .font(Moros.fontSmall)
                            .foregroundStyle(moros.oracle)
                    }
                    .buttonStyle(.plain)
                }
            }

            if showingTimeline {
                VoiceInkTimelineView(voiceInkService: voiceInkService)
                    .environmentObject(appState)
                    .environment(\.managedObjectContext, context)
            } else {
                let transcriptions = voiceInkService.fetchTranscriptions().prefix(50)

                ForEach(Array(transcriptions), id: \.id) { transcription in
                    transcriptionRow(transcription)
                }

                if transcriptions.isEmpty {
                    Text("No transcriptions found")
                        .font(Moros.fontBody)
                        .foregroundStyle(moros.textDim)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding()
                }
            }
        }
    }

    private func transcriptionRow(_ transcription: VoiceInkService.VoiceInkTranscription) -> some View {
        let isImported = voiceInkService.isImported(pk: transcription.id)
        let isSelected = selectedTranscriptions.contains(transcription.id)

        return HStack(alignment: .top, spacing: Moros.spacing8) {
            // Selection checkbox (only for unimported)
            if !isImported {
                Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                    .foregroundStyle(isSelected ? moros.oracle : moros.textDim)
                    .onTapGesture {
                        if isSelected {
                            selectedTranscriptions.remove(transcription.id)
                        } else {
                            selectedTranscriptions.insert(transcription.id)
                        }
                    }
            } else {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(moros.verdit.opacity(0.5))
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(transcription.timestamp, style: .time)
                        .font(Moros.fontMono)
                        .foregroundStyle(moros.textSub)

                    Text(transcription.durationFormatted)
                        .font(Moros.fontMonoSmall)
                        .foregroundStyle(moros.textDim)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(moros.limit03, in: Rectangle())

                    if let mode = transcription.powerMode, !mode.isEmpty {
                        Text(mode)
                            .font(Moros.fontMonoSmall)
                            .foregroundStyle(moros.oracle.opacity(0.7))
                    }

                    if isImported {
                        Text("IMPORTED")
                            .font(Moros.fontMicro)
                            .foregroundStyle(moros.verdit)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(moros.verdit.opacity(0.1), in: Rectangle())
                    }
                }

                Text(transcription.bestText.prefix(200))
                    .font(Moros.fontBody)
                    .foregroundStyle(isImported ? moros.textDim : moros.textMain)
                    .lineLimit(2)
            }

            Spacer()
        }
        .padding(Moros.spacing8)
        .background(isSelected ? moros.oracle.opacity(0.05) : Color.clear, in: Rectangle())
        .overlay(
            Rectangle()
                .stroke(isSelected ? moros.oracle.opacity(0.2) : Color.clear, lineWidth: 1)
        )
    }

    // MARK: - Sync Message Banner

    private var syncMessageBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(moros.verdit)
            Text(syncMessage)
                .font(Moros.fontSmall)
                .foregroundStyle(moros.textMain)
            Spacer()
            Button(action: { syncMessage = "" }) {
                Image(systemName: "xmark")
                    .font(Moros.fontSmall)
                    .foregroundStyle(moros.textDim)
            }
            .buttonStyle(.plain)
        }
        .padding(Moros.spacing8)
        .background(moros.verdit.opacity(0.1), in: Rectangle())
    }

    // MARK: - Not Available

    private var notAvailableSection: some View {
        VStack(spacing: Moros.spacing12) {
            Image(systemName: "mic.slash")
                .font(.system(size: 40))
                .foregroundStyle(moros.textDim)
            Text("VoiceInk not found")
                .font(Moros.fontH3)
                .foregroundStyle(moros.textMain)
            Text("Install VoiceInk from the Mac App Store to enable voice capture integration.")
                .font(Moros.fontBody)
                .foregroundStyle(moros.textSub)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(Moros.spacing32)
    }

    // MARK: - Actions

    private func importSelected() {
        let transcriptions = voiceInkService.fetchTranscriptions()
            .filter { selectedTranscriptions.contains($0.id) }
        let count = voiceInkService.importTranscriptions(transcriptions, context: context)
        syncMessage = "Imported \(count) selected transcriptions"
        selectedTranscriptions.removeAll()
    }

    // MARK: - Helpers

    private func relativeTime(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}
