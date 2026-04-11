//
//  SettingsView.swift
//  ClipboardX
//
//  Created by Rain Walker on 2026/4/11.
//

import Foundation
import KeyboardShortcuts
import ServiceManagement
import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @AppStorage("historyLimit") private var historyLimit = 100
    @AppStorage("showMenuBarIcon") private var showMenuBarIcon = true
    @AppStorage("enableRichMedia") private var enableRichMedia = true
    @AppStorage("recordImages") private var recordImages = true
    @AppStorage("recordFiles") private var recordFiles = true
    @AppStorage("bringToTopOnUse") private var bringToTopOnUse = true
    @AppStorage("hoverInterruptsKeyboard") private var hoverInterruptsKeyboard = true
    @AppStorage("confirmBeforeClear") private var confirmBeforeClear = true
    @AppStorage("ignoreSensitiveContent") private var ignoreSensitiveContent = true
    @AppStorage("blacklistedBundleIDs") private var blacklistedBundleIDs: String = ""
    @AppStorage("spaceKeyQuickLookEnabled") private var spaceKeyQuickLookEnabled = true
    @AppStorage("animationStyle") private var animationStyle: AnimationStyle = .float
    @AppStorage("fadeAnimationDuration") private var fadeAnimationDuration = 0.12
    @AppStorage("floatAnimationResponse") private var floatAnimationResponse = 0.40
    @State private var selectedBlacklistID: String?
    @State private var launchAtLoginEnabled = SMAppService.mainApp.status == .enabled
    @State private var launchAtLoginError: String?

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
                    Label("黑名单", systemImage: "shield.slash")
                }
        }
        .frame(width: 450)
        .frame(minHeight: 350)
    }

    private var generalTab: some View {
        VStack(alignment: .leading, spacing: 16) {
            Toggle("开机自动启动", isOn: Binding(
                get: { launchAtLoginEnabled },
                set: { newValue in
                    setLaunchAtLogin(newValue)
                }
            ))

            Toggle("在顶部菜单栏显示图标", isOn: $showMenuBarIcon)

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

    private var shortcutsTab: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("设置用于唤出剪贴板悬浮窗的全局快捷键。")
                .foregroundStyle(.secondary)

            KeyboardShortcuts.Recorder("唤出快捷键:", name: .toggleClipboard)

            Spacer()
        }
        .padding(20)
        .frame(width: 400)
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
                                Text(style.rawValue).tag(style)
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

                VStack(alignment: .leading, spacing: 6) {
                    Toggle("忽略密码管理器等敏感内容", isOn: $ignoreSensitiveContent)
                    Text("开启后将尝试拦截来自密码管理器的复制行为。本软件为纯本地应用，绝不会获取或上传用户的任何个人信息。")
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
        VStack(alignment: .leading, spacing: 10) {
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

            Spacer()
        }
        .padding(20)
        .frame(width: 400)
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
}

