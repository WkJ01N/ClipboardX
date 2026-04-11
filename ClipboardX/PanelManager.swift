//
//  PanelManager.swift
//  ClipboardX
//
//  Created by Rain Walker on 2026/4/10.
//

import AppKit
import KeyboardShortcuts
import SwiftData
import SwiftUI

/// 承载 `HistoryListView` 的无边框悬浮 `NSPanel`，由全局快捷键或菜单触发显示。
///
/// 该管理器集中处理窗口层级、跨桌面行为、显示定位、外部点击收起与快捷键触发，
/// 将“面板生命周期”从 SwiftUI 视图层中剥离，避免界面逻辑与窗口控制逻辑耦合。
@MainActor
final class PanelManager {
    /// 主悬浮窗口实例（边框隐藏、高层级、支持全屏辅助显示）。
    private let panel: NSPanel
    /// 监听其他应用/桌面的鼠标点击，用于点击外部自动收起。
    private var outsideClickGlobalMonitor: Any?
    /// 监听本应用内鼠标点击，用于菜单栏等区域点击时收起。
    private var outsideClickLocalMonitor: Any?
    /// 响应统一的隐藏通知，支持跨组件关闭面板。
    private var hidePanelNotificationObserver: NSObjectProtocol?

    /// 悬浮面板内容区固定尺寸，与历史列表布局一致。
    private static let contentSize = NSSize(width: 320, height: 450)

    /// 初始化面板管理器并绑定全局快捷键、通知监听与内容控制器。
    init(modelContainer: ModelContainer) {
        let panel = ClipboardPanel(
            contentRect: NSRect(origin: .zero, size: Self.contentSize),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .popUpMenu
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.hidesOnDeactivate = false
        panel.hasShadow = true
        panel.isMovableByWindowBackground = false

        let rootView = HistoryListView(isFromPanel: true)
            .modelContainer(modelContainer)
            .background(Color(nsColor: .windowBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

        let hosting = NSHostingController(rootView: rootView)
        hosting.view.frame = NSRect(origin: .zero, size: Self.contentSize)
        hosting.view.wantsLayer = true
        panel.contentViewController = hosting
        panel.setContentSize(Self.contentSize)

        self.panel = panel

        KeyboardShortcuts.onKeyDown(for: .toggleClipboard) { [weak self] in
            self?.togglePanel()
        }

        hidePanelNotificationObserver = NotificationCenter.default.addObserver(
            forName: .hidePanelNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.hidePanel()
            }
        }
    }

    deinit {
        if let hidePanelNotificationObserver {
            NotificationCenter.default.removeObserver(hidePanelNotificationObserver)
        }
    }

    /// 显示面板并将其定位到鼠标附近，同时建立外部点击监测。
    func showPanel() {
        positionPanelTopLeftAtMouse()
        stopOutsideClickMonitoring()
        beginOutsideClickMonitoring()
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        NotificationCenter.default.post(name: .focusClipboardSearchNotification, object: nil)
    }

    /// 隐藏面板并移除外部点击监测，防止监听器泄漏。
    func hidePanel() {
        stopOutsideClickMonitoring()
        panel.orderOut(nil)
    }

    /// 在显示与隐藏状态间切换面板可见性。
    func togglePanel() {
        if panel.isVisible {
            hidePanel()
        } else {
            showPanel()
        }
    }

    /// 将面板左上角对齐到鼠标位置，并限制在当前屏幕可视区域内。
    private func positionPanelTopLeftAtMouse() {
        let size = panel.frame.size
        let mouse = NSEvent.mouseLocation
        // 鼠标位置视为面板左上角（屏幕坐标系为左下角为原点，故 origin.y = mouse.y - height）
        var origin = NSPoint(x: mouse.x, y: mouse.y - size.height)
        origin = Self.clampOrigin(origin, size: size, to: mouse)
        panel.setFrameOrigin(origin)
    }

    /// 将窗口限制在包含光标的屏幕可见区域内，避免大部分区域在屏外。
    private static func clampOrigin(_ origin: NSPoint, size: NSSize, to mouse: NSPoint) -> NSPoint {
        guard let screen = NSScreen.screens.first(where: { NSMouseInRect(mouse, $0.frame, false) }) ?? NSScreen.main
        else {
            return origin
        }
        let vf = screen.visibleFrame
        var x = origin.x
        var y = origin.y
        if x + size.width > vf.maxX { x = vf.maxX - size.width }
        if x < vf.minX { x = vf.minX }
        if y < vf.minY { y = vf.minY }
        if y + size.height > vf.maxY { y = vf.maxY - size.height }
        return NSPoint(x: x, y: y)
    }

    /// 开启“点击窗口外即收起”的双通道监听（全局 + 本地）。
    private func beginOutsideClickMonitoring() {
        stopOutsideClickMonitoring()
        // 其它应用 / 桌面：全局监视器（不会收到发往本进程的鼠标事件）
        outsideClickGlobalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            Task { @MainActor in
                self?.hideIfClickOutsidePanel()
            }
        }
        // 本应用内、但不在面板上的点击（例如菜单栏菜单）
        outsideClickLocalMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            Task { @MainActor in
                self?.handleLocalMouseDown(event)
            }
            return event
        }
    }

    /// 停止并清理所有外部点击监听句柄。
    private func stopOutsideClickMonitoring() {
        if let outsideClickGlobalMonitor {
            NSEvent.removeMonitor(outsideClickGlobalMonitor)
            self.outsideClickGlobalMonitor = nil
        }
        if let outsideClickLocalMonitor {
            NSEvent.removeMonitor(outsideClickLocalMonitor)
            self.outsideClickLocalMonitor = nil
        }
    }

    /// 当鼠标点击不在面板范围内时，立即收起面板。
    private func hideIfClickOutsidePanel() {
        guard panel.isVisible else { return }
        let mouse = NSEvent.mouseLocation
        if !panel.frame.contains(mouse) {
            hidePanel()
        }
    }

    /// 处理本应用内鼠标事件，避免点在面板内部时误触发关闭。
    private func handleLocalMouseDown(_ event: NSEvent) {
        guard panel.isVisible else { return }
        if event.window === panel { return }
        hideIfClickOutsidePanel()
    }
}

/// 允许无边框面板参与键盘焦点路由。
///
/// 默认 `NSPanel`（尤其无边框样式）在某些场景下不会成为 key/main window，
/// 会导致 SwiftUI 键盘事件（方向键、空格、回车）无法稳定到达视图层。
final class ClipboardPanel: NSPanel {
    /// 允许成为 key window，确保键盘事件分发到内容视图。
    override var canBecomeKey: Bool { true }
    /// 允许成为 main window，避免焦点链路被系统回退。
    override var canBecomeMain: Bool { true }
}
