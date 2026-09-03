import Foundation

enum HistoryReorderAnimationPhase: Equatable {
    case idle
    case fadingOut(UUID)
    case reordering(UUID)
    case fadingIn(UUID)

    var hiddenItemID: UUID? {
        switch self {
        case .idle: nil
        case .fadingOut(let id), .reordering(let id), .fadingIn(let id): id
        }
    }
}

enum HistoryOrdering {
    static func isFirstInGroup<Item>(
        _ selected: Item,
        in items: [Item],
        id: (Item) -> UUID,
        isPinned: (Item) -> Bool
    ) -> Bool {
        items.first(where: { isPinned($0) == isPinned(selected) }).map(id) == id(selected)
    }
}
