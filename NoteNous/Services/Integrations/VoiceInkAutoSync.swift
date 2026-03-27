import Foundation
import CoreData
import os.log

/// Background auto-sync daemon that periodically checks VoiceInk for new transcriptions
/// and imports them into NoteNous as fleeting notes.
final class VoiceInkAutoSync {
    static let shared = VoiceInkAutoSync()

    private var timer: Timer?
    private let interval: TimeInterval = 300 // 5 minutes
    private let logger = Logger(subsystem: "com.notenous.app", category: "VoiceInkAutoSync")
    private let voiceInkService = VoiceInkService.shared

    private static let enabledKey = "voiceInkAutoSyncEnabled"

    var isEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: Self.enabledKey) }
        set { UserDefaults.standard.set(newValue, forKey: Self.enabledKey) }
    }

    var isRunning: Bool { timer != nil }

    private init() {}

    @MainActor
    func startAutoSync(context: NSManagedObjectContext) {
        guard timer == nil else { return }
        guard voiceInkService.isAvailable else {
            logger.info("VoiceInk not available, auto-sync not started")
            return
        }

        logger.info("Starting VoiceInk auto-sync (interval: \(self.interval)s)")
        isEnabled = true

        // Run immediately once with a fresh background context
        Task {
            let freshContext = CoreDataStack.shared.newBackgroundContext()
            await checkAndSync(context: freshContext)
        }

        // Schedule recurring check — create a fresh context each time to avoid stale state
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                let freshContext = CoreDataStack.shared.newBackgroundContext()
                await self.checkAndSync(context: freshContext)
            }
        }
    }

    func stopAutoSync() {
        timer?.invalidate()
        timer = nil
        isEnabled = false
        logger.info("VoiceInk auto-sync stopped")
    }

    @MainActor
    private func checkAndSync(context: NSManagedObjectContext) async {
        let stats = await voiceInkService.sync(context: context)

        if stats.notesCreated > 0 {
            logger.info("Auto-sync: created \(stats.notesCreated) notes from VoiceInk")

            // Post notification for UI update
            NotificationCenter.default.post(
                name: .voiceInkAutoSyncCompleted,
                object: nil,
                userInfo: ["notesCreated": stats.notesCreated]
            )
        }
    }
}

// MARK: - Notification

extension Notification.Name {
    static let voiceInkAutoSyncCompleted = Notification.Name("voiceInkAutoSyncCompleted")
}
