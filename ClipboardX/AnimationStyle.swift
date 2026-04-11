import Foundation

enum AnimationStyle: String, CaseIterable, Identifiable {
    case float = "浮动飞升"
    case fade = "闪现淡入"
    case none = "无动画"

    var id: String { self.rawValue }
}
