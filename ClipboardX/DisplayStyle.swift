import Foundation

enum DisplayStyle: String, CaseIterable, Identifiable {
    case list
    case grid

    var id: String { rawValue }
}
