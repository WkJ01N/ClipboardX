import AppKit
import SwiftData
import UniformTypeIdentifiers

@MainActor
enum DataExportManager {
    static func exportBackup(using context: ModelContext) async throws -> URL {
        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        panel.nameFieldStringValue = defaultBackupFileName()
        panel.allowedContentTypes = [.json]
        guard panel.runModal() == .OK, let destinationURL = panel.url else {
            throw NSError(domain: "ClipboardX.Export", code: 0, userInfo: [NSLocalizedDescriptionKey: "cancelled"])
        }

        let descriptor = FetchDescriptor<ClipboardItem>(sortBy: [SortDescriptor(\.createdAt, order: .reverse)])
        let items = (try? context.fetch(descriptor)) ?? []

        let backupItems = items.map { item in
            ClipboardBackupItem(
                id: item.id,
                content: item.content,
                createdAt: item.createdAt,
                itemType: item.itemType,
                itemDataBase64: item.itemData?.base64EncodedString(),
                isPinned: item.isPinned,
                isFavorite: item.isFavorite,
                isSensitive: item.isSensitive
            )
        }
        let payload = ClipboardBackupPayload(version: 1, exportedAt: Date(), items: backupItems)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(payload)

        try await Task.detached(priority: .utility) {
            try data.write(to: destinationURL, options: [.atomic])
        }.value
        return destinationURL
    }

    private static func defaultBackupFileName() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        return "ClipboardX_Backup_\(formatter.string(from: Date())).json"
    }
}
