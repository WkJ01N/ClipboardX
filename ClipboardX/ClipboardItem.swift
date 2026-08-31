import Foundation
import SwiftData

enum ClipboardItemKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case text
    case image
    case file

    var id: String { rawValue }
}

enum ClipboardSchemaV1: VersionedSchema {
    static let versionIdentifier = Schema.Version(1, 0, 0)
    static var models: [any PersistentModel.Type] { [ClipboardItem.self] }

    @Model
    final class ClipboardItem {
        var id: UUID
        var content: String
        var createdAt: Date
        var itemType: String
        var itemData: Data?
        var isPinned: Bool
        var isFavorite: Bool = false
        var isSensitive: Bool = false

        init(
            id: UUID = UUID(), content: String, createdAt: Date = Date(),
            itemType: String = "text", itemData: Data? = nil,
            isPinned: Bool = false, isFavorite: Bool = false, isSensitive: Bool = false
        ) {
            self.id = id
            self.content = content
            self.createdAt = createdAt
            self.itemType = itemType
            self.itemData = itemData
            self.isPinned = isPinned
            self.isFavorite = isFavorite
            self.isSensitive = isSensitive
        }
    }
}

enum ClipboardSchemaV2: VersionedSchema {
    static let versionIdentifier = Schema.Version(2, 0, 0)
    static var models: [any PersistentModel.Type] { [ClipboardItem.self] }

    @Model
    final class ClipboardItem {
        @Attribute(.unique) var id: UUID
        /// Plain text for ordinary records. Sensitive text is stored only in `encryptedContent`.
        var content: String
        var createdAt: Date
        var itemType: String
        /// Legacy inline image payload. New records use `payloadRelativePath`.
        var itemData: Data?
        var isPinned: Bool
        var isFavorite: Bool = false
        var isSensitive: Bool = false

        var sourceBundleIdentifier: String?
        var sourceAppName: String?
        var contentHash: String?
        /// JSON encoded `[String]`, used for multi-file clipboard records.
        var filePathsData: Data?
        var payloadRelativePath: String?
        var payloadByteCount: Int64 = 0
        var payloadTypeIdentifier: String?
        /// AES-GCM combined sealed box for sensitive UTF-8 text.
        var encryptedContent: Data?
        var encryptionVersion: Int = 0

        init(
            id: UUID = UUID(),
            content: String,
            createdAt: Date = Date(),
            itemType: String = ClipboardItemKind.text.rawValue,
            itemData: Data? = nil,
            isPinned: Bool = false,
            isFavorite: Bool = false,
            isSensitive: Bool = false,
            sourceBundleIdentifier: String? = nil,
            sourceAppName: String? = nil,
            contentHash: String? = nil,
            filePaths: [String] = [],
            payloadRelativePath: String? = nil,
            payloadByteCount: Int64 = 0,
            payloadTypeIdentifier: String? = nil,
            encryptedContent: Data? = nil,
            encryptionVersion: Int = 0
        ) {
            self.id = id
            self.content = content
            self.createdAt = createdAt
            self.itemType = itemType
            self.itemData = itemData
            self.isPinned = isPinned
            self.isFavorite = isFavorite
            self.isSensitive = isSensitive
            self.sourceBundleIdentifier = sourceBundleIdentifier
            self.sourceAppName = sourceAppName
            self.contentHash = contentHash
            self.filePathsData = filePaths.isEmpty ? nil : try? JSONEncoder().encode(filePaths)
            self.payloadRelativePath = payloadRelativePath
            self.payloadByteCount = payloadByteCount
            self.payloadTypeIdentifier = payloadTypeIdentifier
            self.encryptedContent = encryptedContent
            self.encryptionVersion = encryptionVersion
        }

        var kind: ClipboardItemKind {
            ClipboardItemKind(rawValue: itemType) ?? .text
        }

        var filePaths: [String] {
            guard let filePathsData else {
                return kind == .file && !content.isEmpty ? [content] : []
            }
            return (try? JSONDecoder().decode([String].self, from: filePathsData)) ?? []
        }

        func setFilePaths(_ paths: [String]) {
            filePathsData = paths.isEmpty ? nil : try? JSONEncoder().encode(paths)
            if let first = paths.first { content = first }
        }
    }
}

typealias ClipboardItem = ClipboardSchemaV2.ClipboardItem

enum ClipboardMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] { [ClipboardSchemaV1.self, ClipboardSchemaV2.self] }
    static var stages: [MigrationStage] {
        [.lightweight(fromVersion: ClipboardSchemaV1.self, toVersion: ClipboardSchemaV2.self)]
    }
}
