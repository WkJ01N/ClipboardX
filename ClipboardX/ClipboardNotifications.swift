//
//  ClipboardNotifications.swift
//  ClipboardX
//
//  Created by Rain Walker on 2026/4/11.
//

import Foundation

extension Notification.Name {
    /// 请求立即隐藏剪贴板历史悬浮窗（例如在面板内选中条目以粘贴前，先把焦点交回前台应用）。
    static let hidePanelNotification = Notification.Name("com.clipboardx.hidePanel")

    /// 悬浮窗每次置于前台时请求将焦点放到搜索框。
    static let focusClipboardSearchNotification = Notification.Name("com.clipboardx.focusClipboardSearch")
}
