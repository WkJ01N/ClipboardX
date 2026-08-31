import AppKit
import SwiftData
import UniformTypeIdentifiers

@MainActor
enum DataExportManager {
    private enum ExportMode { case standard, encrypted(password: String) }

    static func exportBackup(using context: ModelContext) async throws -> URL {
        guard let mode = promptExportMode() else { throw cancellationError() }
        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        let encrypted: Bool
        if case .encrypted = mode { encrypted = true } else { encrypted = false }
        panel.nameFieldStringValue = defaultBackupFileName(encrypted: encrypted)
        panel.allowedContentTypes = encrypted
            ? [UTType(filenameExtension: "clipboardxbackup") ?? .data]
            : [.json]
        guard panel.runModal() == .OK, let destinationURL = panel.url else {
            throw cancellationError()
        }

        let descriptor = FetchDescriptor<ClipboardItem>(sortBy: [SortDescriptor(\.createdAt, order: .reverse)])
        let items = (try? context.fetch(descriptor)) ?? []

        let includedItems = encrypted ? items : items.filter { !$0.isSensitive }
        let backupItems = includedItems.map { item in
            ClipboardBackupItem(
                id: item.id,
                content: ClipboardContentResolver.text(for: item),
                createdAt: item.createdAt,
                itemType: item.itemType,
                itemDataBase64: ClipboardContentResolver.imageData(for: item)?.base64EncodedString(),
                isPinned: item.isPinned,
                isFavorite: item.isFavorite,
                isSensitive: item.isSensitive,
                sourceBundleIdentifier: item.sourceBundleIdentifier,
                sourceAppName: item.sourceAppName,
                contentHash: item.contentHash,
                filePaths: item.filePaths.isEmpty ? nil : item.filePaths,
                payloadTypeIdentifier: item.payloadTypeIdentifier
            )
        }
        let payload = ClipboardBackupPayload(version: 2, exportedAt: Date(), items: backupItems)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let payloadData = try encoder.encode(payload)
        let data: Data
        switch mode {
        case .standard:
            data = payloadData
        case .encrypted(let password):
            let envelope = try await Task.detached(priority: .userInitiated) {
                try PasswordBackupCrypto.seal(payloadData, password: password)
            }.value
            data = try encoder.encode(envelope)
        }

        try await Task.detached(priority: .utility) {
            try data.write(to: destinationURL, options: [.atomic])
        }.value
        return destinationURL
    }

    private static func defaultBackupFileName(encrypted: Bool) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let ext = encrypted ? "clipboardxbackup" : "json"
        return "ClipboardX_Backup_\(formatter.string(from: Date())).\(ext)"
    }

    private static func promptExportMode() -> ExportMode? {
        let alert = NSAlert()
        alert.messageText = String(localized: "选择备份方式")
        alert.informativeText = String(localized: "普通备份会排除敏感记录；完整备份使用口令加密全部内容。")
        alert.addButton(withTitle: String(localized: "普通备份"))
        alert.addButton(withTitle: String(localized: "完整加密备份"))
        alert.addButton(withTitle: String(localized: "取消"))
        switch alert.runModal() {
        case .alertFirstButtonReturn: return .standard
        case .alertSecondButtonReturn:
            guard let password = promptPassword(confirm: true) else { return nil }
            return .encrypted(password: password)
        default: return nil
        }
    }

    static func promptPassword(confirm: Bool) -> String? {
        let alert = NSAlert()
        alert.messageText = String(localized: confirm ? "设置备份口令" : "输入备份口令")
        alert.informativeText = String(localized: "口令不会被保存，遗失后无法恢复备份。")
        let first = NSSecureTextField(frame: NSRect(x: 0, y: confirm ? 30 : 0, width: 280, height: 24))
        first.placeholderString = String(localized: "口令（至少 8 个字符）")
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 280, height: confirm ? 58 : 24))
        container.addSubview(first)
        var second: NSSecureTextField?
        if confirm {
            let field = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 280, height: 24))
            field.placeholderString = String(localized: "再次输入口令")
            container.addSubview(field)
            second = field
        }
        alert.accessoryView = container
        alert.addButton(withTitle: String(localized: "确定"))
        alert.addButton(withTitle: String(localized: "取消"))
        guard alert.runModal() == .alertFirstButtonReturn,
              first.stringValue.count >= 8,
              second == nil || second?.stringValue == first.stringValue
        else { return nil }
        return first.stringValue
    }

    private static func cancellationError() -> NSError {
        NSError(domain: "ClipboardX.Export", code: NSUserCancelledError, userInfo: [NSLocalizedDescriptionKey: "cancelled"])
    }
}
