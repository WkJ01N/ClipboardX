//
//  SettingsView.swift
//  ClipboardX
//
//  Created by Rain Walker on 2026/4/11.
//

import Foundation
import KeyboardShortcuts
import ServiceManagement
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    private let menuBarIconOptions = [
        "scissors",
        "doc.on.clipboard",
        "list.clipboard",
        "paperclip",
        "clipboard"
    ]

    @AppStorage("appLanguage") private var appLanguage = AppLanguage.system.rawValue
    @AppStorage("historyLimit") private var historyLimit = 100
    @AppStorage("showMenuBarIcon") private var showMenuBarIcon = true
    @AppStorage("menuBarIconName") private var menuBarIconName = "scissors"
    @AppStorage("displayStyle") private var displayStyle = DisplayStyle.list.rawValue
    @AppStorage("favoritesEnabled") private var favoritesEnabled = true
    @AppStorage("gridCardHeight") private var gridCardHeight = 148.0
    @AppStorage("retentionDays") private var retentionDays = 30
    @AppStorage("timeFormat") private var timeFormat = TimeDisplayFormat.relative.rawValue
    @AppStorage("showSeconds") private var showSeconds = false
    @AppStorage("showItemTimestamp") private var showItemTimestamp = true
    @AppStorage("enableCopySound") private var enableCopySound = false
    @AppStorage("copySoundName") private var copySoundName = "Pop"
    @AppStorage("enableRichMedia") private var enableRichMedia = true
    @AppStorage("recordImages") private var recordImages = true
    @AppStorage("recordFiles") private var recordFiles = true
    @AppStorage("bringToTopOnUse") private var bringToTopOnUse = true
    @AppStorage("hoverInterruptsKeyboard") private var hoverInterruptsKeyboard = true
    @AppStorage("confirmBeforeClear") private var confirmBeforeClear = true
    @AppStorage("blacklistedBundleIDs") private var blacklistedBundleIDs: String = ""
    @AppStorage("spaceKeyQuickLookEnabled") private var spaceKeyQuickLookEnabled = true
    @AppStorage("popupAtCaret") private var popupAtCaret = false
    @AppStorage("isMonitoringPaused") private var isMonitoringPaused = false
    @AppStorage("showPanelPauseControl") private var showPanelPauseControl = true
    @AppStorage("removeTrackingParams") private var removeTrackingParams = false
    @AppStorage("trackingParamRegex") private var trackingParamRegex = "^(utm_.*|spm|fbclid|gclid|share_source|vd_source|si)$"
    @AppStorage("keepOriginalAfterTransform") private var keepOriginalAfterTransform = true
    @AppStorage("enableSensitiveDetection") private var enableSensitiveDetection = true
    @AppStorage("sensitiveRetentionMinutes") private var sensitiveRetentionMinutes = 5
    @AppStorage("hideOnScreenShare") private var hideOnScreenShare = true
    @AppStorage("maskSensitiveContent") private var maskSensitiveContent = true
    @AppStorage("customStorageURL") private var customStorageURL = ""
    @AppStorage("enableLongPressShortcut") private var enableLongPressShortcut = false
    @AppStorage("longPressDuration") private var longPressDuration = 0.5
    @AppStorage("longPressKeyKind") private var longPressKeyKind = LongPressShortcutKeyKind.modifier.rawValue
    @AppStorage("longPressKeyCode") private var longPressKeyCode = LongPressShortcutSupport.defaultKeyCode
    @AppStorage("longPressKeyDisplayName") private var longPressKeyDisplayName = LongPressShortcutSupport.defaultDisplayName
    @AppStorage("enableDoubleClick") private var enableDoubleClick = false
    @AppStorage("doubleClickKey") private var doubleClickKey = DoubleClickModifierKey.option.rawValue
    @AppStorage("mergeDuplicateText") private var mergeDuplicateText = true
    @AppStorage("windowFadeAnimationEnabled") private var windowFadeAnimationEnabled = true
    @AppStorage("windowAnimationDurationMs") private var windowAnimationDurationMs = 220
    @AppStorage("animationStyle") private var animationStyle: AnimationStyle = .float
    @AppStorage("fadeAnimationDuration") private var fadeAnimationDuration = 0.12
    @AppStorage("floatAnimationResponse") private var floatAnimationResponse = 0.40
    @AppStorage("enableTypewriterMode") private var enableTypewriterMode = false
    @AppStorage("typewriterBaseInterval") private var typewriterBaseInterval = 0.05
    @AppStorage("enableRandomInterval") private var enableRandomInterval = false
    @AppStorage("randomIntervalMin") private var randomIntervalMin = 0.01
    @AppStorage("randomIntervalMax") private var randomIntervalMax = 0.1
    @State private var selectedBlacklistID: String?
    @State private var launchAtLoginEnabled = SMAppService.mainApp.status == .enabled
    @State private var launchAtLoginError: String?
    @State private var isRecordingLongPressKey = false
    @State private var longPressKeyRecordMonitor: Any?
    @State private var activeShortcutRecordingTarget: ShortcutRecordingTarget?
    @State private var shortcutRecordMonitor: Any?
    @State private var appDatabaseSizeText = ""
    @State private var isComputingDatabaseSize = false
    @State private var hasLoadedDatabaseSize = false
    @State private var shortcutDisplayText: [ShortcutRecordingTarget: String?] = [:]
    @State private var dataActionStatusMessage: String?
    @Environment(\.modelContext) private var modelContext
    @Environment(\.openURL) private var openURL

    private var blacklistItems: [String] {
        blacklistedBundleIDs
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    var body: some View {
        TabView {
            generalTab
                .tabItem {
                    Label("常规", systemImage: "gearshape")
                }

            shortcutsTab
                .tabItem {
                    Label("快捷键", systemImage: "keyboard")
                }

            advancedTab
                .tabItem {
                    Label("交互", systemImage: "hand.tap")
                }

            privacyTab
                .tabItem {
                    Label("隐私", systemImage: "lock.shield")
                }

            aboutTab
                .tabItem {
                    Label("关于", systemImage: "info.circle")
                }
        }
        .frame(width: 450)
        .frame(minHeight: 350)
    }

    private var generalTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Picker("应用语言", selection: $appLanguage) {
                    ForEach(AppLanguage.allCases) { language in
                        Text(language.displayName).tag(language.rawValue)
                    }
                }
                .pickerStyle(.menu)

                Toggle("开机自动启动", isOn: Binding(
                    get: { launchAtLoginEnabled },
                    set: { newValue in
                        setLaunchAtLogin(newValue)
                    }
                ))

                Toggle("在顶部菜单栏显示图标", isOn: $showMenuBarIcon)

                VStack(alignment: .leading, spacing: 6) {
                    Toggle("开启复制音效", isOn: $enableCopySound)
                    Picker("音效选择", selection: $copySoundName) {
                        Text("Pop").tag("Pop")
                        Text("Purr").tag("Purr")
                        Text("Hero").tag("Hero")
                        Text("Submarine").tag("Submarine")
                        Text("Tink").tag("Tink")
                    }
                    .pickerStyle(.menu)
                    .disabled(!enableCopySound)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("状态栏图标")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    HStack(spacing: 8) {
                        ForEach(menuBarIconOptions, id: \.self) { iconName in
                            Button {
                                menuBarIconName = iconName
                            } label: {
                                Image(systemName: iconName)
                                    .frame(width: 28, height: 24)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 4)
                            .background(
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .fill(menuBarIconName == iconName ? Color.accentColor.opacity(0.18) : Color.primary.opacity(0.06))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .stroke(menuBarIconName == iconName ? Color.accentColor.opacity(0.6) : Color.clear, lineWidth: 1)
                            )
                        }
                    }
                }

                Picker("列表显示风格", selection: $displayStyle) {
                    Text("单行列表").tag(DisplayStyle.list.rawValue)
                    Text("双列网格").tag(DisplayStyle.grid.rawValue)
                }
                .pickerStyle(.menu)

                Toggle("启用常用项", isOn: $favoritesEnabled)

                if displayStyle == DisplayStyle.grid.rawValue {
                    VStack(alignment: .leading, spacing: 4) {
                        Stepper(
                            value: Binding(
                                get: { gridCardHeight },
                                set: { newValue in
                                    gridCardHeight = max(30, min(240, newValue))
                                }
                            ),
                            in: 30...240,
                            step: 2
                        ) {
                            Text("双列卡片高度: \(Int(gridCardHeight))")
                        }
                        Text("仅在双列网格模式下生效。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                VStack(alignment: .leading, spacing: 6) {
                    Stepper(value: Binding(
                        get: { historyLimit },
                        set: { newValue in
                            historyLimit = max(10, min(500, newValue))
                        }
                    ), in: 10...500, step: 10) {
                        Text("历史记录上限: \(historyLimit) 条")
                    }

                    Toggle("开启富媒体记录 (图片与文件)", isOn: $enableRichMedia)

                    if enableRichMedia {
                        VStack(alignment: .leading, spacing: 6) {
                            Toggle("记录图片", isOn: $recordImages)
                            Toggle("记录文件", isOn: $recordFiles)
                        }
                        .padding(.leading, 20)
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text(LocalizedStringResource("记录生命周期与显示"))
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Picker(LocalizedStringResource("历史保留时长"), selection: $retentionDays) {
                        Text(LocalizedStringResource("1天")).tag(1)
                        Text(LocalizedStringResource("7天")).tag(7)
                        Text(LocalizedStringResource("30天")).tag(30)
                        Text(LocalizedStringResource("90天")).tag(90)
                        Text(LocalizedStringResource("永久保留")).tag(0)
                    }
                    .pickerStyle(.menu)

                    Picker(LocalizedStringResource("时间显示格式"), selection: $timeFormat) {
                        ForEach(TimeDisplayFormat.allCases) { format in
                            Text(format.localizedName).tag(format.rawValue)
                        }
                    }
                    .pickerStyle(.menu)

                    Toggle(LocalizedStringResource("显示秒数"), isOn: $showSeconds)
                    Toggle("显示剪贴内容时间", isOn: $showItemTimestamp)
                }

                if let launchAtLoginError {
                    Text(launchAtLoginError)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }

                Spacer()

                Divider()
                    .padding(.vertical, 4)

                HStack {
                    Text("如果你需要完全关闭后台服务：")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("退出 ClipboardX") {
                        NSApplication.shared.terminate(nil)
                    }
                }
            }
            .padding(20)
            .frame(width: 400)
        }
    }

    private var shortcutsTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("设置用于唤出剪贴板悬浮窗的全局快捷键。")
                    .foregroundStyle(.secondary)

                shortcutRecorderRow(title: "唤出快捷键:", target: .toggleClipboard)
                shortcutRecorderRow(title: "暂停/恢复监听:", target: .togglePause)

                Divider()
                    .padding(.vertical, 2)

                VStack(alignment: .leading, spacing: 10) {
                    Toggle("启用长按快捷键呼出窗口", isOn: $enableLongPressShortcut)

                    HStack(spacing: 10) {
                        Text("长按按键：\(longPressKeyDisplayName)")
                        Spacer()
                        Button(isRecordingLongPressKey ? "等待按键..." : "录入按键") {
                            toggleLongPressKeyRecording()
                        }
                        .buttonStyle(.bordered)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("长按触发时长: \(String(format: "%.1f", longPressDuration)) s")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Slider(
                            value: Binding(
                                get: { longPressDuration },
                                set: { newValue in
                                    longPressDuration = max(0.3, min(2.0, newValue))
                                }
                            ),
                            in: 0.3...2.0,
                            step: 0.1
                        )
                    }
                }

                VStack(alignment: .leading, spacing: 10) {
                    Toggle("双击修饰键呼出窗口", isOn: $enableDoubleClick)
                    if enableDoubleClick {
                        Picker("双击按键:", selection: $doubleClickKey) {
                            ForEach(DoubleClickModifierKey.allCases) { key in
                                Text(key.displayName).tag(key.rawValue)
                            }
                        }
                        .pickerStyle(.menu)
                    }
                }

                Divider()
                    .padding(.vertical, 2)

                VStack(alignment: .leading, spacing: 10) {
                    Text("打字机模式")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Toggle("启用打字机模式", isOn: $enableTypewriterMode)
                    shortcutRecorderRow(title: "打字机面板快捷键:", target: .showTypewriterPanel)
                    Text("建议将该快捷键设为 Control+V。")
                        .font(.caption2)
                        .foregroundStyle(.secondary)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(String(format: String(localized: "基础输入间隔: %@ s"), String(format: "%.3f", typewriterBaseInterval)))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Slider(
                            value: Binding(
                                get: { typewriterBaseInterval },
                                set: { newValue in
                                    typewriterBaseInterval = max(0.005, min(0.30, newValue))
                                }
                            ),
                            in: 0.005...0.30,
                            step: 0.005
                        )
                    }

                    Toggle("使用随机间隔", isOn: $enableRandomInterval)

                    if enableRandomInterval {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(String(format: String(localized: "随机最小间隔: %@ s"), String(format: "%.3f", randomIntervalMin)))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Slider(
                                value: Binding(
                                    get: { randomIntervalMin },
                                    set: { newValue in
                                        randomIntervalMin = max(0.001, min(randomIntervalMax, newValue))
                                    }
                                ),
                                in: 0.001...0.30,
                                step: 0.001
                            )
                        }
                        VStack(alignment: .leading, spacing: 4) {
                            Text(String(format: String(localized: "随机最大间隔: %@ s"), String(format: "%.3f", randomIntervalMax)))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Slider(
                                value: Binding(
                                    get: { randomIntervalMax },
                                    set: { newValue in
                                        randomIntervalMax = max(randomIntervalMin, min(0.50, newValue))
                                    }
                                ),
                                in: 0.001...0.50,
                                step: 0.001
                            )
                        }
                    }
                }

                Spacer()
            }
            .padding(20)
            .frame(width: 400)
        }
        .onAppear {
            refreshShortcutDisplayText()
        }
        .onDisappear {
            stopLongPressKeyRecording()
            stopShortcutRecording()
        }
    }

    private func shortcutRecorderRow(title: LocalizedStringKey, target: ShortcutRecordingTarget) -> some View {
        HStack(spacing: 10) {
            Text(title)
            Spacer()

            Group {
                if let text = shortcutDisplayText[target] ?? nil {
                    Text(text)
                } else {
                    Text("未设置")
                }
            }
            .font(.system(.body, design: .monospaced))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.primary.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))

            Button(activeShortcutRecordingTarget == target ? "等待按键..." : "录入快捷键") {
                if activeShortcutRecordingTarget == target {
                    stopShortcutRecording()
                } else {
                    startShortcutRecording(for: target)
                }
            }
            .buttonStyle(.bordered)

            Button {
                restoreDefaultShortcut(for: target)
            } label: {
                Image(systemName: "arrow.counterclockwise")
                    .font(.system(size: 11, weight: .semibold))
            }
            .buttonStyle(.borderless)
        }
    }

    private var advancedTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 6) {
                    Toggle("粘贴后将记录置顶", isOn: $bringToTopOnUse)
                    Text("开启后，被复用的历史记录会自动移动到列表最上方。")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if bringToTopOnUse {
                        Picker("置顶动画风格", selection: $animationStyle) {
                            ForEach(AnimationStyle.allCases) { style in
                                Text(style.localizedName).tag(style)
                            }
                        }
                        .pickerStyle(.menu)

                        if animationStyle == .fade {
                            VStack(alignment: .leading, spacing: 4) {
                                Stepper(
                                    value: Binding(
                                        get: { fadeAnimationDuration },
                                        set: { newValue in
                                            fadeAnimationDuration = max(0.05, min(0.40, newValue))
                                        }
                                    ),
                                    in: 0.05...0.40,
                                    step: 0.01
                                ) {
                                    Text("淡入淡出时长: \(Int(fadeAnimationDuration * 1000)) ms")
                                }
                                Text("值越大，闪现淡入的渐隐/渐显越明显。")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        if animationStyle == .float {
                            VStack(alignment: .leading, spacing: 4) {
                                Stepper(
                                    value: Binding(
                                        get: { floatAnimationResponse },
                                        set: { newValue in
                                            floatAnimationResponse = max(0.20, min(0.80, newValue))
                                        }
                                    ),
                                    in: 0.20...0.80,
                                    step: 0.05
                                ) {
                                    Text("浮动动画速度: \(String(format: "%.2f", floatAnimationResponse))")
                                }
                                Text("值越小速度越快，值越大动作更柔和。")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 6) {
                    Toggle("快捷键呼出时跟随输入光标 (Caret)", isOn: $popupAtCaret)
                    Text("开启后将尝试在文本输入光标处显示面板；若获取失败或未开启无障碍权限，将自动回退到鼠标位置。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Toggle("显示悬浮窗底部暂停/继续监听按钮", isOn: $showPanelPauseControl)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Toggle("合并重复纯文本", isOn: $mergeDuplicateText)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Toggle("启用窗口淡入淡出动画", isOn: $windowFadeAnimationEnabled)
                    if windowFadeAnimationEnabled {
                        Stepper(
                            value: Binding(
                                get: { windowAnimationDurationMs },
                                set: { newValue in
                                    windowAnimationDurationMs = max(100, min(600, newValue))
                                }
                            ),
                            in: 100...600,
                            step: 10
                        ) {
                            Text("窗口动画时长: \(windowAnimationDurationMs) ms")
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 6) {
                    Toggle("鼠标悬浮打断键盘选中", isOn: $hoverInterruptsKeyboard)
                    Text("关闭后，使用键盘(上下键)导览时，鼠标的光标移动不会抢走高亮焦点。纯键盘党建议关闭。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Toggle("清空全部记录前需二次确认", isOn: $confirmBeforeClear)

                VStack(alignment: .leading, spacing: 6) {
                    Toggle("空格键快速预览", isOn: $spaceKeyQuickLookEnabled)
                    Text("开启后，空格键用于预览当前键盘选中项；关闭后，空格键将直接触发该项粘贴。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }
            .padding(20)
            .frame(width: 400)
        }
    }

    private var privacyTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 6) {
                    Toggle("自动移除复制链接中的追踪参数 (如 utm_source, spm 等)", isOn: $removeTrackingParams)
                    if removeTrackingParams {
                        Text("自定义追踪参数正则")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        TextField("^(utm_.*|spm|fbclid|gclid|share_source|vd_source|si)$", text: $trackingParamRegex)
                            .textFieldStyle(.roundedBorder)
                    }
                }

                VStack(alignment: .leading, spacing: 6) {
                    Toggle("内容编码后保留原内容", isOn: $keepOriginalAfterTransform)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("隐私与安全")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Toggle("启用敏感信息检测", isOn: $enableSensitiveDetection)

                    Picker("敏感记录保留时间", selection: $sensitiveRetentionMinutes) {
                        Text("1分钟").tag(1)
                        Text("5分钟").tag(5)
                        Text("10分钟").tag(10)
                        Text("立即销毁(0)").tag(0)
                    }
                    .pickerStyle(.menu)

                    Toggle("敏感项内容打码显示", isOn: $maskSensitiveContent)
                    Toggle("屏幕共享或录屏时隐藏悬浮窗", isOn: $hideOnScreenShare)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("数据管理")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text("数据库路径：\(effectiveStorageFolderPath)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)

                    HStack(spacing: 8) {
                        Button("导出备份") {
                            Task {
                                await exportBackupAction()
                            }
                        }
                        Button("导入备份") {
                            Task {
                                await importBackupAction()
                            }
                        }
                        Button("更改存储位置") {
                            changeStorageLocationAction()
                        }
                    }

                    Button("清理冗余数据并优化存储") {
                        Task {
                            await optimizeStorageAction()
                        }
                    }

                    if let dataActionStatusMessage {
                        Text(dataActionStatusMessage)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }

                Divider()

                VStack(alignment: .leading, spacing: 10) {
                    Text("黑名单")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text("在下方列表中的应用程序里复制内容时，ClipboardX 将会忽略记录。")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    List(selection: $selectedBlacklistID) {
                        ForEach(blacklistItems, id: \.self) { bundleID in
                            Text(bundleID)
                                .tag(bundleID)
                        }
                    }
                    .frame(height: 200)

                    HStack(spacing: 8) {
                        Button("+") {
                            addBlacklistApp()
                        }

                        Button("-") {
                            removeSelectedBlacklistApp()
                        }
                        .disabled(selectedBlacklistID == nil)
                    }
                }
            }
            .padding(20)
            .frame(width: 400)
        }
    }

    private var shortVersion: String {
        (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? "1.0"
    }

    private var buildNumber: String {
        (Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String) ?? "1"
    }

    private func formatByteCount(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useMB, .useKB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }

    private var effectiveStorageFolderPath: String {
        let trimmed = customStorageURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            return trimmed
        }
        return Self.defaultAppSupportFolderURL().path
    }

    nonisolated private static func appDatabaseSizeInBytes() -> Int64 {
        let fileManager = FileManager.default
        guard let appSupportURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return 0
        }

        let bundleID = Bundle.main.bundleIdentifier ?? "ClipboardX"
        let bundleToken = bundleID.replacingOccurrences(of: ".", with: "").lowercased()
        guard let enumerator = fileManager.enumerator(
            at: appSupportURL,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
            options: [.skipsHiddenFiles],
            errorHandler: nil
        ) else {
            return 0
        }

        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            let lowerPath = fileURL.path.lowercased()
            let lowerName = fileURL.lastPathComponent.lowercased()
            let isSwiftDataStoreFile = lowerName.contains("default.store")
                || lowerName.hasSuffix(".sqlite")
                || lowerName.hasSuffix(".sqlite-wal")
                || lowerName.hasSuffix(".sqlite-shm")
            let isLikelyClipboardXFile = lowerPath.contains("clipboardx")
                || lowerPath.contains(bundleToken)
                || lowerPath.contains(bundleID.lowercased())
            guard isSwiftDataStoreFile && isLikelyClipboardXFile else { continue }

            if let values = try? fileURL.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
               values.isRegularFile == true,
               let fileSize = values.fileSize {
                total += Int64(fileSize)
            }
        }
        return total
    }

    private static func defaultAppSupportFolderURL() -> URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
    }

    private func discoverStoreFiles() -> [URL] {
        let fileManager = FileManager.default
        guard let appSupportURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first,
              let enumerator = fileManager.enumerator(at: appSupportURL, includingPropertiesForKeys: nil)
        else {
            return []
        }

        let bundleID = (Bundle.main.bundleIdentifier ?? "ClipboardX").lowercased()
        let bundleToken = bundleID.replacingOccurrences(of: ".", with: "")
        var urls: [URL] = []

        for case let fileURL as URL in enumerator {
            let lowerName = fileURL.lastPathComponent.lowercased()
            let lowerPath = fileURL.path.lowercased()
            let isStoreFile = lowerName.contains("default.store")
                || lowerName.hasSuffix(".sqlite")
                || lowerName.hasSuffix(".sqlite-wal")
                || lowerName.hasSuffix(".sqlite-shm")
                || lowerName.hasSuffix(".store-wal")
                || lowerName.hasSuffix(".store-shm")
            guard isStoreFile else { continue }
            if lowerPath.contains("clipboardx") || lowerPath.contains(bundleToken) || lowerPath.contains(bundleID) {
                urls.append(fileURL)
            }
        }
        return urls
    }

    @MainActor
    private func exportBackupAction() async {
        do {
            let url = try await DataExportManager.exportBackup(using: modelContext)
            dataActionStatusMessage = String(format: String(localized: "已导出备份：%@"), url.lastPathComponent)
        } catch {
            guard (error as NSError).localizedDescription != "cancelled" else { return }
            dataActionStatusMessage = String(localized: "导出失败")
        }
    }

    @MainActor
    private func importBackupAction() async {
        do {
            let inserted = try await DataImportManager.importBackup(using: modelContext)
            dataActionStatusMessage = String(format: String(localized: "导入完成，共新增 %lld 条"), inserted)
        } catch {
            guard (error as NSError).localizedDescription != "cancelled" else { return }
            dataActionStatusMessage = String(localized: "导入失败")
        }
    }

    private func changeStorageLocationAction() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true

        guard panel.runModal() == .OK, let folderURL = panel.url else { return }
        let sourceFiles = discoverStoreFiles()
        let fileManager = FileManager.default
        var movedAny = false

        for sourceURL in sourceFiles {
            let destinationURL = folderURL.appendingPathComponent(sourceURL.lastPathComponent)
            guard !fileManager.fileExists(atPath: destinationURL.path) else { continue }
            do {
                try fileManager.moveItem(at: sourceURL, to: destinationURL)
                movedAny = true
            } catch {
                continue
            }
        }

        customStorageURL = folderURL.path
        dataActionStatusMessage = movedAny
            ? String(localized: "已迁移数据库文件并更新存储路径")
            : String(localized: "已更新存储路径，建议重启应用以生效")
    }

    @MainActor
    private func optimizeStorageAction() async {
        cleanupExpiredForOptimization()
        cleanupSensitiveForOptimization()

        let storeFiles = discoverStoreFiles().filter {
            $0.pathExtension == "sqlite" || $0.lastPathComponent.lowercased().hasSuffix(".store")
        }
        let vacuumed = await Task.detached(priority: .utility) {
            DataMaintenanceManager.vacuum(files: storeFiles)
        }.value
        dataActionStatusMessage = vacuumed > 0
            ? String(format: String(localized: "优化完成，已处理 %lld 个数据库文件"), vacuumed)
            : String(localized: "优化完成")

        await refreshDatabaseSizeText()
    }

    private func cleanupExpiredForOptimization() {
        guard retentionDays > 0,
              let thresholdDate = Calendar.current.date(byAdding: .day, value: -retentionDays, to: Date())
        else {
            return
        }
        let descriptor = FetchDescriptor<ClipboardItem>(
            predicate: #Predicate<ClipboardItem> { $0.createdAt < thresholdDate && $0.isFavorite == false }
        )
        if let items = try? modelContext.fetch(descriptor), !items.isEmpty {
            for item in items {
                modelContext.delete(item)
            }
            try? modelContext.save()
        }
    }

    private func cleanupSensitiveForOptimization() {
        let retentionMinutes = max(0, sensitiveRetentionMinutes)
        let graceSeconds: TimeInterval = retentionMinutes == 0 ? 3 : TimeInterval(retentionMinutes * 60)
        let cutoff = Date().addingTimeInterval(-graceSeconds)
        let descriptor = FetchDescriptor<ClipboardItem>(
            predicate: #Predicate<ClipboardItem> { $0.isSensitive == true && $0.createdAt < cutoff }
        )
        if let items = try? modelContext.fetch(descriptor), !items.isEmpty {
            for item in items {
                modelContext.delete(item)
            }
            try? modelContext.save()
        }
    }

    private var aboutTab: some View {
        VStack {
            Spacer()

            VStack(spacing: 10) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 64, height: 64)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

                Text("ClipboardX")
                    .font(.largeTitle)
                    .fontWeight(.bold)

                Text("版本 \(shortVersion) (\(buildNumber))")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                if hasLoadedDatabaseSize {
                    Text("存储空间占用：\(appDatabaseSizeText)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .padding(.top, 4)
                } else {
                    Text("存储空间占用：\("计算中...")")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .padding(.top, 4)
                }

                Button("清理缓存") {
                    clearHistoryCache()
                }
                .buttonStyle(.bordered)
                .padding(.top, 2)

                HStack(spacing: 12) {
                    Button("检查更新") {
                        if let url = URL(string: "https://github.com/WkJ01N/ClipboardX/releases") {
                            openURL(url)
                        }
                    }

                    Button("GitHub 仓库") {
                        if let url = URL(string: "https://github.com/WkJ01N/ClipboardX") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                }
                .padding(.top, 6)
            }

            Spacer()
        }
        .padding(20)
        .frame(width: 400)
        .task {
            if !hasLoadedDatabaseSize {
                await refreshDatabaseSizeText()
            }
        }
        .onChange(of: appLanguage) {
            Task {
                await refreshDatabaseSizeText()
            }
        }
    }

    private func addBlacklistApp() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")

        guard panel.runModal() == .OK,
              let url = panel.url,
              let bundleID = Bundle(url: url)?.bundleIdentifier
        else {
            return
        }

        var items = blacklistItems
        guard !items.contains(bundleID) else { return }
        items.append(bundleID)
        blacklistedBundleIDs = items.joined(separator: ",")
    }

    private func removeSelectedBlacklistApp() {
        guard let selectedBlacklistID else { return }
        let items = blacklistItems.filter { $0 != selectedBlacklistID }
        blacklistedBundleIDs = items.joined(separator: ",")
        self.selectedBlacklistID = nil
    }

    private func clearHistoryCache() {
        NSPasteboard.general.clearContents()
        let descriptor = FetchDescriptor<ClipboardItem>()
        if let allItems = try? modelContext.fetch(descriptor) {
            for item in allItems where !item.isPinned {
                modelContext.delete(item)
            }
            try? modelContext.save()
        }
        Task {
            await refreshDatabaseSizeText()
        }
    }

    @MainActor
    private func refreshDatabaseSizeText() async {
        guard !isComputingDatabaseSize else { return }
        isComputingDatabaseSize = true
        let bytes = await Task.detached(priority: .utility) {
            Self.appDatabaseSizeInBytes()
        }.value
        appDatabaseSizeText = formatByteCount(bytes)
        hasLoadedDatabaseSize = true
        isComputingDatabaseSize = false
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            launchAtLoginError = nil
            launchAtLoginEnabled = enabled
        } catch {
            launchAtLoginError = error.localizedDescription
            launchAtLoginEnabled = (SMAppService.mainApp.status == .enabled)
        }
    }

    private func toggleLongPressKeyRecording() {
        if isRecordingLongPressKey {
            stopLongPressKeyRecording()
        } else {
            startLongPressKeyRecording()
        }
    }

    private func startLongPressKeyRecording() {
        stopLongPressKeyRecording()
        isRecordingLongPressKey = true
        longPressKeyRecordMonitor = NSEvent.addLocalMonitorForEvents(matching: [.flagsChanged, .keyDown]) { event in
            if event.type == .flagsChanged,
               let modifierFlag = LongPressShortcutSupport.modifierFlag(for: event.keyCode),
               event.modifierFlags.intersection(.deviceIndependentFlagsMask).contains(modifierFlag) {
                self.longPressKeyKind = LongPressShortcutKeyKind.modifier.rawValue
                self.longPressKeyCode = Int(event.keyCode)
                self.longPressKeyDisplayName = LongPressShortcutSupport.modifierDisplayName(for: event.keyCode)
                self.stopLongPressKeyRecording()
                return nil
            }

            if event.type == .keyDown {
                self.longPressKeyKind = LongPressShortcutKeyKind.regular.rawValue
                self.longPressKeyCode = Int(event.keyCode)
                self.longPressKeyDisplayName = LongPressShortcutSupport.displayName(from: event)
                self.stopLongPressKeyRecording()
                return nil
            }
            return event
        }
    }

    private func stopLongPressKeyRecording() {
        if let longPressKeyRecordMonitor {
            NSEvent.removeMonitor(longPressKeyRecordMonitor)
            self.longPressKeyRecordMonitor = nil
        }
        isRecordingLongPressKey = false
    }

    private func startShortcutRecording(for target: ShortcutRecordingTarget) {
        stopShortcutRecording()
        activeShortcutRecordingTarget = target
        shortcutRecordMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == 53 { // Esc
                self.stopShortcutRecording()
                return nil
            }
            guard let shortcut = KeyboardShortcuts.Shortcut(event: event) else {
                return nil
            }
            KeyboardShortcuts.setShortcut(shortcut, for: target.name)
            self.refreshShortcutDisplayText()
            self.stopShortcutRecording()
            return nil
        }
    }

    private func stopShortcutRecording() {
        if let shortcutRecordMonitor {
            NSEvent.removeMonitor(shortcutRecordMonitor)
            self.shortcutRecordMonitor = nil
        }
        activeShortcutRecordingTarget = nil
    }

    private func restoreDefaultShortcut(for target: ShortcutRecordingTarget) {
        stopShortcutRecording()
        KeyboardShortcuts.setShortcut(target.defaultShortcut, for: target.name)
        refreshShortcutDisplayText()
    }

    private func refreshShortcutDisplayText() {
        var next: [ShortcutRecordingTarget: String?] = [:]
        for target in ShortcutRecordingTarget.allCases {
            if let shortcut = KeyboardShortcuts.getShortcut(for: target.name) {
                next[target] = shortcut.description
            } else {
                next[target] = nil
            }
        }
        shortcutDisplayText = next
    }
}

private enum ShortcutRecordingTarget: Equatable, Hashable, CaseIterable {
    case toggleClipboard
    case togglePause
    case showTypewriterPanel

    var name: KeyboardShortcuts.Name {
        switch self {
        case .toggleClipboard:
            return .toggleClipboard
        case .togglePause:
            return .togglePause
        case .showTypewriterPanel:
            return .showTypewriterPanel
        }
    }

    var defaultShortcut: KeyboardShortcuts.Shortcut? {
        switch self {
        case .toggleClipboard:
            return KeyboardShortcuts.Shortcut(.v, modifiers: [.control])
        case .togglePause:
            return nil
        case .showTypewriterPanel:
            return KeyboardShortcuts.Shortcut(.v, modifiers: [.control, .option])
        }
    }
}

