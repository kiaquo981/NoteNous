import SwiftUI
import Speech
import AVFoundation

struct VoiceCaptureView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss

    @State private var isRecording = false
    @State private var transcribedText = ""
    @State private var audioLevel: Float = 0
    @State private var showSaved = false
    @State private var errorMessage: String?
    @State private var authorizationStatus: SFSpeechRecognizerAuthorizationStatus = .notDetermined

    @State private var audioEngine = AVAudioEngine()
    @State private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    @State private var recognitionTask: SFSpeechRecognitionTask?
    @State private var levelTimer: Timer?

    private let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))

    var body: some View {
        NavigationStack {
            ZStack {
                MorosIOS.void.ignoresSafeArea()

                VStack(spacing: MorosIOS.spacing24) {
                    Spacer()

                    // Waveform visualization
                    waveformView
                        .frame(height: 80)
                        .padding(.horizontal, MorosIOS.spacing32)

                    // Status text
                    Text(statusText)
                        .font(MorosIOS.fontSmall)
                        .foregroundColor(MorosIOS.textDim)

                    // Record button
                    Button(action: toggleRecording) {
                        ZStack {
                            Circle()
                                .fill(isRecording ? MorosIOS.signal : MorosIOS.oracle)
                                .frame(width: 72, height: 72)
                                .morosIOSGlow(isRecording ? MorosIOS.signal : MorosIOS.oracle, radius: isRecording ? 16 : 8)

                            Image(systemName: isRecording ? "stop.fill" : "mic.fill")
                                .font(.title)
                                .foregroundColor(.white)
                        }
                    }
                    .disabled(authorizationStatus == .denied || authorizationStatus == .restricted)

                    Spacer()

                    // Transcribed text area
                    if !transcribedText.isEmpty {
                        VStack(alignment: .leading, spacing: MorosIOS.spacing12) {
                            Text("Transcription")
                                .font(MorosIOS.fontLabel)
                                .foregroundColor(MorosIOS.textDim)
                                .textCase(.uppercase)

                            ScrollView {
                                Text(transcribedText)
                                    .font(MorosIOS.fontBody)
                                    .foregroundColor(MorosIOS.textMain)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .frame(maxHeight: 200)
                            .padding(MorosIOS.spacing12)
                            .background(MorosIOS.limit02)
                            .clipShape(RoundedRectangle(cornerRadius: 4))

                            Button(action: saveAsNote) {
                                HStack {
                                    Image(systemName: "arrow.down.circle.fill")
                                    Text("Save as Note")
                                        .font(MorosIOS.fontSubhead)
                                        .fontWeight(.medium)
                                }
                                .foregroundColor(MorosIOS.void)
                                .frame(maxWidth: .infinity)
                                .frame(height: MorosIOS.buttonHeight)
                                .background(MorosIOS.oracle)
                                .clipShape(RoundedRectangle(cornerRadius: 4))
                            }
                        }
                        .padding(.horizontal, MorosIOS.spacing16)
                    }

                    // Error message
                    if let error = errorMessage {
                        Text(error)
                            .font(MorosIOS.fontSmall)
                            .foregroundColor(MorosIOS.signal)
                            .padding(.horizontal, MorosIOS.spacing16)
                    }

                    Spacer()
                }
            }
            .navigationTitle("Voice Capture")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") {
                        stopRecording()
                        dismiss()
                    }
                    .foregroundColor(MorosIOS.ambient)
                }
            }
            .onAppear(perform: requestAuthorization)
            .onDisappear(perform: stopRecording)
            .overlay {
                if showSaved {
                    savedOverlay
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Waveform

    private var waveformView: some View {
        HStack(spacing: 3) {
            ForEach(0..<20, id: \.self) { index in
                let barHeight = isRecording ? barHeightFor(index: index) : 4.0
                RoundedRectangle(cornerRadius: 2)
                    .fill(isRecording ? MorosIOS.oracle : MorosIOS.textGhost)
                    .frame(width: 4, height: barHeight)
                    .animation(
                        .easeInOut(duration: 0.15).delay(Double(index) * 0.01),
                        value: audioLevel
                    )
            }
        }
    }

    private func barHeightFor(index: Int) -> CGFloat {
        let base = CGFloat(audioLevel) * 60
        let variance = sin(Double(index) * 0.5 + Double(audioLevel) * 10) * 0.5 + 0.5
        return max(4, base * CGFloat(variance) + 4)
    }

    // MARK: - Status

    private var statusText: String {
        switch authorizationStatus {
        case .notDetermined:
            return "Requesting permission..."
        case .denied, .restricted:
            return "Speech recognition not available"
        case .authorized:
            return isRecording ? "Listening..." : "Tap to record"
        @unknown default:
            return "Tap to record"
        }
    }

    // MARK: - Authorization

    private func requestAuthorization() {
        SFSpeechRecognizer.requestAuthorization { status in
            DispatchQueue.main.async {
                authorizationStatus = status
            }
        }
    }

    // MARK: - Recording

    private func toggleRecording() {
        if isRecording {
            stopRecording()
        } else {
            startRecording()
        }
    }

    private func startRecording() {
        guard let recognizer = speechRecognizer, recognizer.isAvailable else {
            errorMessage = "Speech recognizer not available"
            return
        }

        let audioSession = AVAudioSession.sharedInstance()
        do {
            try audioSession.setCategory(.record, mode: .measurement, options: .duckOthers)
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            errorMessage = "Audio session error: \(error.localizedDescription)"
            return
        }

        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let request = recognitionRequest else { return }
        request.shouldReportPartialResults = true

        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { buffer, _ in
            request.append(buffer)

            // Calculate audio level
            let channelData = buffer.floatChannelData?[0]
            let frameLength = Int(buffer.frameLength)
            if let data = channelData, frameLength > 0 {
                var sum: Float = 0
                for i in 0..<frameLength {
                    sum += abs(data[i])
                }
                let avg = sum / Float(frameLength)
                DispatchQueue.main.async {
                    self.audioLevel = min(avg * 10, 1.0)
                }
            }
        }

        recognitionTask = recognizer.recognitionTask(with: request) { result, error in
            if let result = result {
                DispatchQueue.main.async {
                    transcribedText = result.bestTranscription.formattedString
                }
            }
            if error != nil || (result?.isFinal ?? false) {
                DispatchQueue.main.async {
                    stopRecording()
                }
            }
        }

        audioEngine.prepare()
        do {
            try audioEngine.start()
            isRecording = true
            errorMessage = nil
        } catch {
            errorMessage = "Could not start audio engine: \(error.localizedDescription)"
        }
    }

    private func stopRecording() {
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        recognitionRequest = nil
        recognitionTask = nil
        isRecording = false
        audioLevel = 0
    }

    // MARK: - Save

    private func saveAsNote() {
        guard !transcribedText.isEmpty else { return }

        let noteService = NoteService(context: viewContext)
        let firstLine = transcribedText.components(separatedBy: .newlines).first ?? "Voice Note"
        let noteTitle = String(firstLine.prefix(60))
        noteService.createNote(
            title: noteTitle,
            content: transcribedText,
            paraCategory: .inbox
        )

        withAnimation(.easeInOut(duration: MorosIOS.animBase)) {
            showSaved = true
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            withAnimation(.easeInOut(duration: MorosIOS.animBase)) {
                showSaved = false
            }
            transcribedText = ""
            dismiss()
        }
    }

    // MARK: - Saved Overlay

    private var savedOverlay: some View {
        VStack(spacing: MorosIOS.spacing12) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 48))
                .foregroundColor(MorosIOS.verdit)
            Text("Saved")
                .font(MorosIOS.fontH3)
                .foregroundColor(MorosIOS.textMain)
        }
        .padding(MorosIOS.spacing32)
        .background(MorosIOS.limit02)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .morosIOSGlow(MorosIOS.verdit, radius: 12)
        .transition(.opacity.combined(with: .scale(scale: 0.9)))
    }
}
