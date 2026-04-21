//
//  KeyboardShortcuts+Clipboard.swift
//  ClipboardX
//
//  Created by Rain Walker on 2026/4/10.
//

import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    /// 显示 / 隐藏剪贴板历史悬浮窗。默认快捷键在 `ClipboardXApp.init` 中设为 ⌥V（若用户尚未自定义）。
    static let toggleClipboard = Self("toggleClipboard")
    /// 暂停 / 恢复剪贴板监听。
    static let togglePause = Self("togglePause")
    /// 唤出“打字机模式”专用面板。
    static let showTypewriterPanel = Self("showTypewriterPanel")
}
