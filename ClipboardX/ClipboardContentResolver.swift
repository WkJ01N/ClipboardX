import Foundation

enum ClipboardContentResolver {
    static func text(for item: ClipboardItem) -> String {
        guard item.isSensitive, let encrypted = item.encryptedContent else { return item.content }
        return (try? SensitiveDataService.shared.decrypt(encrypted)) ?? String(localized: "无法解密此敏感记录")
    }

    static func imageData(for item: ClipboardItem) -> Data? {
        if let relativePath = item.payloadRelativePath {
            return try? PayloadStore.shared.read(relativePath: relativePath)
        }
        return item.itemData
    }
}
