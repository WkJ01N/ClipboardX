//
//  PasteSimulation.swift
//  ClipboardX
//
//  Created by Rain Walker on 2026/4/11.
//

import CoreGraphics

/// 通过 CGEvent 模拟 ⌘V，将当前剪贴板内容粘贴到前台应用（需辅助功能权限才能可靠投递）。
enum PasteSimulation {
    /// `v` 的虚拟键码为 `kVK_ANSI_V` (0x09)。
    private static let ansiVKeyCode: CGKeyCode = 0x09

    /// 模拟一次完整的 `⌘V` 按下/抬起序列。
    ///
    /// 之所以使用 `cghidEventTap` 发送低层事件，是为了在面板窗口收起后，
    /// 将粘贴行为准确投递给先前的前台应用，而不是当前菜单栏进程自身。
    static func simulatePaste() {
        let source = CGEventSource(stateID: .hidSystemState)
        let flags = CGEventFlags.maskCommand

        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: ansiVKeyCode, keyDown: true) else { return }
        keyDown.flags = flags
        keyDown.post(tap: CGEventTapLocation.cghidEventTap)

        guard let keyUp = CGEvent(keyboardEventSource: source, virtualKey: ansiVKeyCode, keyDown: false) else { return }
        keyUp.flags = flags
        keyUp.post(tap: CGEventTapLocation.cghidEventTap)
    }
}
