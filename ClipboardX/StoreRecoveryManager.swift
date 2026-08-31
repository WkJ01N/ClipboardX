import Foundation
import SwiftData

enum StoreRecoveryManager {
    static let snapshotDefaultsKey = "didCreateV2MigrationSnapshot"
    static let pendingRestoreDefaultsKey = "pendingRestoreSnapshotURL"

    static func createMigrationSnapshotIfNeeded(storeURL: URL) throws -> URL? {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: snapshotDefaultsKey) else { return nil }
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: storeURL.path) else {
            defaults.set(true, forKey: snapshotDefaultsKey)
            return nil
        }

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let snapshotRoot = storeURL.deletingLastPathComponent()
            .appendingPathComponent("RecoverySnapshots", isDirectory: true)
            .appendingPathComponent("pre-v2-\(formatter.string(from: Date()))", isDirectory: true)
        try fileManager.createDirectory(at: snapshotRoot, withIntermediateDirectories: true)

        for suffix in ["", "-wal", "-shm"] {
            let source = URL(fileURLWithPath: storeURL.path + suffix)
            guard fileManager.fileExists(atPath: source.path) else { continue }
            try fileManager.copyItem(at: source, to: snapshotRoot.appendingPathComponent(source.lastPathComponent))
        }
        let payloads = storeURL.deletingLastPathComponent().appendingPathComponent("Payloads", isDirectory: true)
        if fileManager.fileExists(atPath: payloads.path) {
            try fileManager.copyItem(at: payloads, to: snapshotRoot.appendingPathComponent("Payloads", isDirectory: true))
        }
        defaults.set(true, forKey: snapshotDefaultsKey)
        return snapshotRoot
    }

    /// A location change is staged in settings and applied before SwiftData opens.
    static func applyPendingLocationIfNeeded(currentStoreURL: URL) throws -> URL {
        let defaults = UserDefaults.standard
        guard let pendingPath = defaults.string(forKey: "pendingStorageURL"), !pendingPath.isEmpty else {
            return currentStoreURL
        }
        let destinationDirectory = URL(fileURLWithPath: pendingPath, isDirectory: true)
        let destinationStore = destinationDirectory.appendingPathComponent("default.store")
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: destinationDirectory, withIntermediateDirectories: true)

        if fileManager.fileExists(atPath: currentStoreURL.path), !fileManager.fileExists(atPath: destinationStore.path) {
            for suffix in ["", "-wal", "-shm"] {
                let source = URL(fileURLWithPath: currentStoreURL.path + suffix)
                guard fileManager.fileExists(atPath: source.path) else { continue }
                try fileManager.copyItem(
                    at: source,
                    to: URL(fileURLWithPath: destinationStore.path + suffix)
                )
            }
            let sourcePayloads = currentStoreURL.deletingLastPathComponent().appendingPathComponent("Payloads")
            let destinationPayloads = destinationDirectory.appendingPathComponent("Payloads")
            if fileManager.fileExists(atPath: sourcePayloads.path), !fileManager.fileExists(atPath: destinationPayloads.path) {
                try fileManager.copyItem(at: sourcePayloads, to: destinationPayloads)
            }
        }

        defaults.set(pendingPath, forKey: "customStorageURL")
        defaults.removeObject(forKey: "pendingStorageURL")
        defaults.set(false, forKey: snapshotDefaultsKey)
        return destinationStore
    }

    static func latestSnapshot(for storeURL: URL) -> URL? {
        let root = storeURL.deletingLastPathComponent().appendingPathComponent("RecoverySnapshots")
        let candidates = (try? FileManager.default.contentsOfDirectory(
            at: root, includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        )) ?? []
        return candidates
            .filter { FileManager.default.fileExists(atPath: $0.appendingPathComponent(storeURL.lastPathComponent).path) }
            .max { lhs, rhs in
                let left = (try? lhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                let right = (try? rhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                return left < right
            }
    }

    static func queueRestore(snapshotURL: URL) {
        UserDefaults.standard.set(snapshotURL.path, forKey: pendingRestoreDefaultsKey)
    }

    /// Runs before SwiftData opens the database. Current files are archived first,
    /// and are restored automatically if copying the selected snapshot fails.
    static func applyPendingRestoreIfNeeded(currentStoreURL: URL) throws {
        let defaults = UserDefaults.standard
        guard let path = defaults.string(forKey: pendingRestoreDefaultsKey) else { return }
        let snapshot = URL(fileURLWithPath: path, isDirectory: true)
        let snapshotStore = snapshot.appendingPathComponent(currentStoreURL.lastPathComponent)
        guard FileManager.default.fileExists(atPath: snapshotStore.path) else {
            throw CocoaError(.fileNoSuchFile)
        }

        let archive = currentStoreURL.deletingLastPathComponent()
            .appendingPathComponent("RecoverySnapshots", isDirectory: true)
            .appendingPathComponent("pre-restore-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: archive, withIntermediateDirectories: true)
        let moved = try moveStoreFiles(from: currentStoreURL, to: archive)
        let currentPayloads = currentStoreURL.deletingLastPathComponent().appendingPathComponent("Payloads")
        let archivedPayloads = archive.appendingPathComponent("Payloads")
        if FileManager.default.fileExists(atPath: currentPayloads.path) {
            try FileManager.default.moveItem(at: currentPayloads, to: archivedPayloads)
        }
        do {
            for suffix in ["", "-wal", "-shm"] {
                let source = URL(fileURLWithPath: snapshotStore.path + suffix)
                guard FileManager.default.fileExists(atPath: source.path) else { continue }
                try FileManager.default.copyItem(at: source, to: URL(fileURLWithPath: currentStoreURL.path + suffix))
            }
            let snapshotPayloads = snapshot.appendingPathComponent("Payloads")
            if FileManager.default.fileExists(atPath: snapshotPayloads.path) {
                try FileManager.default.copyItem(at: snapshotPayloads, to: currentPayloads)
            }
            defaults.removeObject(forKey: pendingRestoreDefaultsKey)
            defaults.set(false, forKey: snapshotDefaultsKey)
        } catch {
            removeStoreFiles(at: currentStoreURL)
            try? FileManager.default.removeItem(at: currentPayloads)
            try restoreStoreFiles(moved, to: currentStoreURL)
            if FileManager.default.fileExists(atPath: archivedPayloads.path) {
                try FileManager.default.moveItem(at: archivedPayloads, to: currentPayloads)
            }
            throw error
        }
    }

    static func diagnosticData(error: String, storeURL: URL) throws -> Data {
        let snapshotsRoot = storeURL.deletingLastPathComponent().appendingPathComponent("RecoverySnapshots")
        let snapshots = ((try? FileManager.default.contentsOfDirectory(
            at: snapshotsRoot, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
        )) ?? []).map(\.lastPathComponent).sorted()
        let object: [String: Any] = [
            "applicationVersion": "2.1.0",
            "generatedAt": ISO8601DateFormatter().string(from: Date()),
            "storePath": storeURL.path,
            "storeExists": FileManager.default.fileExists(atPath: storeURL.path),
            "error": error,
            "recoverySnapshots": snapshots
        ]
        return try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
    }

    /// Imports stores created before ClipboardX adopted `VersionedSchema`.
    /// The original SQLite files are moved to a recoverable archive and restored
    /// automatically if creation of the v2 store fails.
    @MainActor
    static func rebuildUnversionedStore(at storeURL: URL) throws -> ModelContainer {
        guard FileManager.default.fileExists(atPath: storeURL.path) else {
            throw CocoaError(.fileNoSuchFile)
        }
        let records = try readLegacyRecords(at: storeURL)
        let archiveDirectory = storeURL.deletingLastPathComponent()
            .appendingPathComponent("RecoverySnapshots", isDirectory: true)
            .appendingPathComponent("legacy-original-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: archiveDirectory, withIntermediateDirectories: true)
        let movedFiles = try moveStoreFiles(from: storeURL, to: archiveDirectory)

        do {
            let container = try ModelContainer(
                for: ClipboardItem.self,
                migrationPlan: ClipboardMigrationPlan.self,
                configurations: ModelConfiguration(url: storeURL)
            )
            for record in records {
                let encrypted = record.isSensitive ? try SensitiveDataService.shared.encrypt(record.content) : nil
                container.mainContext.insert(ClipboardItem(
                    id: record.id,
                    content: record.isSensitive ? "" : record.content,
                    createdAt: record.createdAt,
                    itemType: record.itemType,
                    itemData: record.itemData,
                    isPinned: record.isPinned,
                    isFavorite: record.isFavorite,
                    isSensitive: record.isSensitive,
                    encryptedContent: encrypted,
                    encryptionVersion: encrypted == nil ? 0 : 1
                ))
            }
            try container.mainContext.save()
            return container
        } catch {
            removeStoreFiles(at: storeURL)
            try restoreStoreFiles(movedFiles, to: storeURL)
            throw error
        }
    }

    private struct LegacyRecord {
        let id: UUID
        let content: String
        let createdAt: Date
        let itemType: String
        let itemData: Data?
        let isPinned: Bool
        let isFavorite: Bool
        let isSensitive: Bool
    }

    @MainActor
    private static func readLegacyRecords(at storeURL: URL) throws -> [LegacyRecord] {
        let container = try ModelContainer(
            for: ClipboardSchemaV1.ClipboardItem.self,
            configurations: ModelConfiguration(url: storeURL)
        )
        return try container.mainContext.fetch(FetchDescriptor<ClipboardSchemaV1.ClipboardItem>()).map {
            LegacyRecord(
                id: $0.id, content: $0.content, createdAt: $0.createdAt,
                itemType: $0.itemType, itemData: $0.itemData,
                isPinned: $0.isPinned, isFavorite: $0.isFavorite, isSensitive: $0.isSensitive
            )
        }
    }

    private static func moveStoreFiles(from storeURL: URL, to directory: URL) throws -> [(URL, URL)] {
        var moved: [(URL, URL)] = []
        do {
            for suffix in ["", "-wal", "-shm"] {
                let source = URL(fileURLWithPath: storeURL.path + suffix)
                guard FileManager.default.fileExists(atPath: source.path) else { continue }
                let destination = directory.appendingPathComponent(source.lastPathComponent)
                try FileManager.default.moveItem(at: source, to: destination)
                moved.append((source, destination))
            }
            return moved
        } catch {
            try? restoreStoreFiles(moved, to: storeURL)
            throw error
        }
    }

    private static func restoreStoreFiles(_ files: [(URL, URL)], to storeURL: URL) throws {
        for (original, archived) in files where FileManager.default.fileExists(atPath: archived.path) {
            try FileManager.default.moveItem(at: archived, to: original)
        }
    }

    private static func removeStoreFiles(at storeURL: URL) {
        for suffix in ["", "-wal", "-shm"] {
            let url = URL(fileURLWithPath: storeURL.path + suffix)
            try? FileManager.default.removeItem(at: url)
        }
    }
}
