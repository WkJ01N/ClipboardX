import Foundation

enum AppLanguage: String, CaseIterable, Identifiable {
    case system
    case zhHans = "zh-Hans"
    case english = "en"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .system:
            return "跟随系统 (System)"
        case .zhHans:
            return "简体中文"
        case .english:
            return "English"
        }
    }
}

enum LanguageManager {
    static func locale(for storedValue: String) -> Locale {
        let language = AppLanguage(rawValue: storedValue) ?? .system
        switch language {
        case .system:
            return .autoupdatingCurrent
        case .zhHans:
            return Locale(identifier: "zh-Hans")
        case .english:
            return Locale(identifier: "en")
        }
    }
}
