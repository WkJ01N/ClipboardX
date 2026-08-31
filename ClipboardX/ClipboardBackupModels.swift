import Foundation

struct ClipboardBackupPayload: Codable, Sendable {
    var version: Int
    var exportedAt: Date
    var items: [ClipboardBackupItem]
}

struct ClipboardBackupItem: Codable, Sendable {
    var id: UUID
    var content: String
    var createdAt: Date
    var itemType: String
    var itemDataBase64: String?
    var isPinned: Bool
    var isFavorite: Bool
    var isSensitive: Bool
    var sourceBundleIdentifier: String?
    var sourceAppName: String?
    var contentHash: String?
    var filePaths: [String]?
    var payloadTypeIdentifier: String?
}

struct EncryptedClipboardBackupEnvelope: Codable, Sendable {
    var format: String
    var version: Int
    var kdf: String
    var iterations: Int
    var saltBase64: String
    var sealedPayloadBase64: String
}
