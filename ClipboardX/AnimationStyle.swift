import Foundation
import SwiftUI

enum AnimationStyle: String, CaseIterable, Identifiable {
    case float = "浮动飞升"
    case fade = "闪现淡入"
    case none = "无动画"

    var id: String { self.rawValue }

    var localizedName: LocalizedStringResource {
        switch self {
        case .float:
            "浮动飞升"
        case .fade:
            "闪现淡入"
        case .none:
            "无动画"
        }
    }
}
