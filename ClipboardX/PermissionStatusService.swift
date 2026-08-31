import AppKit
import ApplicationServices
import CoreGraphics

enum PermissionStatusService {
    static var canPostKeyboardEvents: Bool {
        AXIsProcessTrusted() && CGPreflightPostEventAccess()
    }

    static var canListenToGlobalKeyboard: Bool {
        CGPreflightListenEventAccess()
    }

    @discardableResult
    static func requestAccessibility() -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    @discardableResult
    static func requestInputMonitoring() -> Bool {
        CGRequestListenEventAccess()
    }

    static func openPrivacySettings(anchor: String = "Privacy_Accessibility") {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)") else { return }
        NSWorkspace.shared.open(url)
    }
}

@MainActor
final class PasteCoordinator {
    static let shared = PasteCoordinator()
    private var targetPID: pid_t?

    func captureFrontmostTarget() {
        let ownPID = ProcessInfo.processInfo.processIdentifier
        guard let app = NSWorkspace.shared.frontmostApplication,
              app.processIdentifier != ownPID
        else { return }
        targetPID = app.processIdentifier
    }

    var canPasteAutomatically: Bool { PermissionStatusService.canPostKeyboardEvents }

    func pasteIntoCapturedTarget() {
        if let targetPID, let app = NSRunningApplication(processIdentifier: targetPID) {
            app.activate(options: [])
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
            _ = PasteSimulation.simulatePaste()
        }
    }
}
