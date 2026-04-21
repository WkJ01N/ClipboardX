import AppKit
import Foundation

enum LongPressShortcutKeyKind: String {
    case modifier
    case regular
}

enum LongPressShortcutSupport {
    static let defaultKeyCode: Int = 58
    static let defaultKind: LongPressShortcutKeyKind = .modifier
    static let defaultDisplayName = "⌥ Option"

    static func kind(from raw: String?) -> LongPressShortcutKeyKind {
        guard let raw, let kind = LongPressShortcutKeyKind(rawValue: raw) else {
            return defaultKind
        }
        return kind
    }

    static func displayName(kind: LongPressShortcutKeyKind, keyCode: Int) -> String {
        switch kind {
        case .modifier:
            return modifierDisplayName(for: UInt16(keyCode))
        case .regular:
            return "KeyCode \(keyCode)"
        }
    }

    static func modifierDisplayName(for keyCode: UInt16) -> String {
        switch keyCode {
        case 55, 54: "⌘ Command"
        case 58, 61: "⌥ Option"
        case 59, 62: "⌃ Control"
        case 56, 60: "⇧ Shift"
        case 57: "⇪ Caps Lock"
        default: "Modifier \(keyCode)"
        }
    }

    static func modifierFlag(for keyCode: UInt16) -> NSEvent.ModifierFlags? {
        switch keyCode {
        case 55, 54: return .command
        case 58, 61: return .option
        case 59, 62: return .control
        case 56, 60: return .shift
        case 57: return .capsLock
        default: return nil
        }
    }

    static func isModifierPressed(keyCode: UInt16, flags: NSEvent.ModifierFlags) -> Bool {
        guard let targetFlag = modifierFlag(for: keyCode) else { return false }
        return flags.intersection(.deviceIndependentFlagsMask).contains(targetFlag)
    }

    static func displayName(from keyEvent: NSEvent) -> String {
        guard let raw = keyEvent.charactersIgnoringModifiers?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty
        else {
            return "KeyCode \(keyEvent.keyCode)"
        }

        if raw == " " {
            return "Space"
        }
        return raw.uppercased()
    }
}
