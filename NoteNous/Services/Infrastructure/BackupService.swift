import Foundation
import CoreData
import os.log

// MARK: - Backup Errors

enum BackupError: LocalizedError {
    case storeNotFound
    case metadataInvalid
    case compressionFailed
    case decompressionFailed
    case restoreFailed(String)

    var errorDescription: String? {
        switch self {
        case .storeNotFound:
            return "Core Data store file not found."
        case .metadataInvalid:
            return "Backup metadata is invalid or missing."
        case .compressionFailed:
            return "Failed to compress backup."
        case .decompressionFailed:
            return "Failed to decompress backup."
        case .restoreFailed(let reason):
            return "Restore failed: \(reason)"
        }
    }
}

// MARK: - Backup Metadata

struct BackupMetadata: Codable {
    let appVersion: String
    let createdAt: Date
    let noteCount: Int
    let backupVersion: Int

    static let currentVersion = 1
}

// MARK: - Backup Service

final class BackupService {
    private let logger = Logger(subsystem: "com.notenous.app", category: "BackupService")
    private let fileManager = FileManager.default

    private var appSupportDir: URL {
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("NoteNous", isDirectory: true)
    }

    private var storeURL: URL {
        appSupportDir.appendingPathComponent("NoteNous.sqlite")
    }

    // MARK: - Create Backup

    func createBackup(to destinationURL: URL) async -> Result<Void, Error> {
        do {
            // Create a temporary staging directory
            let tempDir = fileManager.temporaryDirectory
                .appendingPathComponent("notenous-backup-\(UUID().uuidString)", isDirectory: true)
            try fileManager.createDirectory(at: tempDir, withIntermediateDirectories: true)

            defer {
                try? fileManager.removeItem(at: tempDir)
            }

            // Copy sqlite files (main + WAL + SHM)
            let sqliteFiles = ["NoteNous.sqlite", "NoteNous.sqlite-wal", "NoteNous.sqlite-shm"]
            for filename in sqliteFiles {
                let source = appSupportDir.appendingPathComponent(filename)
                if fileManager.fileExists(atPath: source.path) {
                    let dest = tempDir.appendingPathComponent(filename)
                    try fileManager.copyItem(at: source, to: dest)
                }
            }

            guard fileManager.fileExists(atPath: tempDir.appendingPathComponent("NoteNous.sqlite").path) else {
                return .failure(BackupError.storeNotFound)
            }

            // Count notes for metadata
            let noteCount = countSqliteNotes()

            // Create metadata
            let metadata = BackupMetadata(
                appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1.0",
                createdAt: Date(),
                noteCount: noteCount,
                backupVersion: BackupMetadata.currentVersion
            )

            let metadataData = try JSONEncoder().encode(metadata)
            try metadataData.write(to: tempDir.appendingPathComponent("metadata.json"))

            // Compress to zip
            let coordinator = NSFileCoordinator()
            var compressError: NSError?

            // Remove destination if it exists
            if fileManager.fileExists(atPath: destinationURL.path) {
                try fileManager.removeItem(at: destinationURL)
            }

            coordinator.coordinate(readingItemAt: tempDir, options: .forUploading, error: &compressError) { zipURL in
                do {
                    try self.fileManager.copyItem(at: zipURL, to: destinationURL)
                } catch {
                    self.logger.error("Failed to copy zip: \(error.localizedDescription)")
                }
            }

            if let error = compressError {
                return .failure(error)
            }

            logger.info("Backup created at \(destinationURL.path)")
            return .success(())

        } catch {
            logger.error("Backup failed: \(error.localizedDescription)")
            return .failure(error)
        }
    }

    // MARK: - Restore Backup

    func restoreBackup(from sourceURL: URL) async -> Result<Void, Error> {
        do {
            // Create temp directory for extraction
            let tempDir = fileManager.temporaryDirectory
                .appendingPathComponent("notenous-restore-\(UUID().uuidString)", isDirectory: true)
            try fileManager.createDirectory(at: tempDir, withIntermediateDirectories: true)

            defer {
                try? fileManager.removeItem(at: tempDir)
            }

            // Decompress zip
            let coordinator = NSFileCoordinator()
            var decompressError: NSError?

            coordinator.coordinate(readingItemAt: sourceURL, options: .forUploading, error: &decompressError) { _ in
                // NSFileCoordinator with forUploading compresses; we need the opposite
            }

            // Use Process to unzip
            let unzipProcess = Process()
            unzipProcess.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
            unzipProcess.arguments = ["-o", sourceURL.path, "-d", tempDir.path]
            unzipProcess.standardOutput = nil
            unzipProcess.standardError = nil

            try unzipProcess.run()
            unzipProcess.waitUntilExit()

            guard unzipProcess.terminationStatus == 0 else {
                return .failure(BackupError.decompressionFailed)
            }

            // Validate metadata
            let metadataURL = tempDir.appendingPathComponent("metadata.json")
            guard fileManager.fileExists(atPath: metadataURL.path) else {
                return .failure(BackupError.metadataInvalid)
            }

            let metadataData = try Data(contentsOf: metadataURL)
            let metadata = try JSONDecoder().decode(BackupMetadata.self, from: metadataData)

            guard metadata.backupVersion <= BackupMetadata.currentVersion else {
                return .failure(BackupError.restoreFailed("Backup version \(metadata.backupVersion) is newer than supported version \(BackupMetadata.currentVersion)"))
            }

            // Ensure app support directory exists
            try fileManager.createDirectory(at: appSupportDir, withIntermediateDirectories: true)

            // Replace sqlite files
            let sqliteFiles = ["NoteNous.sqlite", "NoteNous.sqlite-wal", "NoteNous.sqlite-shm"]
            for filename in sqliteFiles {
                let dest = appSupportDir.appendingPathComponent(filename)
                let source = tempDir.appendingPathComponent(filename)

                // Remove existing
                if fileManager.fileExists(atPath: dest.path) {
                    try fileManager.removeItem(at: dest)
                }

                // Copy from backup if exists
                if fileManager.fileExists(atPath: source.path) {
                    try fileManager.copyItem(at: source, to: dest)
                }
            }

            logger.info("Restore completed from backup created \(metadata.createdAt) with \(metadata.noteCount) notes")
            return .success(())

        } catch {
            logger.error("Restore failed: \(error.localizedDescription)")
            return .failure(error)
        }
    }

    // MARK: - Helpers

    private func countSqliteNotes() -> Int {
        // Quick count via Core Data
        let context = CoreDataStack.shared.viewContext
        let request = NoteEntity.fetchRequest() as! NSFetchRequest<NoteEntity>
        return (try? context.count(for: request)) ?? 0
    }
}
