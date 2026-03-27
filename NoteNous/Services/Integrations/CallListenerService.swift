import ScreenCaptureKit
import Speech
import AVFoundation
import os.log

/// Captures microphone audio during calls and transcribes in real-time using on-device Speech framework.
///
/// NOTE: Basic mic capture only records YOUR voice. To capture both sides of a call (system audio + mic),
/// the user needs to route system audio through the mic input using a virtual audio device like BlackHole
/// (https://github.com/ExistentialAudio/BlackHole), or use a multi-output aggregate device in Audio MIDI Setup.
/// A future enhancement could use ScreenCaptureKit's `SCStreamConfiguration.capturesAudio` to capture
/// system audio directly, but that requires screen recording permission and additional mixing logic.
final class CallListenerService: ObservableObject {
    static let shared = CallListenerService()

    enum ListenerState: Equatable {
        case idle
        case preparing
        case listening
        case paused
        case error(String)

        static func == (lhs: ListenerState, rhs: ListenerState) -> Bool {
            switch (lhs, rhs) {
            case (.idle, .idle), (.preparing, .preparing),
                 (.listening, .listening), (.paused, .paused):
                return true
            case let (.error(a), .error(b)):
                return a == b
            default:
                return false
            }
        }
    }

    @Published var state: ListenerState = .idle
    @Published var isListening: Bool = false
    @Published var liveTranscription: String = ""
    @Published var duration: TimeInterval = 0
    @Published var audioLevel: Float = 0  // 0.0-1.0 for UI visualization

    private let logger = Logger(subsystem: "com.notenous.app", category: "CallListener")
    private var speechRecognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var audioEngine: AVAudioEngine?
    private var timer: Timer?
    private var startTime: Date?

    private init() {}

    // MARK: - Permissions

    /// Check and request all needed permissions
    func checkPermissions() async -> (microphone: Bool, speechRecognition: Bool) {
        let mic = await checkMicrophonePermission()
        let speech = await checkSpeechPermission()
        return (mic, speech)
    }

    private func checkMicrophonePermission() async -> Bool {
        let status = AVCaptureDevice.authorizationStatus(for: .audio)
        if status == .authorized { return true }
        if status == .notDetermined {
            return await AVCaptureDevice.requestAccess(for: .audio)
        }
        return false
    }

    private func checkSpeechPermission() async -> Bool {
        let status = SFSpeechRecognizer.authorizationStatus()
        if status == .authorized { return true }
        if status == .notDetermined {
            return await withCheckedContinuation { continuation in
                SFSpeechRecognizer.requestAuthorization { newStatus in
                    continuation.resume(returning: newStatus == .authorized)
                }
            }
        }
        return false
    }

    // MARK: - Start Listening

    /// Start capturing microphone audio and transcribing in real-time
    func startListening(language: String = "pt-BR") async {
        guard !isListening else { return }

        await MainActor.run {
            state = .preparing
            liveTranscription = ""
            duration = 0
            audioLevel = 0
        }

        // Setup speech recognizer
        let locale = Locale(identifier: language)
        speechRecognizer = SFSpeechRecognizer(locale: locale)

        guard let speechRecognizer, speechRecognizer.isAvailable else {
            await MainActor.run { state = .error("Speech recognizer not available for \(language)") }
            return
        }

        // Create recognition request
        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let recognitionRequest else {
            await MainActor.run { state = .error("Failed to create recognition request") }
            return
        }
        recognitionRequest.shouldReportPartialResults = true
        recognitionRequest.requiresOnDeviceRecognition = true  // on-device, no cloud

        // Start recognition task
        recognitionTask = speechRecognizer.recognitionTask(with: recognitionRequest) { [weak self] result, error in
            guard let self else { return }
            if let result {
                DispatchQueue.main.async {
                    self.liveTranscription = result.bestTranscription.formattedString
                }
            }
            if let error {
                self.logger.error("Recognition error: \(error.localizedDescription)")
                // Recognition auto-stops after ~60s of continuous speech, restart it
                if self.isListening {
                    Task { await self.restartRecognition(language: language) }
                }
            }
        }

        // Setup audio capture via AVAudioEngine (microphone input)
        audioEngine = AVAudioEngine()
        guard let audioEngine else {
            await MainActor.run { state = .error("Failed to create audio engine") }
            return
        }
        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, _ in
            self?.recognitionRequest?.append(buffer)

            // Calculate audio level for visualization
            guard let channelData = buffer.floatChannelData?[0] else { return }
            let frames = buffer.frameLength
            guard frames > 0 else { return }

            var sum: Float = 0
            for i in 0..<Int(frames) {
                sum += abs(channelData[i])
            }
            let avg = sum / Float(frames)
            DispatchQueue.main.async {
                self?.audioLevel = min(avg * 10, 1.0)
            }
        }

        do {
            try audioEngine.start()
            startTime = Date()

            await MainActor.run {
                state = .listening
                isListening = true
            }

            // Start duration timer
            await MainActor.run {
                timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
                    guard let self, let start = self.startTime else { return }
                    self.duration = Date().timeIntervalSince(start)
                }
            }

            logger.info("Call listener started with language: \(language)")
        } catch {
            await MainActor.run { state = .error("Failed to start audio: \(error.localizedDescription)") }
            logger.error("Audio engine start failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Stop Listening

    /// Stop capturing and return the final transcription text
    @discardableResult
    func stopListening() -> String {
        timer?.invalidate()
        timer = nil

        audioEngine?.stop()
        audioEngine?.inputNode.removeTap(onBus: 0)

        recognitionRequest?.endAudio()
        recognitionTask?.cancel()

        recognitionRequest = nil
        recognitionTask = nil
        audioEngine = nil

        let finalTranscription = liveTranscription

        state = .idle
        isListening = false
        audioLevel = 0

        logger.info("Call listener stopped. Transcribed \(finalTranscription.count) chars")
        return finalTranscription
    }

    // MARK: - Pause/Resume

    func pause() {
        audioEngine?.pause()
        timer?.invalidate()
        timer = nil
        state = .paused
    }

    func resume() {
        do {
            try audioEngine?.start()
            state = .listening
            // Restart duration timer from where we left off
            timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
                guard let self, let start = self.startTime else { return }
                self.duration = Date().timeIntervalSince(start)
            }
        } catch {
            logger.error("Failed to resume audio engine: \(error.localizedDescription)")
            state = .error("Failed to resume: \(error.localizedDescription)")
        }
    }

    // MARK: - Restart Recognition (handles ~60s limit)

    private func restartRecognition(language: String) async {
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()

        let savedText = await MainActor.run { liveTranscription }

        let newRequest = SFSpeechAudioBufferRecognitionRequest()
        newRequest.shouldReportPartialResults = true
        newRequest.requiresOnDeviceRecognition = true
        recognitionRequest = newRequest

        guard let speechRecognizer else { return }

        recognitionTask = speechRecognizer.recognitionTask(with: newRequest) { [weak self] result, error in
            guard let self else { return }
            if let result {
                DispatchQueue.main.async {
                    self.liveTranscription = savedText + "\n" + result.bestTranscription.formattedString
                }
            }
            if error != nil, self.isListening {
                Task { await self.restartRecognition(language: language) }
            }
        }

        logger.info("Recognition restarted (60s limit workaround)")
    }
}
