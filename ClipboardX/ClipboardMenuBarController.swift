import AppKit
import Combine
import SwiftUI

/// Owns an explicitly named status item instead of SwiftUI's automatically named Item-0.
/// A stable, app-specific identity avoids reusing Control Center's stale associations
/// with other applications while keeping the existing preference domain and data.
@MainActor
final class ClipboardMenuBarController: NSObject, NSPopoverDelegate {
    nonisolated static let autosaveName = "com.wkj01n.ClipboardX.menuBar"

    private let defaults: UserDefaults
    private let itemAutosaveName: String
    private let makeContent: () -> AnyView
    private let popover = NSPopover()
    private var subscriptions = Set<AnyCancellable>()
    private var requestedVisibility: Bool?
    private var iconName: String?
    private(set) var statusItem: NSStatusItem?

    init(
        defaults: UserDefaults = .standard,
        autosaveName: String = ClipboardMenuBarController.autosaveName,
        makeContent: @escaping () -> AnyView
    ) {
        self.defaults = defaults
        self.itemAutosaveName = autosaveName
        self.makeContent = makeContent
        super.init()
        popover.behavior = .transient
        popover.delegate = self
        // Avoid a delayed close callback removing a newly reopened view hierarchy.
        popover.animates = false
    }

    func start() {
        guard statusItem == nil else { return }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.autosaveName = itemAutosaveName
        item.behavior = .removalAllowed
        item.button?.setAccessibilityIdentifier(Self.autosaveName)
        item.button?.setAccessibilityLabel("ClipboardX")
        item.button?.toolTip = "ClipboardX"
        item.button?.target = self
        item.button?.action = #selector(togglePopover(_:))
        statusItem = item
        refreshPreferences()

        NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification, object: defaults)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.refreshPreferences() }
            .store(in: &subscriptions)
        NotificationCenter.default.publisher(for: .hidePanelNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.closePopover() }
            .store(in: &subscriptions)
    }

    func refreshPreferences() {
        guard let statusItem else { return }
        let visible = defaults.object(forKey: "showMenuBarIcon") as? Bool ?? true
        if requestedVisibility != visible {
            requestedVisibility = visible
            if !visible { closePopover() }
            statusItem.isVisible = visible
        }
        let name = defaults.string(forKey: "menuBarIconName") ?? "scissors"
        if iconName != name {
            iconName = name
            let image = NSImage(systemSymbolName: name, accessibilityDescription: "ClipboardX")
                ?? NSImage(systemSymbolName: "scissors", accessibilityDescription: "ClipboardX")
            image?.isTemplate = true
            statusItem.button?.image = image
        }
    }

    func stop() {
        closePopover()
        subscriptions.removeAll()
        if let statusItem { NSStatusBar.system.removeStatusItem(statusItem) }
        statusItem = nil
        requestedVisibility = nil
        iconName = nil
    }

    @objc private func togglePopover(_ sender: NSStatusBarButton) {
        if popover.isShown {
            closePopover()
        } else {
            let hosting = NSHostingController(rootView: makeContent())
            hosting.sizingOptions = .preferredContentSize
            popover.contentViewController = hosting
            NSApp.activate(ignoringOtherApps: true)
            popover.show(relativeTo: sender.bounds, of: sender, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    private func closePopover() {
        popover.performClose(nil)
    }

    func popoverDidClose(_ notification: Notification) {
        // Discard list state and its event monitors when the menu is no longer visible.
        popover.contentViewController = nil
    }
}

struct ClipboardMenuBarContent: View {
    @AppStorage("appLanguage") private var appLanguage = AppLanguage.system.rawValue
    @AppStorage("isMonitoringPaused") private var isMonitoringPaused = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HistoryListView(isFromPanel: false)
            Divider()
            HStack {
                SettingsLink {
                    Text("偏好设置...")
                }
                .keyboardShortcut(",", modifiers: .command)
                .simultaneousGesture(TapGesture().onEnded {
                    NSApp.activate(ignoringOtherApps: true)
                })
                Spacer()
                Button {
                    isMonitoringPaused.toggle()
                } label: {
                    if isMonitoringPaused {
                        HStack(spacing: 4) {
                            Text("已暂停监听")
                            Image(systemName: "play.circle")
                        }
                    } else {
                        Image(systemName: "pause.circle")
                    }
                }
                .buttonStyle(.plain)
                Spacer()
                Button("退出应用") { NSApp.terminate(nil) }
            }
            .padding(10)
        }
        .environment(\.locale, LanguageManager.locale(for: appLanguage))
    }
}
