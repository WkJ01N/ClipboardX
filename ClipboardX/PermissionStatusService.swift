import AppKit
import ApplicationServices
import CoreGraphics

enum PermissionStatusService {
    /// Posting synthetic keyboard events is governed by Accessibility trust.
    /// `CGPreflightPostEventAccess()` can remain false for an Accessibility-trusted
    /// app on recent macOS releases, so it must not be combined with this check.
    static var canPostKeyboardEvents: Bool {
        canPostKeyboardEvents(accessibilityTrusted: AXIsProcessTrusted())
    }

    static func canPostKeyboardEvents(accessibilityTrusted: Bool) -> Bool {
        accessibilityTrusted
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
    private(set) var targetPID: pid_t?

    func captureFrontmostTarget() {
        let ownPID = ProcessInfo.processInfo.processIdentifier
        updateCapturedTarget(
            frontmostPID: NSWorkspace.shared.frontmostApplication?.processIdentifier,
            ownPID: ownPID
        )
    }

    func updateCapturedTarget(frontmostPID: pid_t?, ownPID: pid_t) {
        guard let frontmostPID, frontmostPID != ownPID else {
            targetPID = nil
            return
        }
        targetPID = frontmostPID
    }

    var canPasteAutomatically: Bool { PermissionStatusService.canPostKeyboardEvents }
    var hasCapturedTarget: Bool {
        guard let targetPID,
              let app = NSRunningApplication(processIdentifier: targetPID)
        else { return false }
        return !app.isTerminated
    }

    func pasteIntoCapturedTarget() async -> PasteAttemptResult {
        guard PermissionStatusService.canPostKeyboardEvents else { return .permissionDenied }
        guard let targetPID,
              let app = NSRunningApplication(processIdentifier: targetPID),
              !app.isTerminated
        else { return .targetUnavailable }

        guard app.activate(options: []) else { return .targetActivationFailed }
        for _ in 0..<20 {
            if NSWorkspace.shared.frontmostApplication?.processIdentifier == targetPID {
                return PasteSimulation.simulatePaste() ? .success : .eventCreationFailed
            }
            try? await Task.sleep(nanoseconds: 25_000_000)
        }
        return .targetActivationFailed
    }
}

enum PasteAttemptResult: Equatable {
    case success
    case permissionDenied
    case targetUnavailable
    case targetActivationFailed
    case eventCreationFailed
}
