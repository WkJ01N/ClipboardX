import Foundation

enum ClipboardContentResolver {
    enum ResolutionError: Error {
        case decryptionFailed
    }

    static func text(for item: ClipboardItem) -> String {
        (try? resolvedText(for: item)) ?? String(localized: "无法解密此敏感记录")
    }

    static func resolvedText(for item: ClipboardItem) throws -> String {
        guard item.isSensitive else { return item.content }
        guard let encrypted = item.encryptedContent else { throw ClipboardWriteError.decryptionFailed }
        do {
            return try SensitiveDataService.shared.decrypt(encrypted)
        } catch {
            throw ClipboardWriteError.decryptionFailed
        }
    }

    static func imageData(for item: ClipboardItem) -> Data? {
        try? resolvedImageData(for: item)
    }

    static func resolvedImageData(for item: ClipboardItem) throws -> Data? {
        if let relativePath = item.payloadRelativePath {
            return try PayloadStore.shared.read(relativePath: relativePath)
        }
        return item.itemData
    }
}
