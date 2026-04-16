//
//  HistoryListView.swift
//  ClipboardX
//
//  Created by Rain Walker on 2026/4/10.
//

import AppKit
import SwiftData
import SwiftUI

/// 剪贴板历史主列表视图。
///
/// 负责组合搜索、排序、键盘导览、快速预览、快捷激活、置顶动画与批量清理等交互。
/// 该视图聚焦“列表级编排”，而单条卡片与预览弹层分别拆分到独立文件，降低耦合度。
struct HistoryListView: View {
    var isFromPanel: Bool = false
    /// 快捷键面板与菜单栏弹窗的列表顶部留白分离配置，便于分别微调。
    private let panelListTopPadding: CGFloat = 6
    private let menuPopupListTopPadding: CGFloat = 3
    /// 顶部栏弹窗中搜索栏距离顶部的留白，便于单独微调。
    private let menuPopupSearchTopPadding: CGFloat = 10

    /// SwiftData 上下文，用于更新排序时间、删除记录与写回状态。
    @Environment(\.modelContext) private var modelContext
    @Environment(\.openSettings) private var openSettings
    @Query(sort: \ClipboardItem.createdAt, order: .reverse) private var items: [ClipboardItem]
    /// 列表重排时的共享几何命名空间，用于平滑置顶动画。
    @Namespace private var animationNamespace

    /// 搜索关键词（本地过滤）。
    @State private var searchText = ""
    /// 搜索框焦点状态。
    @FocusState private var isSearchFocused: Bool
    /// 列表容器焦点状态（用于键盘事件接收）。
    @FocusState private var isListFocused: Bool
    /// 当前选中记录 ID（键盘导览/回车激活依赖）。
    @State private var selectedItemID: UUID?
    /// 是否处于“键盘导览模式”（影响高亮样式）。
    @State private var isKeyboardMode = false
    /// 列表滚动代理，用于将选中项滚动到可见区域。
    @State private var listScrollProxy: ScrollViewProxy?
    /// 当前执行淡出过渡的记录 ID（fade 置顶样式）。
    @State private var fadingItemID: UUID?
    /// 清空全部的行内确认态。
    @State private var showClearConfirmation = false
    /// 本地键盘监听句柄（用于 Cmd+数字直达）。
    @State private var keyDownMonitor: Any?
    /// Quick Look 预览中的记录 ID；`nil` 表示未展示预览层。
    @State private var quickLookItemID: UUID?

    /// 是否在复用记录后将其置顶。
    @AppStorage("bringToTopOnUse") private var bringToTopOnUse = true
    /// 清空前是否要求二次确认。
    @AppStorage("confirmBeforeClear") private var confirmBeforeClear = true
    /// 置顶动画风格（float/fade/none）。
    @AppStorage("animationStyle") private var animationStyle: AnimationStyle = .float
    /// fade 动画时长（秒）。
    @AppStorage("fadeAnimationDuration") private var fadeAnimationDuration = 0.12
    /// float 弹簧 response 参数（值越小越快）。
    @AppStorage("floatAnimationResponse") private var floatAnimationResponse = 0.40
    /// 空格键行为：预览或直接粘贴。
    @AppStorage("spaceKeyQuickLookEnabled") private var spaceKeyQuickLookEnabled = true

    /// 基于搜索词并结合固定优先规则生成最终展示数据。
    ///
    /// 说明：当前在视图层二次排序（固定项优先 + 时间倒序），
    /// 是为了兼容当前工具链下 `@Query` 对 `Bool` 多字段排序的限制。
    private var filteredItems: [ClipboardItem] {
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let base = trimmed.isEmpty
            ? items
            : items.filter { $0.content.localizedCaseInsensitiveContains(trimmed) }
        return base.sorted {
            if $0.isPinned != $1.isPinned {
                return $0.isPinned && !$1.isPinned
            }
            return $0.createdAt > $1.createdAt
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            if !isFromPanel {
                searchField
            }

            if items.isEmpty {
                emptyStateNoHistory
            } else if filteredItems.isEmpty {
                emptyStateNoMatches
            } else {
                listSection
            }

            Divider()

            toolbar
        }
        .frame(width: 320, height: 450)
        .focusable()
        .focused($isListFocused)
        .focusRingType(.none)
        .onKeyPress(.upArrow, phases: .down) { _ in moveSelection(up: true) }
        .onKeyPress(.downArrow, phases: .down) { _ in moveSelection(up: false) }
        .onKeyPress(.space, phases: .down) { _ in
            if spaceKeyQuickLookEnabled {
                if quickLookItemID != nil {
                    quickLookItemID = nil
                    return .handled
                } else if isKeyboardMode, let selected = selectedItemID {
                    quickLookItemID = selected
                    return .handled
                }
                return .ignored
            }

            if quickLookItemID != nil {
                quickLookItemID = nil
                return .handled
            }
            guard isKeyboardMode,
                  let selected = selectedItemID,
                  let item = filteredItems.first(where: { $0.id == selected })
            else {
                return .ignored
            }
            activateItem(item)
            return .handled
        }
        .onKeyPress(.escape, phases: .down) { _ in handleEscapeKey() }
        .onKeyPress(.return, phases: .down) { _ in handleReturnKey() }
        .onAppear {
            if isFromPanel {
                isListFocused = true
            } else {
                isSearchFocused = true
            }

            if let keyDownMonitor {
                NSEvent.removeMonitor(keyDownMonitor)
                self.keyDownMonitor = nil
            }
            keyDownMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                if event.modifierFlags.contains(.command),
                   let chars = event.charactersIgnoringModifiers,
                   let digit = Int(chars),
                   digit >= 1 && digit <= 9 {
                    activateItem(at: digit - 1)
                    return nil
                }
                return event
            }
        }
        .onDisappear {
            if let keyDownMonitor {
                NSEvent.removeMonitor(keyDownMonitor)
                self.keyDownMonitor = nil
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .focusClipboardSearchNotification)) { _ in
            if isFromPanel {
                isListFocused = true
            } else {
                isSearchFocused = true
            }
        }
        .overlay {
            if let qlID = quickLookItemID,
               let item = filteredItems.first(where: { $0.id == qlID }) {
                QuickLookPreview(item: item, onClose: {
                    quickLookItemID = nil
                })
                .transition(.opacity.combined(with: .scale(scale: 0.95)))
                .zIndex(100)
            }
        }
        .animation(.spring(response: 0.25, dampingFraction: 0.8), value: quickLookItemID)
    }

    /// 顶部搜索输入区，支持键盘方向键与回车/ESC 透传到列表逻辑。
    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("搜索剪贴板历史", text: $searchText)
                .textFieldStyle(.plain)
                .focused($isSearchFocused)
                .onKeyPress(.escape, phases: .down) { _ in handleEscapeKey() }
                .onKeyPress(.return, phases: .down) { _ in handleReturnKey() }
                .onKeyPress(.upArrow, phases: .down) { _ in moveSelection(up: true) }
                .onKeyPress(.downArrow, phases: .down) { _ in moveSelection(up: false) }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color.primary.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .padding(.horizontal, 10)
        .padding(.top, menuPopupSearchTopPadding)
        .padding(.bottom, 6)
    }

    /// 历史为空时的占位视图。
    private var emptyStateNoHistory: some View {
        VStack(spacing: 10) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 30))
            Text("暂无剪贴板历史")
                .font(.callout)
        }
        .foregroundColor(.secondary)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// 搜索无结果时的占位视图。
    private var emptyStateNoMatches: some View {
        VStack(spacing: 10) {
            Image(systemName: "line.3.horizontal.decrease.circle")
                .font(.system(size: 28))
            Text("无匹配结果")
                .font(.callout)
        }
        .foregroundColor(.secondary)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// 历史列表主体区域。
    private var listSection: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 0) {
                ForEach(Array(filteredItems.enumerated()), id: \.element.id) { index, item in
                    HistoryListItemView(
                        index: index,
                        isFromPanel: isFromPanel,
                        isKeyboardMode: $isKeyboardMode,
                        isSelected: selectedItemID == item.id,
                        isFadingOut: fadingItemID == item.id,
                        namespace: animationNamespace,
                        item: item,
                        onActivate: {
                            activateItem(item)
                        },
                        onCopyOnly: {
                            copyToPasteboard(item: item)
                        }
                    )
                    .id(item.id)
                    .tag(item.id)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 3)
                }
                }
                .padding(.top, isFromPanel ? panelListTopPadding : menuPopupListTopPadding)
            }
            .onAppear {
                listScrollProxy = proxy
                scrollListToTop(proxy: proxy)
            }
        }
    }

    /// 将列表滚动到顶部（新内容插入或首次展示时）。
    private func scrollListToTop(proxy: ScrollViewProxy) {
        guard let id = filteredItems.first?.id else { return }
        DispatchQueue.main.async {
            withAnimation(.easeOut(duration: 0.2)) {
                proxy.scrollTo(id, anchor: .top)
            }
        }
    }

    /// 将当前选中项滚动到可见区域中部，提升键盘导览稳定性。
    private func scrollSelectionIntoView(id: UUID?) {
        guard let id else { return }
        guard let proxy = listScrollProxy else { return }
        DispatchQueue.main.async {
            withAnimation(.easeOut(duration: 0.15)) {
                proxy.scrollTo(id, anchor: .center)
            }
        }
    }

    /// 底部工具栏（清空与行内确认）。
    private var toolbar: some View {
        HStack {
            if isFromPanel {
                if !showClearConfirmation {
                    Button {
                        NSApp.activate(ignoringOtherApps: true)
                        openSettings()
                        NotificationCenter.default.post(name: .hidePanelNotification, object: nil)
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "gearshape")
                            Text("设置")
                        }
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.primary.opacity(0.05))
                        .cornerRadius(4)
                    }
                    .buttonStyle(.plain)
                    .transition(.opacity)
                }
            }

            Spacer()

            if showClearConfirmation {
                Text("确定清空?")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)

                Button("确认") {
                    clearAllHistory()
                    showClearConfirmation = false
                }
                .font(.system(size: 12))
                .foregroundStyle(.red)
                .buttonStyle(.plain)

                Button("取消") {
                    showClearConfirmation = false
                }
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .buttonStyle(.plain)
            } else {
                Button {
                    if confirmBeforeClear {
                        withAnimation {
                            showClearConfirmation = true
                        }
                    } else {
                        clearAllHistory()
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "trash")
                        Text("清空")
                    }
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.primary.opacity(0.05))
                    .cornerRadius(4)
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.delete, modifiers: .command)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.black.opacity(0.02))
        .animation(.easeInOut(duration: 0.2), value: showClearConfirmation)
    }

    /// 处理键盘上下方向键的选中迁移。
    private func moveSelection(up: Bool) -> KeyPress.Result {
        guard !filteredItems.isEmpty else { return .ignored }
        isKeyboardMode = true

        if let current = selectedItemID,
           let idx = filteredItems.firstIndex(where: { $0.id == current }) {
            let next = up ? idx - 1 : idx + 1
            guard filteredItems.indices.contains(next) else { return .handled }
            selectedItemID = filteredItems[next].id
            scrollSelectionIntoView(id: selectedItemID)
            return .handled
        }

        selectedItemID = up ? filteredItems.last?.id : filteredItems.first?.id
        scrollSelectionIntoView(id: selectedItemID)
        return .handled
    }

    /// 处理 ESC：优先关闭预览，其次清空搜索，最后关闭面板。
    private func handleEscapeKey() -> KeyPress.Result {
        if showClearConfirmation {
            showClearConfirmation = false
            return .handled
        }
        if quickLookItemID != nil {
            quickLookItemID = nil
            return .handled
        }
        if !searchText.isEmpty {
            searchText = ""
            return .handled
        }
        NotificationCenter.default.post(name: .hidePanelNotification, object: nil)
        return .handled
    }

    /// 处理回车：关闭预览后激活当前选中项。
    private func handleReturnKey() -> KeyPress.Result {
        if showClearConfirmation {
            clearAllHistory()
            showClearConfirmation = false
            return .handled
        }
        if quickLookItemID != nil {
            quickLookItemID = nil
        }
        let id = selectedItemID ?? filteredItems.first?.id
        guard let id, let item = filteredItems.first(where: { $0.id == id }) else {
            return .ignored
        }
        activateItem(item)
        return .handled
    }

    /// 通过索引激活条目（用于 Cmd+数字直达），先给短暂高亮反馈再执行粘贴。
    private func activateItem(at index: Int) {
        guard filteredItems.indices.contains(index) else { return }
        let item = filteredItems[index]
        selectedItemID = item.id
        isKeyboardMode = true
        scrollSelectionIntoView(id: item.id)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            activateItem(item)
        }
    }

    /// 激活历史项：写回剪贴板，并按入口上下文执行粘贴/置顶策略。
    private func activateItem(_ item: ClipboardItem) {
        resetSelectionState()
        copyToPasteboard(item: item)

        if isFromPanel {
            NSApp.hide(nil)
            NotificationCenter.default.post(name: .hidePanelNotification, object: nil)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                PasteSimulation.simulatePaste()
            }
        } else {
            if bringToTopOnUse {
                switch animationStyle {
                case .float:
                    let response = max(0.20, min(0.80, floatAnimationResponse))
                    withAnimation(.spring(response: response, dampingFraction: 0.8)) {
                        item.createdAt = Date()
                        try? modelContext.save()
                    }
                case .fade:
                    let duration = max(0.05, min(0.40, fadeAnimationDuration))
                    withAnimation(.easeOut(duration: duration)) {
                        fadingItemID = item.id
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + duration) {
                        var tx = Transaction()
                        tx.animation = nil
                        withTransaction(tx) {
                            item.createdAt = Date()
                            try? modelContext.save()
                        }
                        withAnimation(.easeIn(duration: duration)) {
                            fadingItemID = nil
                        }
                    }
                case .none:
                    item.createdAt = Date()
                    try? modelContext.save()
                }
            }
        }
    }

    /// 重置键盘选中视觉状态，避免激活后高亮残留。
    private func resetSelectionState() {
        selectedItemID = nil
        isKeyboardMode = false
    }

    /// 按记录类型将内容写回系统剪贴板，并打上内部标记避免监听回环。
    func copyToPasteboard(item: ClipboardItem) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        if item.itemType == "image", let data = item.itemData {
            pasteboard.setData(data, forType: .tiff)
        } else if item.itemType == "file" {
            let fileURL = URL(fileURLWithPath: item.content)
            pasteboard.writeObjects([fileURL as NSURL])
        } else {
            pasteboard.setString(item.content, forType: .string)
        }

        let internalMarkerType = NSPasteboard.PasteboardType("com.clipboardx.internal")
        pasteboard.setString("true", forType: internalMarkerType)
    }

    /// 清空历史（保留固定项），并重置局部交互状态。
    private func clearAllHistory() {
        NSPasteboard.general.clearContents()

        for item in items where !item.isPinned {
            modelContext.delete(item)
        }

        try? modelContext.save()
        searchText = ""
        selectedItemID = nil
        isKeyboardMode = false
    }
}

private extension View {
    /// 兼容方式隐藏焦点环，保留可聚焦能力而去掉默认蓝色轮廓。
    @ViewBuilder
    func focusRingType(_ type: NSFocusRingType) -> some View {
        if #available(macOS 14.0, *) {
            self.focusEffectDisabled(type == .none)
        } else {
            self
        }
    }
}
