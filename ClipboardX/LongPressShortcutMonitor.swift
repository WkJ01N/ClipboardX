import AppKit
import Foundation

@MainActor
final class LongPressShortcutMonitor {
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var longPressTimer: DispatchSourceTimer?
    private var isPressingTargetKey = false
    private var didTriggerForCurrentPress = false
    private let onLongPressTriggered: () -> Void

    init(onLongPressTriggered: @escaping () -> Void) {
        self.onLongPressTriggered = onLongPressTriggered
        startMonitoring()
    }

    deinit {
        if let globalMonitor {
            NSEvent.removeMonitor(globalMonitor)
        }
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
        }
        longPressTimer?.cancel()
        longPressTimer = nil
    }

    func startMonitoring() {
        guard globalMonitor == nil, localMonitor == nil else { return }

        let mask: NSEvent.EventTypeMask = [.flagsChanged, .keyDown, .keyUp]
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

    func stopMonitoring() {
        if let globalMonitor {
            NSEvent.removeMonitor(globalMonitor)
            self.globalMonitor = nil
        }
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
            self.localMonitor = nil
        }
        cancelPressTracking()
    }

    private var isEnabled: Bool {
        UserDefaults.standard.bool(forKey: "enableLongPressShortcut")
    }

    private var keyKind: LongPressShortcutKeyKind {
        LongPressShortcutSupport.kind(from: UserDefaults.standard.string(forKey: "longPressKeyKind"))
    }

    private var keyCode: UInt16 {
        if UserDefaults.standard.object(forKey: "longPressKeyCode") == nil {
            return UInt16(LongPressShortcutSupport.defaultKeyCode)
        }
        return UInt16(UserDefaults.standard.integer(forKey: "longPressKeyCode"))
    }

    private var triggerDuration: TimeInterval {
        let defaults = UserDefaults.standard
        let raw = defaults.object(forKey: "longPressDuration") == nil
            ? 0.5
            : defaults.double(forKey: "longPressDuration")
        return max(0.3, min(2.0, raw))
    }

    private func handle(_ event: NSEvent) {
        guard isEnabled else {
            cancelPressTracking()
            return
        }

        switch keyKind {
        case .modifier:
            handleModifierEvent(event)
        case .regular:
            handleRegularKeyEvent(event)
        }
    }

    private func handleModifierEvent(_ event: NSEvent) {
        guard event.type == .flagsChanged else { return }
        let pressed = LongPressShortcutSupport.isModifierPressed(
            keyCode: keyCode,
            flags: event.modifierFlags
        )
        if pressed {
            beginPressTrackingIfNeeded()
        } else {
            cancelPressTracking()
        }
    }

    private func handleRegularKeyEvent(_ event: NSEvent) {
        switch event.type {
        case .keyDown:
            guard event.keyCode == keyCode, !event.isARepeat else { return }
            beginPressTrackingIfNeeded()
        case .keyUp:
            guard event.keyCode == keyCode else { return }
            cancelPressTracking()
        default:
            break
        }
    }

    private func beginPressTrackingIfNeeded() {
        guard !isPressingTargetKey else { return }
        isPressingTargetKey = true
        didTriggerForCurrentPress = false

        longPressTimer?.cancel()
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + triggerDuration)
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            guard self.isPressingTargetKey, !self.didTriggerForCurrentPress else { return }
            guard self.isEnabled else { return }
            self.didTriggerForCurrentPress = true
            self.onLongPressTriggered()
        }
        longPressTimer = timer
        timer.resume()
    }

    private func cancelPressTracking() {
        isPressingTargetKey = false
        didTriggerForCurrentPress = false
        longPressTimer?.cancel()
        longPressTimer = nil
    }
}
