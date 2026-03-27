import Foundation
import CoreData
import os.log

/// Schedules the Zettelkasten Agent to run automatically at a configured time (default 23:59).
/// Processes all unprocessed notes from the day:
/// - Classifies fleeting notes
/// - Suggests promotions to permanent
/// - Proposes Folgezettel placement
/// - Creates links between related notes
/// - Updates the keyword index
/// - Identifies notes to split or merge
///
/// Results are saved for the user to review in the morning.
final class NightlyAgentScheduler: ObservableObject {
    static let shared = NightlyAgentScheduler()

    private let logger = Logger(subsystem: "com.notenous.app", category: "NightlyScheduler")

    @Published var isEnabled: Bool {
        didSet { UserDefaults.standard.set(isEnabled, forKey: "nightlyAgentEnabled") }
    }
    @Published var scheduledHour: Int {
        didSet {
            UserDefaults.standard.set(scheduledHour, forKey: "nightlyAgentHour")
            reschedule()
        }
    }
    @Published var scheduledMinute: Int {
        didSet {
            UserDefaults.standard.set(scheduledMinute, forKey: "nightlyAgentMinute")
            reschedule()
        }
    }
    @Published var lastRunDate: Date? {
        didSet {
            if let date = lastRunDate {
                UserDefaults.standard.set(date, forKey: "nightlyAgentLastRun")
            }
        }
    }
    @Published var lastRunStats: RunStats?
    @Published var isRunning: Bool = false
    @Published var pendingActionCount: Int = 0

    struct RunStats: Codable {
        let date: Date
        let notesProcessed: Int
        let actionsProposed: Int
        let classificationsProposed: Int
        let promotionsProposed: Int
        let linksProposed: Int
        let indexUpdatesProposed: Int
    }

    private var timer: Timer?

    private init() {
        isEnabled = UserDefaults.standard.object(forKey: "nightlyAgentEnabled") != nil
            ? UserDefaults.standard.bool(forKey: "nightlyAgentEnabled")
            : true  // enabled by default
        scheduledHour = UserDefaults.standard.object(forKey: "nightlyAgentHour") != nil
            ? UserDefaults.standard.integer(forKey: "nightlyAgentHour")
            : 23
        scheduledMinute = UserDefaults.standard.object(forKey: "nightlyAgentMinute") != nil
            ? UserDefaults.standard.integer(forKey: "nightlyAgentMinute")
            : 59
        lastRunDate = UserDefaults.standard.object(forKey: "nightlyAgentLastRun") as? Date

        if let statsData = UserDefaults.standard.data(forKey: "nightlyAgentLastStats") {
            lastRunStats = try? JSONDecoder().decode(RunStats.self, from: statsData)
        }
    }

    // MARK: - Schedule

    /// Start the scheduler — checks every minute if it's time to run
    func start() {
        guard isEnabled else {
            logger.info("Nightly agent disabled")
            return
        }

        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            self?.checkAndRun()
        }
        logger.info("Nightly agent scheduled for \(self.scheduledHour):\(String(format: "%02d", self.scheduledMinute))")
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        logger.info("Nightly agent stopped")
    }

    func reschedule() {
        stop()
        if isEnabled { start() }
    }

    // MARK: - Check & Run

    private func checkAndRun() {
        guard isEnabled, !isRunning else { return }

        let now = Date()
        let calendar = Calendar.current
        let hour = calendar.component(.hour, from: now)
        let minute = calendar.component(.minute, from: now)

        // Check if it's the scheduled time
        guard hour == scheduledHour && minute == scheduledMinute else { return }

        // Check if already ran today
        if let lastRun = lastRunDate {
            if calendar.isDate(lastRun, inSameDayAs: now) {
                return  // already ran today
            }
        }

        logger.info("Nightly agent triggered at \(hour):\(String(format: "%02d", minute))")
        runAgent()
    }

    /// Run the agent manually (also used by the scheduled trigger)
    func runAgent() {
        guard !isRunning else { return }
        isRunning = true

        Task { @MainActor in
            let context = CoreDataStack.shared.viewContext
            let agent = ZettelkastenAgent()

            await agent.processFleetingNotes(context: context)

            let actions = agent.actions
            let stats = RunStats(
                date: Date(),
                notesProcessed: actions.count,
                actionsProposed: actions.count,
                classificationsProposed: actions.filter { $0.type == .classify }.count,
                promotionsProposed: actions.filter { $0.type == .promote }.count,
                linksProposed: actions.filter { $0.type == .createLink }.count,
                indexUpdatesProposed: actions.filter { $0.type == .updateIndex }.count
            )

            // Save stats
            if let data = try? JSONEncoder().encode(stats) {
                UserDefaults.standard.set(data, forKey: "nightlyAgentLastStats")
            }

            await MainActor.run {
                lastRunDate = Date()
                lastRunStats = stats
                pendingActionCount = agent.actions.filter { $0.status == .pending }.count
                isRunning = false
                logger.info("Nightly agent complete: \(stats.actionsProposed) actions proposed")

                // Post notification for the user
                sendNotification(stats: stats)
            }
        }
    }

    // MARK: - Notification

    private func sendNotification(stats: RunStats) {
        let center = NSUserNotificationCenter.default
        let notification = NSUserNotification()
        notification.title = "NoteNous — Nightly Processing Complete"
        notification.informativeText = "\(stats.actionsProposed) actions ready for review: \(stats.promotionsProposed) promotions, \(stats.linksProposed) links, \(stats.classificationsProposed) classifications"
        notification.soundName = NSUserNotificationDefaultSoundName
        center.deliver(notification)
    }

    // MARK: - Display Helpers

    var scheduledTimeString: String {
        String(format: "%02d:%02d", scheduledHour, scheduledMinute)
    }

    var lastRunString: String? {
        guard let date = lastRunDate else { return nil }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}
