import AppKit
import SwiftData
import UniformTypeIdentifiers

enum DataImportMode {
    case merge
    case overwrite
}

@MainActor
enum DataImportManager {
    static func importBackup(using context: ModelContext) async throws -> Int {
        let openPanel = NSOpenPanel()
        openPanel.canChooseFiles = true
        openPanel.canChooseDirectories = false
        openPanel.allowsMultipleSelection = false
        openPanel.allowedContentTypes = [.json]
        guard openPanel.runModal() == .OK, let fileURL = openPanel.url else {
            throw NSError(domain: "ClipboardX.Import", code: 0, userInfo: [NSLocalizedDescriptionKey: "cancelled"])
        }

        guard let mode = promptImportMode() else {
            throw NSError(domain: "ClipboardX.Import", code: 0, userInfo: [NSLocalizedDescriptionKey: "cancelled"])
        }

        let data = try await Task.detached(priority: .utility) {
            let data = try Data(contentsOf: fileURL)
            return data
        }.value
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let payload = try decoder.decode(ClipboardBackupPayload.self, from: data)

        return try applyImport(payload: payload, mode: mode, context: context)
    }

    private static func promptImportMode() -> DataImportMode? {
        let alert = NSAlert()
        alert.messageText = String(localized: "选择导入方式")
        alert.informativeText = String(localized: "请选择将备份数据合并到当前记录，还是覆盖当前记录。")
        alert.addButton(withTitle: String(localized: "合并"))
        alert.addButton(withTitle: String(localized: "覆盖当前"))
        alert.addButton(withTitle: String(localized: "取消"))
        alert.alertStyle = .informational

        let response = alert.runModal()
        switch response {
        case .alertFirstButtonReturn:
            return .merge
        case .alertSecondButtonReturn:
            return .overwrite
        default:
            return nil
        }
    }

    private static func applyImport(payload: ClipboardBackupPayload, mode: DataImportMode, context: ModelContext) throws -> Int {
        if mode == .overwrite {
            let allDescriptor = FetchDescriptor<ClipboardItem>()
            if let allItems = try? context.fetch(allDescriptor) {
                for item in allItems {
                    context.delete(item)
                }
            }
        }

        var existingKeys: Set<String> = []
        if mode == .merge {
            let existingDescriptor = FetchDescriptor<ClipboardItem>()
            let existingItems = (try? context.fetch(existingDescriptor)) ?? []
            existingKeys = Set(existingItems.map(makeDedupKey))
        }

        var inserted = 0
        for backupItem in payload.items {
            let newItem = ClipboardItem(
                id: backupItem.id,
                content: backupItem.content,
                createdAt: backupItem.createdAt,
                itemType: backupItem.itemType,
                itemData: backupItem.itemDataBase64.flatMap { Data(base64Encoded: $0) },
                isPinned: backupItem.isPinned,
                isFavorite: backupItem.isFavorite,
                isSensitive: backupItem.isSensitive
            )
            let key = makeDedupKey(newItem)
            if mode == .merge, existingKeys.contains(key) {
                continue
            }
            context.insert(newItem)
            existingKeys.insert(key)
            inserted += 1
        }

        try context.save()
        return inserted
    }

    private static func makeDedupKey(_ item: ClipboardItem) -> String {
        "\(item.itemType)|\(item.content)"
    }
}
