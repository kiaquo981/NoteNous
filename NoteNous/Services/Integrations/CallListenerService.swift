import ScreenCaptureKit
import Speech
import AVFoundation
import CoreAudio
import os.log

/// Captures audio during calls and transcribes in real-time using on-device Speech framework.
/// Auto-detects BlackHole virtual audio driver for capturing BOTH sides of the call.
/// Falls back to mic-only if BlackHole is not installed.
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

    enum CaptureMode: String {
        case micOnly = "Mic Only (your voice)"
        case bothSides = "Both Sides (mic + system audio via BlackHole)"
    }

    @Published var state: ListenerState = .idle
    @Published var isListening: Bool = false
    @Published var liveTranscription: String = ""
    @Published var duration: TimeInterval = 0
    @Published var audioLevel: Float = 0
    @Published var captureMode: CaptureMode = .micOnly
    @Published var blackHoleAvailable: Bool = false

    private let logger = Logger(subsystem: "com.notenous.app", category: "CallListener")
    private var speechRecognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var audioEngine: AVAudioEngine?
    private var timer: Timer?
    private var startTime: Date?
    private var createdAggregateDeviceID: AudioDeviceID = 0

    private init() {
        blackHoleAvailable = findBlackHoleDeviceID() != nil
        if blackHoleAvailable {
            captureMode = .bothSides
            logger.info("BlackHole detected — both-sides capture available")
        }
    }

    // MARK: - BlackHole Detection & Aggregate Device

    /// Find the BlackHole 2ch audio device ID
    private func findBlackHoleDeviceID() -> AudioDeviceID? {
        var propertySize: UInt32 = 0
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &propertySize)
        let deviceCount = Int(propertySize) / MemoryLayout<AudioDeviceID>.size
        var devices = [AudioDeviceID](repeating: 0, count: deviceCount)
        AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &propertySize, &devices)

        for device in devices {
            if let name = getDeviceName(device), name.lowercased().contains("blackhole") {
                return device
            }
        }
        return nil
    }

    /// Find the built-in microphone device ID
    private func findBuiltInMicDeviceID() -> AudioDeviceID? {
        var propertySize: UInt32 = 0
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &propertySize)
        let deviceCount = Int(propertySize) / MemoryLayout<AudioDeviceID>.size
        var devices = [AudioDeviceID](repeating: 0, count: deviceCount)
        AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &propertySize, &devices)

        for device in devices {
            if let name = getDeviceName(device),
               (name.lowercased().contains("built-in") || name.lowercased().contains("macbook")) &&
               deviceHasInputChannels(device) {
                return device
            }
        }
        // Fallback: return default input device
        var defaultInput = AudioDeviceID(0)
        var defaultSize = UInt32(MemoryLayout<AudioDeviceID>.size)
        var defaultAddr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &defaultAddr, 0, nil, &defaultSize, &defaultInput)
        return defaultInput != 0 ? defaultInput : nil
    }

    private func getDeviceName(_ deviceID: AudioDeviceID) -> String? {
        var name: CFString = "" as CFString
        var size = UInt32(MemoryLayout<CFString>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceNameCFString,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &name)
        return status == noErr ? name as String : nil
    }

    private func deviceHasInputChannels(_ deviceID: AudioDeviceID) -> Bool {
        var size: UInt32 = 0
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: kAudioDevicePropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectGetPropertyDataSize(deviceID, &address, 0, nil, &size)
        guard size > 0 else { return false }
        let bufferList = UnsafeMutablePointer<AudioBufferList>.allocate(capacity: 1)
        defer { bufferList.deallocate() }
        AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, bufferList)
        let buffers = UnsafeMutableAudioBufferListPointer(bufferList)
        return buffers.reduce(0) { $0 + Int($1.mNumberChannels) } > 0
    }

    /// Detect what output and input the user is CURRENTLY using
    private func detectCurrentAudioDevices() -> (outputID: AudioDeviceID, outputName: String, inputID: AudioDeviceID, inputName: String) {
        // Get current default output (what user hears through)
        var outputID = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &outputID)

        // Get current default input (what user speaks into)
        var inputID = AudioDeviceID(0)
        addr.mSelector = kAudioHardwarePropertyDefaultInputDevice
        AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &inputID)

        let outputName = getDeviceName(outputID) ?? "Unknown"
        let inputName = getDeviceName(inputID) ?? "Unknown"

        logger.info("Current audio: Output=\(outputName) (\(outputID)), Input=\(inputName) (\(inputID))")
        return (outputID, outputName, inputID, inputName)
    }

    private var savedOutputDeviceID: AudioDeviceID = 0
    private var createdMultiOutputDeviceID: AudioDeviceID = 0

    /// Full auto-setup: creates Multi-Output (speakers + BlackHole) AND Aggregate (mic + BlackHole)
    /// Returns the aggregate device ID to use as input, or nil on failure
    private func autoSetupBothSidesCapture() -> AudioDeviceID? {
        guard let blackHoleID = findBlackHoleDeviceID(),
              let bhUID = getDeviceUID(blackHoleID) else {
            logger.warning("BlackHole not found")
            return nil
        }

        let current = detectCurrentAudioDevices()

        guard let currentOutputUID = getDeviceUID(current.outputID),
              let currentInputUID = getDeviceUID(current.inputID) else {
            logger.warning("Cannot get current device UIDs")
            return nil
        }

        // Save current output to restore later
        savedOutputDeviceID = current.outputID

        // Step 1: Create Multi-Output Device (current output + BlackHole)
        // This routes call audio to BOTH the user's speakers/headphones AND BlackHole
        let multiOutputDesc: [String: Any] = [
            kAudioAggregateDeviceNameKey as String: "NoteNous Multi-Output",
            kAudioAggregateDeviceUIDKey as String: "com.notenous.multioutput.\(UUID().uuidString.prefix(8))",
            kAudioAggregateDeviceIsPrivateKey as String: true,
            kAudioAggregateDeviceSubDeviceListKey as String: [
                [kAudioSubDeviceUIDKey as String: currentOutputUID],
                [kAudioSubDeviceUIDKey as String: bhUID]
            ]
        ]

        var multiOutputID: AudioDeviceID = 0
        var status = AudioHardwareCreateAggregateDevice(multiOutputDesc as CFDictionary, &multiOutputID)

        guard status == noErr else {
            logger.error("Failed to create multi-output device: \(status)")
            return nil
        }
        createdMultiOutputDeviceID = multiOutputID
        logger.info("Created multi-output: \(current.outputName) + BlackHole (ID: \(multiOutputID))")

        // Set system output to the multi-output device
        var mutableMultiOutputID = multiOutputID
        var outputAddr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectSetPropertyData(AudioObjectID(kAudioObjectSystemObject), &outputAddr, 0, nil,
                                   UInt32(MemoryLayout<AudioDeviceID>.size), &mutableMultiOutputID)
        logger.info("System output set to multi-output device")

        // Step 2: Create Aggregate Input Device (current mic + BlackHole)
        // This lets NoteNous capture BOTH the user's voice AND the call audio
        let aggregateDesc: [String: Any] = [
            kAudioAggregateDeviceNameKey as String: "NoteNous Call Capture",
            kAudioAggregateDeviceUIDKey as String: "com.notenous.aggregate.\(UUID().uuidString.prefix(8))",
            kAudioAggregateDeviceIsPrivateKey as String: true,
            kAudioAggregateDeviceSubDeviceListKey as String: [
                [kAudioSubDeviceUIDKey as String: currentInputUID],
                [kAudioSubDeviceUIDKey as String: bhUID]
            ]
        ]

        var aggregateID: AudioDeviceID = 0
        status = AudioHardwareCreateAggregateDevice(aggregateDesc as CFDictionary, &aggregateID)

        guard status == noErr else {
            logger.error("Failed to create aggregate device: \(status)")
            // Cleanup multi-output
            restoreAudioRouting()
            return nil
        }
        createdAggregateDeviceID = aggregateID
        logger.info("Created aggregate input: \(current.inputName) + BlackHole (ID: \(aggregateID))")

        return aggregateID
    }

    /// Restore original audio routing — destroy temp devices, reset system output
    private func restoreAudioRouting() {
        // Restore original output device
        if savedOutputDeviceID != 0 {
            var mutableID = savedOutputDeviceID
            var addr = AudioObjectPropertyAddress(
                mSelector: kAudioHardwarePropertyDefaultOutputDevice,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            AudioObjectSetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil,
                                       UInt32(MemoryLayout<AudioDeviceID>.size), &mutableID)
            let name = getDeviceName(savedOutputDeviceID) ?? "Unknown"
            logger.info("Restored system output to: \(name)")
            savedOutputDeviceID = 0
        }

        // Destroy multi-output device
        if createdMultiOutputDeviceID != 0 {
            AudioHardwareDestroyAggregateDevice(createdMultiOutputDeviceID)
            logger.info("Destroyed multi-output device")
            createdMultiOutputDeviceID = 0
        }
    }

    private func getDeviceUID(_ deviceID: AudioDeviceID) -> String? {
        var uid: CFString = "" as CFString
        var size = UInt32(MemoryLayout<CFString>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceUID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &uid)
        return status == noErr ? uid as String : nil
    }

    /// Destroy the aggregate device on cleanup
    private func destroyAggregateDevice() {
        guard createdAggregateDeviceID != 0 else { return }
        AudioHardwareDestroyAggregateDevice(createdAggregateDeviceID)
        logger.info("Destroyed aggregate device: \(self.createdAggregateDeviceID)")
        createdAggregateDeviceID = 0
    }

    /// Set the audio engine's input to a specific device
    private func setAudioEngineInputDevice(_ deviceID: AudioDeviceID) {
        guard let audioEngine else { return }
        let inputNode = audioEngine.inputNode
        let audioUnit = inputNode.audioUnit!

        var deviceIDVar = deviceID
        AudioUnitSetProperty(
            audioUnit,
            kAudioOutputUnitProperty_CurrentDevice,
            kAudioUnitScope_Global,
            0,
            &deviceIDVar,
            UInt32(MemoryLayout<AudioDeviceID>.size)
        )
        logger.info("Set audio engine input to device: \(deviceID)")
    }

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

        // Setup audio capture via AVAudioEngine
        audioEngine = AVAudioEngine()
        guard let audioEngine else {
            await MainActor.run { state = .error("Failed to create audio engine") }
            return
        }

        // Auto-setup both-sides capture if BlackHole available
        if captureMode == .bothSides, blackHoleAvailable {
            if let aggregateID = autoSetupBothSidesCapture() {
                setAudioEngineInputDevice(aggregateID)
                let current = detectCurrentAudioDevices()
                logger.info("Both-sides capture ready: mic=\(current.inputName) + system audio via BlackHole")
            } else {
                logger.warning("Auto-setup failed, falling back to mic-only")
                await MainActor.run { captureMode = .micOnly }
            }
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

        // Cleanup: restore original audio routing + destroy temp devices
        restoreAudioRouting()
        destroyAggregateDevice()

        let finalTranscription = liveTranscription

        state = .idle
        isListening = false
        audioLevel = 0

        logger.info("Call listener stopped. Mode: \(self.captureMode.rawValue). Transcribed \(finalTranscription.count) chars")
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
