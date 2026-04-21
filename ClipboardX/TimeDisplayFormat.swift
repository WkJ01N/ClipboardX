import Foundation
import SwiftUI

enum TimeDisplayFormat: String, CaseIterable, Identifiable {
    case relative
    case absolute24
    case absolute12

    var id: String { rawValue }

    var localizedName: LocalizedStringResource {
        switch self {
        case .relative:
            "相对时间"
        case .absolute24:
            "24小时制"
        case .absolute12:
            "12小时制"
        }
    }
}
