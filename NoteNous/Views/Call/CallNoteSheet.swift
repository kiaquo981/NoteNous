import SwiftUI
import CoreData

struct CallNoteSheet: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.managedObjectContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.moros) private var moros

    @ObservedObject var callNoteService: CallNoteService
    let callNoteId: UUID?

    @State private var topic: String = ""
    @State private var participantsText: String = ""
    @State private var annotations: String = ""
    @State private var transcription: String = ""
    @State private var isLiveMode: Bool = true
    @State private var timerSeconds: Int = 0
    @State private var timerActive: Bool = false
    @State private var timerTask: Task<Void, Never>?

    // Call Listener
    @StateObject private var callListener = CallListenerService.shared
    @State private var listenerPermissionError: String?

    // Extraction
    @State private var isExtracting: Bool = false
    @State private var extractionResult: CallNoteService.ExtractionResult?
    @State private var extractionError: String?
    @State private var appliedNotes: [NoteEntity] = []
    @State private var didApply: Bool = false

    private var existingCallNote: CallNoteService.CallNote? {
        guard let id = callNoteId else { return nil }
        return callNoteService.callNote(for: id)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            header

            Divider().background(moros.border)

            // Call Listener Panel (shown when listening)
            if callListener.isListening || callListener.state == .paused {
                CallListenerPanel(listener: callListener)
            }

            // Content
            ScrollView {
                VStack(alignment: .leading, spacing: Moros.spacing16) {
                    if isLiveMode {
                        liveSection
                    } else {
                        reviewSection
                    }
                }
                .padding(Moros.spacing16)
            }
        }
        .frame(minWidth: 600, minHeight: 500)
        .morosBackground(moros.limit01)
        .onAppear(perform: loadExisting)
        .onDisappear(perform: saveAndCleanup)
        .onChange(of: callListener.isListening) { wasListening, nowListening in
            // When listener stops (from panel stop button), auto-fill transcription
            if wasListening && !nowListening {
                let text = callListener.liveTranscription
                if !text.isEmpty {
                    if transcription.isEmpty {
                        transcription = text
                    } else {
                        transcription += "\n\n--- Live Transcription ---\n" + text
                    }
                }
                // Auto-switch to review mode
                isLiveMode = false
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Text(callNoteId == nil ? "New Call Note" : "Call Note")
                .font(Moros.fontH3)
                .foregroundStyle(moros.textMain)

            Spacer()

            if isLiveMode {
                timerBadge
            }

            // Mode toggle
            Picker("Mode", selection: $isLiveMode) {
                Text("Live").tag(true)
                Text("Review").tag(false)
            }
            .pickerStyle(.segmented)
            .frame(width: 160)

            Button("Done") {
                saveAndCleanup()
                dismiss()
            }
            .buttonStyle(.plain)
            .foregroundStyle(moros.oracle)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(moros.oracle.opacity(0.15), in: Rectangle())
        }
        .padding(Moros.spacing12)
        .morosBackground(moros.limit02)
    }

    private var timerBadge: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(Moros.signal)
                .frame(width: 6, height: 6)
            Text(formatDuration(timerSeconds))
                .font(Moros.fontMono)
                .foregroundStyle(moros.textMain)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Moros.signal.opacity(0.15), in: Rectangle())
        .onAppear(perform: startTimer)
    }

    // MARK: - Live Section

    private var liveSection: some View {
        VStack(alignment: .leading, spacing: Moros.spacing12) {
            // Topic
            TextField("Call topic...", text: $topic)
                .font(Moros.fontH2)
                .textFieldStyle(.plain)
                .foregroundStyle(moros.textMain)

            // Participants
            HStack(spacing: 8) {
                Image(systemName: "person.2")
                    .foregroundStyle(moros.textDim)
                TextField("Participants (comma-separated)", text: $participantsText)
                    .textFieldStyle(.plain)
                    .font(Moros.fontBody)
                    .foregroundStyle(moros.textSub)
            }
            .padding(8)
            .background(moros.limit02, in: Rectangle())

            // Listen button
            if !callListener.isListening && callListener.state != .paused {
                Button {
                    Task { await startCallListener() }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "mic.fill")
                        Text("Listen")
                            .font(Moros.fontSubhead)
                    }
                    .foregroundStyle(Moros.signal)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Moros.signal.opacity(0.12), in: Rectangle())
                }
                .buttonStyle(.plain)
            }

            if let permError = listenerPermissionError {
                Text(permError)
                    .font(Moros.fontSmall)
                    .foregroundStyle(Moros.signal)
            }

            Divider().background(moros.border)

            // Annotations area
            TextEditor(text: $annotations)
                .font(Moros.fontBody)
                .foregroundStyle(moros.textMain)
                .scrollContentBackground(.hidden)
                .frame(minHeight: 250)
                .padding(8)
                .background(moros.limit02, in: Rectangle())

            // Quick action buttons
            HStack(spacing: 8) {
                quickActionButton(label: "Action Item", prefix: "- [ ] ") {
                    Image(systemName: "bolt.fill")
                }
                quickActionButton(label: "Insight", prefix: "> Insight: ") {
                    Image(systemName: "lightbulb.fill")
                }
                quickActionButton(label: "Question", prefix: "> Question: ") {
                    Image(systemName: "questionmark.circle.fill")
                }
                quickActionButton(label: "Decision", prefix: "**DECISION:** ") {
                    Image(systemName: "checkmark.seal.fill")
                }
            }
        }
    }

    @ViewBuilder
    private func quickActionButton<Icon: View>(label: String, prefix: String, @ViewBuilder icon: () -> Icon) -> some View {
        Button {
            if !annotations.isEmpty && !annotations.hasSuffix("\n") {
                annotations += "\n"
            }
            annotations += prefix
        } label: {
            HStack(spacing: 4) {
                icon()
                Text(label)
                    .font(Moros.fontSmall)
            }
            .foregroundStyle(moros.oracle)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(moros.oracle.opacity(0.1), in: Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Review Section

    private var reviewSection: some View {
        VStack(alignment: .leading, spacing: Moros.spacing16) {
            // Topic (read-only display)
            if !topic.isEmpty {
                Text(topic)
                    .font(Moros.fontH2)
                    .foregroundStyle(moros.textMain)
            }

            // Annotations preview
            if !annotations.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("ANNOTATIONS")
                        .font(Moros.fontLabel)
                        .foregroundStyle(moros.textDim)
                    Text(annotations)
                        .font(Moros.fontBody)
                        .foregroundStyle(moros.textSub)
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(moros.limit02, in: Rectangle())
                }
            }

            Divider().background(moros.border)

            // Transcription section
            VStack(alignment: .leading, spacing: 8) {
                Text("TRANSCRIPTION")
                    .font(Moros.fontLabel)
                    .foregroundStyle(moros.textDim)

                TextEditor(text: $transcription)
                    .font(Moros.fontBody)
                    .foregroundStyle(moros.textMain)
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 120)
                    .padding(8)
                    .background(moros.limit02, in: Rectangle())

                HStack(spacing: 8) {
                    Button("Import from Clipboard") {
                        if let clipboard = NSPasteboard.general.string(forType: .string) {
                            transcription = clipboard
                        }
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(moros.textSub)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(moros.limit03, in: Rectangle())

                    Button("Import from VoiceInk") {
                        importFromVoiceInk()
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(moros.oracle)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(moros.oracle.opacity(0.1), in: Rectangle())
                }
            }

            Divider().background(moros.border)

            // Extract button
            if extractionResult == nil && !didApply {
                Button {
                    Task { await runExtraction() }
                } label: {
                    HStack {
                        if isExtracting {
                            ProgressView()
                                .controlSize(.small)
                                .tint(Moros.void)
                        } else {
                            Image(systemName: "sparkles")
                        }
                        Text(isExtracting ? "Extracting..." : "Extract with AI")
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .foregroundStyle(Moros.void)
                    .background(moros.oracle, in: Rectangle())
                    .font(Moros.fontSubhead)
                }
                .buttonStyle(.plain)
                .disabled(isExtracting || (annotations.isEmpty && transcription.isEmpty))
            }

            if let error = extractionError {
                Text(error)
                    .font(Moros.fontSmall)
                    .foregroundStyle(Moros.signal)
            }

            // Extraction results
            if let result = extractionResult, !didApply {
                CallExtractedView(
                    result: result,
                    onApply: { applyResults(result) }
                )
            }

            // Applied confirmation
            if didApply {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(moros.verdit)
                        Text("Extraction applied — \(appliedNotes.count) notes created")
                            .font(Moros.fontBody)
                            .foregroundStyle(moros.verdit)
                    }

                    ForEach(appliedNotes, id: \.objectID) { note in
                        HStack(spacing: 6) {
                            Image(systemName: "diamond.fill")
                                .font(Moros.fontCaption)
                                .foregroundStyle(moros.oracle)
                            Text(note.title)
                                .font(Moros.fontSmall)
                                .foregroundStyle(moros.textSub)
                        }
                    }
                }
                .padding(12)
                .background(moros.verdit.opacity(0.08), in: Rectangle())
            }
        }
    }

    // MARK: - Actions

    private func startTimer() {
        guard callNoteId == nil else { return } // Only for new notes
        timerActive = true
        timerTask = Task {
            while timerActive && !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                await MainActor.run {
                    timerSeconds += 1
                }
            }
        }
    }

    private func importFromVoiceInk() {
        let voiceInk = VoiceInkService.shared
        guard voiceInk.isAvailable else { return }
        let recent = voiceInk.fetchTranscriptions(since: Calendar.current.date(byAdding: .hour, value: -2, to: Date()))
        if let latest = recent.first {
            transcription = latest.bestText
        }
    }

    private func runExtraction() async {
        guard !annotations.isEmpty || !transcription.isEmpty else { return }
        isExtracting = true
        extractionError = nil

        // Save current state first
        let saved = saveCurrentState()

        do {
            let result = try await callNoteService.extractFromCall(saved, context: context)
            await MainActor.run {
                extractionResult = result
                isExtracting = false
            }
        } catch {
            await MainActor.run {
                extractionError = "Extraction failed: \(error.localizedDescription)"
                isExtracting = false
            }
        }
    }

    private func applyResults(_ result: CallNoteService.ExtractionResult) {
        let saved = saveCurrentState()
        appliedNotes = callNoteService.applyExtraction(result, for: saved, context: context)
        didApply = true
    }

    @discardableResult
    private func saveCurrentState() -> CallNoteService.CallNote {
        let participants = participantsText
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        if let existing = existingCallNote {
            var updated = existing
            updated.topic = topic
            updated.participants = participants
            updated.annotations = annotations
            updated.transcription = transcription.isEmpty ? nil : transcription
            if timerSeconds > 0 {
                updated.duration = TimeInterval(timerSeconds) / 60.0
            }
            callNoteService.updateCallNote(updated)
            return updated
        } else {
            var callNote = callNoteService.createCallNote(
                topic: topic.isEmpty ? "Untitled Call" : topic,
                participants: participants,
                date: Date()
            )
            callNote.annotations = annotations
            callNote.transcription = transcription.isEmpty ? nil : transcription
            if timerSeconds > 0 {
                callNote.duration = TimeInterval(timerSeconds) / 60.0
            }
            callNoteService.updateCallNote(callNote)
            return callNote
        }
    }

    private func loadExisting() {
        if let existing = existingCallNote {
            topic = existing.topic
            participantsText = existing.participants.joined(separator: ", ")
            annotations = existing.annotations
            transcription = existing.transcription ?? ""
            isLiveMode = !existing.isProcessed && existing.annotations.isEmpty
            if existing.isProcessed {
                didApply = true
            }
        }
    }

    private func startCallListener() async {
        let perms = await callListener.checkPermissions()
        if !perms.microphone {
            listenerPermissionError = "Microphone permission denied. Grant access in System Settings > Privacy & Security > Microphone."
            return
        }
        if !perms.speechRecognition {
            listenerPermissionError = "Speech recognition permission denied. Grant access in System Settings > Privacy & Security > Speech Recognition."
            return
        }
        listenerPermissionError = nil
        await callListener.startListening(language: "pt-BR")
    }

    private func saveAndCleanup() {
        timerActive = false
        timerTask?.cancel()

        // Stop listener and fill transcription if it was active
        if callListener.isListening || callListener.state == .paused {
            let listenerText = callListener.stopListening()
            if !listenerText.isEmpty {
                if transcription.isEmpty {
                    transcription = listenerText
                } else {
                    transcription += "\n\n--- Live Transcription ---\n" + listenerText
                }
            }
        }

        if !topic.isEmpty || !annotations.isEmpty {
            saveCurrentState()
        }
    }

    private func formatDuration(_ totalSeconds: Int) -> String {
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%02d:%02d", minutes, seconds)
    }
}
