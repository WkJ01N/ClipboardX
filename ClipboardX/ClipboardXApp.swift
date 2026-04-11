//
//  ClipboardXApp.swift
//  ClipboardX
//
//  Created by Rain Walker on 2026/4/10.
//

import AppKit
import Combine
import KeyboardShortcuts
import SwiftData
import SwiftUI

@main
struct ClipboardXApp: App {
    @StateObject private var appState = ClipboardAppState()
    @AppStorage("showMenuBarIcon") private var showMenuBarIcon = true

    init() {
        if KeyboardShortcuts.getShortcut(for: .toggleClipboard) == nil {
            KeyboardShortcuts.setShortcut(
                KeyboardShortcuts.Shortcut(.v, modifiers: [.control]),
                for: .toggleClipboard
            )
        }
    }

    var body: some Scene {
        MenuBarExtra("ClipboardX", systemImage: "scissors", isInserted: $showMenuBarIcon) {
            VStack(alignment: .leading, spacing: 0) {
                HistoryListView(isFromPanel: false)

                Divider()

                HStack(alignment: .center) {
                    SettingsLink {
                        Text("偏好设置...")
                    }
                    .keyboardShortcut(",", modifiers: .command)
                    .simultaneousGesture(TapGesture().onEnded {
                        NSApp.activate(ignoringOtherApps: true)
                    })

                    Spacer()

                    Button("退出应用") {
                        NSApplication.shared.terminate(nil)
                    }
                }
                .padding(10)
            }
        }
        .menuBarExtraStyle(.window)
        .modelContainer(appState.modelContainer)

        Settings {
            SettingsView()
                .modelContainer(appState.modelContainer)
        }
    }
}

/// 在应用启动时订阅 `ClipboardMonitor` 的发布值并写入 SwiftData；并管理悬浮历史窗口。
@MainActor
private final class ClipboardAppState: ObservableObject {
    let modelContainer: ModelContainer
    let clipboardMonitor: ClipboardMonitor
    let panelManager: PanelManager
    private var captureSubscription: AnyCancellable?
    @AppStorage("historyLimit") private var historyLimit = 100

    init() {
        do {
            modelContainer = try ModelContainer(for: ClipboardItem.self)
        } catch {
            fatalError("Failed to create ModelContainer for ClipboardItem: \(error)")
        }

        clipboardMonitor = ClipboardMonitor()
        panelManager = PanelManager(modelContainer: modelContainer)

        captureSubscription = clipboardMonitor.$captureEventCount
            .dropFirst()
            .sink { [weak self] _ in
                self?.persistLatestCapture()
            }
    }

    private func persistLatestCapture() {
        guard let text = clipboardMonitor.lastCapturedText, !text.isEmpty else { return }
        let type = clipboardMonitor.lastCapturedType
        let data = clipboardMonitor.lastCapturedData

        let item = ClipboardItem(content: text, itemType: type, itemData: data)
        modelContainer.mainContext.insert(item)
        try? modelContainer.mainContext.save()

        let descriptor = FetchDescriptor<ClipboardItem>(
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        if let allItems = try? modelContainer.mainContext.fetch(descriptor) {
            let unpinnedItems = allItems.filter { !$0.isPinned }
            if unpinnedItems.count > historyLimit {
                for stale in unpinnedItems.dropFirst(historyLimit) {
                    modelContainer.mainContext.delete(stale)
                }
                try? modelContainer.mainContext.save()
            }
        }
    }
}
