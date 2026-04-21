import AppKit
import Foundation

enum DoubleClickModifierKey: String, CaseIterable, Identifiable {
    case option
    case command
    case control
    case shift

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .option:
            return "Option (⌥)"
        case .command:
            return "Command (⌘)"
        case .control:
            return "Control (⌃)"
        case .shift:
            return "Shift (⇧)"
        }
    }

    var flag: NSEvent.ModifierFlags {
        switch self {
        case .option: return .option
        case .command: return .command
        case .control: return .control
        case .shift: return .shift
        }
    }

    func matches(keyCode: UInt16) -> Bool {
        switch self {
        case .option:
            return keyCode == 58 || keyCode == 61
        case .command:
            return keyCode == 55 || keyCode == 54
        case .control:
            return keyCode == 59 || keyCode == 62
        case .shift:
            return keyCode == 56 || keyCode == 60
        }
    }
}

@MainActor
final class DoubleClickMonitor {
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var lastPressTime: TimeInterval?
    private var hasInterferingKeyDown = false
    private let onDoubleClickTriggered: () -> Void
    private let threshold: TimeInterval = 0.4

    init(onDoubleClickTriggered: @escaping () -> Void) {
        self.onDoubleClickTriggered = onDoubleClickTriggered
        startMonitoring()
    }

    deinit {
        if let globalMonitor {
            NSEvent.removeMonitor(globalMonitor)
        }
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
        }
    }

    private var isEnabled: Bool {
        UserDefaults.standard.bool(forKey: "enableDoubleClick")
    }

    private var targetModifier: DoubleClickModifierKey {
        let raw = UserDefaults.standard.string(forKey: "doubleClickKey") ?? DoubleClickModifierKey.option.rawValue
        return DoubleClickModifierKey(rawValue: raw) ?? .option
    }

    private func startMonitoring() {
        guard globalMonitor == nil, localMonitor == nil else { return }
        let mask: NSEvent.EventTypeMask = [.flagsChanged, .keyDown]
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] event in
            Task { @MainActor in
                self?.handle(event)
            }
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
            Task { @MainActor in
                self?.handle(event)
            }
            return event
        }
    }

    private func handle(_ event: NSEvent) {
        guard isEnabled else {
            resetState()
            return
        }

        if event.type == .keyDown {
            hasInterferingKeyDown = true
            return
        }

        guard event.type == .flagsChanged else { return }
        let modifier = targetModifier
        guard modifier.matches(keyCode: event.keyCode) else { return }

        let isPressed = event.modifierFlags.intersection(.deviceIndependentFlagsMask).contains(modifier.flag)
        guard isPressed else { return }

        let now = ProcessInfo.processInfo.systemUptime
        guard let lastPressTime, now - lastPressTime <= threshold else {
            self.lastPressTime = now
            hasInterferingKeyDown = false
            return
        }
        guard !hasInterferingKeyDown else {
            self.lastPressTime = now
            hasInterferingKeyDown = false
            return
        }

        onDoubleClickTriggered()
        resetState()
    }

    private func resetState() {
        lastPressTime = nil
        hasInterferingKeyDown = false
    }
}
