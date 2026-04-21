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
}
