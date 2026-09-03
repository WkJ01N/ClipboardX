import AppKit
import ApplicationServices
import CoreGraphics

enum PermissionStatusService {
    static var canPostKeyboardEvents: Bool {
        canPostKeyboardEvents(accessibilityTrusted: AXIsProcessTrusted())
    }

    static func canPostKeyboardEvents(accessibilityTrusted: Bool) -> Bool { accessibilityTrusted }

    static var canListenToGlobalKeyboard: Bool { CGPreflightListenEventAccess() }

    @discardableResult
    static func requestAccessibility() -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    @discardableResult
    static func requestInputMonitoring() -> Bool { CGRequestListenEventAccess() }

    static func openPrivacySettings(anchor: String = "Privacy_Accessibility") {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)") else { return }
        NSWorkspace.shared.open(url)
    }
}

struct PasteTargetSession: Equatable, Sendable {
    let processIdentifier: pid_t
    let bundleIdentifier: String?
    let capturedAt: Date
    let generation: UInt
}

struct PasteApplicationState: Equatable, Sendable {
    let processIdentifier: pid_t
    let bundleIdentifier: String?
    let isTerminated: Bool
}

@MainActor
struct PasteCoordinatorDependencies {
    var accessibilityTrusted: () -> Bool
    var frontmostApplication: () -> PasteApplicationState?
    var applicationState: (pid_t) -> PasteApplicationState?
    var activate: (pid_t) -> Bool
    var postPaste: () -> Bool
    var sleep: (UInt64) async -> Void

    static let live = PasteCoordinatorDependencies(
        accessibilityTrusted: { AXIsProcessTrusted() },
        frontmostApplication: {
            guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
            return PasteApplicationState(
                processIdentifier: app.processIdentifier,
                bundleIdentifier: app.bundleIdentifier,
                isTerminated: app.isTerminated
            )
        },
        applicationState: { pid in
            guard let app = NSRunningApplication(processIdentifier: pid) else { return nil }
            return PasteApplicationState(
                processIdentifier: app.processIdentifier,
                bundleIdentifier: app.bundleIdentifier,
                isTerminated: app.isTerminated
            )
        },
        activate: { pid in
            guard let app = NSRunningApplication(processIdentifier: pid), !app.isTerminated else { return false }
            NSApp.yieldActivation(to: app)
            return app.activate(from: .current, options: [])
        },
        postPaste: { PasteSimulation.simulatePaste() },
        sleep: { nanoseconds in try? await Task.sleep(nanoseconds: nanoseconds) }
    )
}

@MainActor
final class PasteCoordinator {
    static let shared = PasteCoordinator()

    private let dependencies: PasteCoordinatorDependencies
    private let observesWorkspace: Bool
    private var activationObserver: NSObjectProtocol?
    private var terminationObserver: NSObjectProtocol?
    private var mostRecentExternalApplication: PasteApplicationState?
    private var selfActivatedAt: Date?
    private var generation: UInt = 0
    private(set) var targetSession: PasteTargetSession?

    var targetPID: pid_t? { targetSession?.processIdentifier }

    init(observeWorkspace: Bool = true, dependencies: PasteCoordinatorDependencies? = nil) {
        let resolvedDependencies = dependencies ?? .live
        self.dependencies = resolvedDependencies
        observesWorkspace = observeWorkspace
        if observeWorkspace {
            if let current = resolvedDependencies.frontmostApplication() {
                noteApplicationActivated(current, at: Date())
            }
            activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
                forName: NSWorkspace.didActivateApplicationNotification,
                object: nil,
                queue: .main
            ) { [weak self] notification in
                guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else {
                    return
                }
                Task { @MainActor [weak self] in
                    self?.noteApplicationActivated(
                        PasteApplicationState(
                            processIdentifier: app.processIdentifier,
                            bundleIdentifier: app.bundleIdentifier,
                            isTerminated: app.isTerminated
                        ),
                        at: Date()
                    )
                }
            }
            terminationObserver = NSWorkspace.shared.notificationCenter.addObserver(
                forName: NSWorkspace.didTerminateApplicationNotification,
                object: nil,
                queue: .main
            ) { [weak self] notification in
                guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else {
                    return
                }
                Task { @MainActor [weak self] in
                    self?.noteApplicationTerminated(processIdentifier: app.processIdentifier)
                }
            }
        }
    }

    deinit {
        if observesWorkspace, let activationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(activationObserver)
        }
        if observesWorkspace, let terminationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(terminationObserver)
        }
    }

    func noteApplicationActivated(_ application: PasteApplicationState, at date: Date) {
        let ownPID = ProcessInfo.processInfo.processIdentifier
        if application.processIdentifier == ownPID {
            selfActivatedAt = date
        } else if !application.isTerminated {
            mostRecentExternalApplication = application
        }
    }

    func noteApplicationTerminated(processIdentifier: pid_t) {
        if mostRecentExternalApplication?.processIdentifier == processIdentifier {
            mostRecentExternalApplication = nil
        }
        if targetSession?.processIdentifier == processIdentifier {
            invalidateSession()
        }
    }

    @discardableResult
    func captureFrontmostTarget(now: Date = Date()) -> PasteTargetSession? {
        beginSession(
            frontmostApplication: dependencies.frontmostApplication(),
            ownPID: ProcessInfo.processInfo.processIdentifier,
            now: now
        )
    }

    @discardableResult
    func beginSession(
        frontmostApplication: PasteApplicationState?,
        ownPID: pid_t,
        now: Date
    ) -> PasteTargetSession? {
        generation &+= 1
        let candidate: PasteApplicationState?
        if let frontmostApplication,
           frontmostApplication.processIdentifier != ownPID,
           !frontmostApplication.isTerminated {
            candidate = frontmostApplication
            mostRecentExternalApplication = frontmostApplication
        } else if frontmostApplication?.processIdentifier == ownPID,
                  let selfActivatedAt,
                  now.timeIntervalSince(selfActivatedAt) <= 1,
                  let recent = mostRecentExternalApplication,
                  !recent.isTerminated {
            candidate = recent
        } else {
            candidate = nil
        }

        guard let candidate else {
            targetSession = nil
            return nil
        }
        let session = PasteTargetSession(
            processIdentifier: candidate.processIdentifier,
            bundleIdentifier: candidate.bundleIdentifier,
            capturedAt: now,
            generation: generation
        )
        targetSession = session
        return session
    }

    func invalidateSession() {
        generation &+= 1
        targetSession = nil
    }

    var canPasteAutomatically: Bool { dependencies.accessibilityTrusted() }

    var hasCapturedTarget: Bool {
        guard let session = targetSession,
              let state = dependencies.applicationState(session.processIdentifier),
              !state.isTerminated,
              state.bundleIdentifier == session.bundleIdentifier
        else { return false }
        return true
    }

    func pasteIntoCapturedTarget() async -> PasteAttemptResult {
        guard dependencies.accessibilityTrusted() else { return .permissionDenied }
        guard let session = targetSession,
              let state = dependencies.applicationState(session.processIdentifier),
              !state.isTerminated,
              state.bundleIdentifier == session.bundleIdentifier
        else {
            invalidateSession()
            return .targetUnavailable
        }

        guard dependencies.activate(session.processIdentifier) else {
            invalidateSession()
            return .targetActivationFailed
        }
        for _ in 0..<40 {
            guard targetSession?.generation == session.generation else { return .targetUnavailable }
            if dependencies.frontmostApplication()?.processIdentifier == session.processIdentifier {
                let posted = dependencies.postPaste()
                invalidateSession()
                return posted ? .eventsPosted : .eventCreationFailed
            }
            await dependencies.sleep(25_000_000)
        }
        invalidateSession()
        return .targetActivationTimedOut
    }
}

enum PasteAttemptResult: Equatable {
    case eventsPosted
    case permissionDenied
    case targetUnavailable
    case targetActivationFailed
    case targetActivationTimedOut
    case eventCreationFailed
}
