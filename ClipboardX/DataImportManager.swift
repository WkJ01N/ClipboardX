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
        openPanel.allowedContentTypes = [.json, UTType(filenameExtension: "clipboardxbackup") ?? .data]
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
        let payloadData: Data
        if let envelope = try? decoder.decode(EncryptedClipboardBackupEnvelope.self, from: data),
           envelope.format == "ClipboardXEncryptedBackup" {
            guard let password = DataExportManager.promptPassword(confirm: false) else {
                throw NSError(domain: "ClipboardX.Import", code: NSUserCancelledError, userInfo: [NSLocalizedDescriptionKey: "cancelled"])
            }
            payloadData = try await Task.detached(priority: .userInitiated) {
                try PasswordBackupCrypto.open(envelope, password: password)
            }.value
        } else {
            payloadData = data
        }
        let payload = try decoder.decode(ClipboardBackupPayload.self, from: payloadData)
        guard payload.version == 1 || payload.version == 2 else {
            throw NSError(domain: "ClipboardX.Import", code: 2, userInfo: [NSLocalizedDescriptionKey: "unsupported backup version"])
        }

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
        var replacedPayloads: [String] = []
        if mode == .overwrite {
            let allDescriptor = FetchDescriptor<ClipboardItem>()
            if let allItems = try? context.fetch(allDescriptor) {
                for item in allItems {
                    if let path = item.payloadRelativePath { replacedPayloads.append(path) }
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
        var writtenPayloads: [String] = []
        do {
        for backupItem in payload.items {
            let rawKey = "\(backupItem.itemType)|\(backupItem.content)"
            if mode == .merge, existingKeys.contains(rawKey) { continue }
            let encryptedContent = backupItem.isSensitive
                ? try SensitiveDataService.shared.encrypt(backupItem.content)
                : nil
            let id = backupItem.id
            var payloadPath: String?
            if backupItem.itemType == ClipboardItemKind.image.rawValue,
               let encoded = backupItem.itemDataBase64,
               let imageData = Data(base64Encoded: encoded) {
                payloadPath = try PayloadStore.shared.write(imageData, id: id)
                if let payloadPath { writtenPayloads.append(payloadPath) }
            }
            let newItem = ClipboardItem(
                id: id,
                content: backupItem.isSensitive ? "" : backupItem.content,
                createdAt: backupItem.createdAt,
                itemType: backupItem.itemType,
                isPinned: backupItem.isPinned,
                isFavorite: backupItem.isFavorite,
                isSensitive: backupItem.isSensitive,
                sourceBundleIdentifier: backupItem.sourceBundleIdentifier,
                sourceAppName: backupItem.sourceAppName,
                contentHash: backupItem.contentHash,
                filePaths: backupItem.filePaths ?? (backupItem.itemType == "file" ? [backupItem.content] : []),
                payloadRelativePath: payloadPath,
                payloadByteCount: Int64(backupItem.itemDataBase64.flatMap { Data(base64Encoded: $0)?.count } ?? 0),
                payloadTypeIdentifier: backupItem.payloadTypeIdentifier,
                encryptedContent: encryptedContent,
                encryptionVersion: encryptedContent == nil ? 0 : 1
            )
            let key = makeDedupKey(newItem)
            context.insert(newItem)
            existingKeys.insert(key)
            inserted += 1
        }

        try context.save()
        for path in replacedPayloads { PayloadStore.shared.remove(relativePath: path) }
        return inserted
        } catch {
            context.rollback()
            for path in writtenPayloads { PayloadStore.shared.remove(relativePath: path) }
            throw error
        }
    }

    private static func makeDedupKey(_ item: ClipboardItem) -> String {
        "\(item.itemType)|\(item.content)"
    }
}
