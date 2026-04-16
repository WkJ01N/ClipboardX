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
    @AppStorage("windowFadeAnimationEnabled") private var windowFadeAnimationEnabled = true
    @AppStorage("windowAnimationDurationMs") private var windowAnimationDurationMs = 220

    /// 主悬浮窗口实例（边框隐藏、高层级、支持全屏辅助显示）。
    private let panel: NSPanel
    /// 监听其他应用/桌面的鼠标点击，用于点击外部自动收起。
    private var outsideClickGlobalMonitor: Any?
    /// 监听本应用内鼠标点击，用于菜单栏等区域点击时收起。
    private var outsideClickLocalMonitor: Any?
    /// 响应统一的隐藏通知，支持跨组件关闭面板。
    private var hidePanelNotificationObserver: NSObjectProtocol?
    /// 用于避免 show/hide 快速切换时旧动画 completion 污染新状态。
    private var animationGeneration: UInt = 0

    /// 悬浮面板内容区固定尺寸，与历史列表布局一致。
    private static let contentSize = NSSize(width: 320, height: 450)

    private var normalizedWindowAnimationDuration: TimeInterval {
        Double(max(100, min(600, windowAnimationDurationMs))) / 1000.0
    }

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
        let targetOrigin = resolvedPanelOrigin()
        stopOutsideClickMonitoring()
        beginOutsideClickMonitoring()

        animationGeneration &+= 1
        let generation = animationGeneration
        let shouldAnimate = windowFadeAnimationEnabled
        let duration = normalizedWindowAnimationDuration
        panel.alphaValue = shouldAnimate ? 0 : 1
        panel.setFrameOrigin(targetOrigin)

        NSRunningApplication.current.activate(options: [])
        panel.orderFrontRegardless()
        panel.makeMain()
        panel.makeKeyAndOrderFront(nil)

        if shouldAnimate {
            Task { @MainActor [weak self] in
                guard let self, self.animationGeneration == generation, self.panel.isVisible else { return }
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = duration
                    self.panel.animator().alphaValue = 1.0
                }
            }
        }

        // 等窗口进入 key 状态后再广播焦点请求，提升上下键接管成功率。
        DispatchQueue.main.asyncAfter(deadline: .now() + (shouldAnimate ? 0.05 : 0)) {
            NotificationCenter.default.post(name: .focusClipboardSearchNotification, object: nil)
        }
    }

    /// 隐藏面板并移除外部点击监测，防止监听器泄漏。
    func hidePanel() {
        stopOutsideClickMonitoring()
        animationGeneration &+= 1
        let generation = animationGeneration
        let shouldAnimate = windowFadeAnimationEnabled
        let duration = normalizedWindowAnimationDuration
        guard shouldAnimate else {
            panel.orderOut(nil)
            panel.alphaValue = 1
            return
        }

        NSAnimationContext.runAnimationGroup { context in
            context.duration = duration
            panel.animator().alphaValue = 0
        } completionHandler: { [weak self] in
            guard let self else { return }
            Task { @MainActor [self] in
                guard self.animationGeneration == generation else { return }
                self.panel.orderOut(nil)
                self.panel.alphaValue = 1
            }
        }
    }

    /// 在显示与隐藏状态间切换面板可见性。
    func togglePanel() {
        if panel.isVisible {
            hidePanel()
        } else {
            showPanel()
        }
    }

    /// 计算面板目标位置：优先输入光标处（需用户开启），否则鼠标位置。
    private func resolvedPanelOrigin() -> NSPoint {
        let size = panel.frame.size
        let popupAtCaret = UserDefaults.standard.bool(forKey: "popupAtCaret")

        // 尝试从 Accessibility API 获取输入光标的屏幕坐标
        var anchor: NSPoint?
        if popupAtCaret {
            anchor = Self.caretScreenPoint()
        }

        let ref = anchor ?? NSEvent.mouseLocation
        var origin = NSPoint(x: ref.x, y: ref.y - size.height)
        origin = Self.clampOrigin(origin, size: size, to: ref)
        return origin
    }

    /// 通过 macOS Accessibility API 获取当前聚焦输入框的光标屏幕坐标。
    ///
    /// 返回值使用 AppKit 屏幕坐标系（原点在左下角）。
    /// 若无障碍权限未授予、前台应用不支持或无文本光标，返回 `nil`。
    private static func caretScreenPoint() -> NSPoint? {
        guard AXIsProcessTrusted() else { return nil }

        let systemWide = AXUIElementCreateSystemWide()

        var focusedElement: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            systemWide,
            kAXFocusedUIElementAttribute as CFString,
            &focusedElement
        ) == .success else {
            return nil
        }
        guard let focusedElement,
              CFGetTypeID(focusedElement) == AXUIElementGetTypeID()
        else {
            return nil
        }
        let element = unsafeBitCast(focusedElement, to: AXUIElement.self)

        // 先读取选中范围，光标状态通常为 length == 0。
        var insertionPointValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element,
            kAXSelectedTextRangeAttribute as CFString,
            &insertionPointValue
        ) == .success else {
            return nil
        }

        guard let insertionPointValue,
              CFGetTypeID(insertionPointValue) == AXValueGetTypeID()
        else {
            return nil
        }
        let insertionAXValue = unsafeBitCast(insertionPointValue, to: AXValue.self)
        guard AXValueGetType(insertionAXValue) == .cfRange else {
            return nil
        }

        var selectedRange = CFRange(location: 0, length: 0)
        guard AXValueGetValue(
            insertionAXValue,
            .cfRange,
            &selectedRange
        ) else {
            return nil
        }

        // 先用 insertion point（length=0）取光标矩形，失败再尝试当前选区矩形。
        var queryRanges = [CFRange(location: selectedRange.location, length: 0)]
        if selectedRange.length > 0 {
            queryRanges.append(selectedRange)
        }

        var caretRect: CGRect?
        for range in queryRanges {
            var mutableRange = range
            guard let rangeValue = AXValueCreate(.cfRange, &mutableRange) else { continue }
            var boundsValue: CFTypeRef?
            let status = AXUIElementCopyParameterizedAttributeValue(
                element,
                kAXBoundsForRangeParameterizedAttribute as CFString,
                rangeValue,
                &boundsValue
            )
            guard status == .success,
                  let boundsValue,
                  CFGetTypeID(boundsValue) == AXValueGetTypeID()
            else {
                continue
            }

            let boundsAXValue = unsafeBitCast(boundsValue, to: AXValue.self)
            guard AXValueGetType(boundsAXValue) == .cgRect else {
                continue
            }

            var rect = CGRect.zero
            if AXValueGetValue(boundsAXValue, .cgRect, &rect), !rect.isNull, !rect.isEmpty {
                caretRect = rect
                break
            }
        }

        // 对不支持 boundsForRange 的应用，退化到“聚焦输入控件左上角”定位。
        let targetRect: CGRect
        if let caretRect {
            targetRect = caretRect
        } else if let focusedFrame = focusedElementFrame(element) {
            targetRect = focusedFrame
        } else {
            return nil
        }

        return appKitPoint(fromAXRect: targetRect)
    }

    /// 获取聚焦元素的外框（用于不支持 caret bounds 的应用降级）。
    private static func focusedElementFrame(_ element: AXUIElement) -> CGRect? {
        var positionValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element,
            kAXPositionAttribute as CFString,
            &positionValue
        ) == .success,
        let positionValue,
        CFGetTypeID(positionValue) == AXValueGetTypeID()
        else {
            return nil
        }

        let positionAXValue = unsafeBitCast(positionValue, to: AXValue.self)
        guard AXValueGetType(positionAXValue) == .cgPoint else {
            return nil
        }

        var sizeValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element,
            kAXSizeAttribute as CFString,
            &sizeValue
        ) == .success,
        let sizeValue,
        CFGetTypeID(sizeValue) == AXValueGetTypeID()
        else {
            return nil
        }

        let sizeAXValue = unsafeBitCast(sizeValue, to: AXValue.self)
        guard AXValueGetType(sizeAXValue) == .cgSize else {
            return nil
        }

        var position = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(positionAXValue, .cgPoint, &position),
              AXValueGetValue(sizeAXValue, .cgSize, &size),
              size.width > 0,
              size.height > 0
        else {
            return nil
        }

        let frame = CGRect(origin: position, size: size)
        return frame
    }

    /// 将 AX 全局坐标（左上原点）转换为 AppKit 屏幕坐标（左下原点）。
    private static func appKitPoint(fromAXRect rect: CGRect) -> NSPoint? {
        guard let desktopTopY = NSScreen.screens.map(\.frame.maxY).max() else {
            return nil
        }
        let appKitY = desktopTopY - rect.origin.y - rect.size.height
        return NSPoint(x: rect.origin.x, y: appKitY)
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
