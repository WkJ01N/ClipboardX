//
//  ClipboardItem.swift
//  ClipboardX
//
//  Created by Rain Walker on 2026/4/10.
//

import Foundation
import SwiftData

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
        id: UUID = UUID(),
        content: String,
        createdAt: Date = Date(),
        itemType: String = "text",
        itemData: Data? = nil,
        isPinned: Bool = false,
        isFavorite: Bool = false,
        isSensitive: Bool = false
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
