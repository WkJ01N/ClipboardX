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
    @AppStorage("menuBarIconName") private var menuBarIconName = "scissors"
    @AppStorage("appLanguage") private var appLanguage = AppLanguage.system.rawValue
    @AppStorage("isMonitoringPaused") private var isMonitoringPaused = false

    init() {
        if KeyboardShortcuts.getShortcut(for: .toggleClipboard) == nil {
            KeyboardShortcuts.setShortcut(
                KeyboardShortcuts.Shortcut(.v, modifiers: [.control]),
                for: .toggleClipboard
            )
        }
        KeyboardShortcuts.onKeyDown(for: .togglePause) {
            let current = UserDefaults.standard.bool(forKey: "isMonitoringPaused")
            UserDefaults.standard.set(!current, forKey: "isMonitoringPaused")
        }
    }

    var body: some Scene {
        let appLocale = LanguageManager.locale(for: appLanguage)

        MenuBarExtra("ClipboardX", systemImage: menuBarIconName, isInserted: $showMenuBarIcon) {
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

                    Button("退出应用") {
                        NSApplication.shared.terminate(nil)
                    }
                }
                .padding(10)
            }
            .environment(\.locale, appLocale)
        }
        .menuBarExtraStyle(.window)
        .modelContainer(appState.modelContainer)

        Settings {
            SettingsView()
                .modelContainer(appState.modelContainer)
                .environment(\.locale, appLocale)
        }
    }
}

/// 在应用启动时订阅 `ClipboardMonitor` 的发布值并写入 SwiftData；并管理悬浮历史窗口。
@MainActor
private final class ClipboardAppState: ObservableObject {
    let modelContainer: ModelContainer
    let clipboardMonitor: ClipboardMonitor
    let panelManager: PanelManager
    let longPressShortcutMonitor: LongPressShortcutMonitor
    let doubleClickMonitor: DoubleClickMonitor
    private var captureSubscription: AnyCancellable?
    private var cleanupTimer: Timer?
    private var sensitiveCleanupTimer: Timer?
    @AppStorage("historyLimit") private var historyLimit = 100
    @AppStorage("mergeDuplicateText") private var mergeDuplicateText = true
    @AppStorage("retentionDays") private var retentionDays = 30
    @AppStorage("sensitiveRetentionMinutes") private var sensitiveRetentionMinutes = 5

    init() {
        let customStoragePath = UserDefaults.standard.string(forKey: "customStorageURL") ?? ""
        do {
            if let customStoreURL = Self.customStoreFileURL(from: customStoragePath) {
                try Self.prepareCustomStoreLocationIfNeeded(targetStoreURL: customStoreURL)
                let configuration = ModelConfiguration(url: customStoreURL)
                modelContainer = try ModelContainer(for: ClipboardItem.self, configurations: configuration)
            } else {
                modelContainer = try ModelContainer(for: ClipboardItem.self)
            }
        } catch {
            fatalError("Failed to create ModelContainer for ClipboardItem: \(error)")
        }

        clipboardMonitor = ClipboardMonitor()
        panelManager = PanelManager(modelContainer: modelContainer)
        longPressShortcutMonitor = LongPressShortcutMonitor { [weak panelManager] in
            panelManager?.presentPanel()
        }
        doubleClickMonitor = DoubleClickMonitor { [weak panelManager] in
            panelManager?.togglePanel()
        }

        captureSubscription = clipboardMonitor.$captureEventCount
            .dropFirst()
            .sink { [weak self] _ in
                self?.persistLatestCapture()
            }

        cleanupExpiredItems()
        cleanupSensitiveItems()
        startCleanupTimer()
        startSensitiveCleanupTimer()
    }

    deinit {
        cleanupTimer?.invalidate()
        sensitiveCleanupTimer?.invalidate()
    }

    private func persistLatestCapture() {
        guard let text = clipboardMonitor.lastCapturedText, !text.isEmpty else { return }
        let type = clipboardMonitor.lastCapturedType
        let data = clipboardMonitor.lastCapturedData
        let isSensitive = clipboardMonitor.lastCapturedIsSensitive
        let context = modelContainer.mainContext

        if mergeDuplicateText, type == "text" {
            let duplicateDescriptor = FetchDescriptor<ClipboardItem>(
                predicate: #Predicate<ClipboardItem> {
                    $0.itemType == "text" && $0.content == text
                },
                sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
            )
            if let duplicates = try? context.fetch(duplicateDescriptor), !duplicates.isEmpty {
                let keeper = duplicates[0]
                keeper.createdAt = Date()
                keeper.isSensitive = keeper.isSensitive || isSensitive
                for duplicate in duplicates.dropFirst() {
                    context.delete(duplicate)
                }
                if (try? context.save()) != nil {
                    ClipboardMonitor.playCopySoundIfEnabled()
                    if keeper.isSensitive && sensitiveRetentionMinutes == 0 {
                        scheduleSensitiveAutoDestroy(for: keeper.id)
                    }
                }
                enforceHistoryLimit(in: context)
                return
            }
        }

        let item = ClipboardItem(content: text, itemType: type, itemData: data, isSensitive: isSensitive)
        context.insert(item)
        if (try? context.save()) != nil {
            ClipboardMonitor.playCopySoundIfEnabled()
            if isSensitive && sensitiveRetentionMinutes == 0 {
                scheduleSensitiveAutoDestroy(for: item.id)
            }
        }
        enforceHistoryLimit(in: context)
    }

    private func enforceHistoryLimit(in context: ModelContext) {
        let descriptor = FetchDescriptor<ClipboardItem>(
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        if let allItems = try? context.fetch(descriptor) {
            let unpinnedItems = allItems.filter { !$0.isPinned }
            if unpinnedItems.count > historyLimit {
                for stale in unpinnedItems.dropFirst(historyLimit) {
                    context.delete(stale)
                }
                try? context.save()
            }
        }
    }

    private func startCleanupTimer() {
        cleanupTimer?.invalidate()
        let timer = Timer(timeInterval: 3600, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor [self] in
                self.cleanupExpiredItems()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        cleanupTimer = timer
    }

    private func startSensitiveCleanupTimer() {
        sensitiveCleanupTimer?.invalidate()
        let timer = Timer(timeInterval: 30, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor [self] in
                self.cleanupSensitiveItems()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        sensitiveCleanupTimer = timer
    }

    private func cleanupExpiredItems() {
        guard retentionDays > 0 else { return }
        guard let thresholdDate = Calendar.current.date(byAdding: .day, value: -retentionDays, to: Date()) else {
            return
        }

        let context = modelContainer.mainContext
        let descriptor = FetchDescriptor<ClipboardItem>(
            predicate: #Predicate<ClipboardItem> {
                $0.createdAt < thresholdDate && $0.isFavorite == false
            }
        )
        if let expiredItems = try? context.fetch(descriptor), !expiredItems.isEmpty {
            for item in expiredItems {
                context.delete(item)
            }
            try? context.save()
        }
    }

    private func cleanupSensitiveItems() {
        let retentionMinutes = max(0, sensitiveRetentionMinutes)
        let graceSeconds: TimeInterval = retentionMinutes == 0 ? 3 : TimeInterval(retentionMinutes * 60)
        let cutoff = Date().addingTimeInterval(-graceSeconds)

        let context = modelContainer.mainContext
        let descriptor = FetchDescriptor<ClipboardItem>(
            predicate: #Predicate<ClipboardItem> {
                $0.isSensitive == true && $0.createdAt < cutoff
            }
        )
        if let sensitiveItems = try? context.fetch(descriptor), !sensitiveItems.isEmpty {
            for item in sensitiveItems {
                context.delete(item)
            }
            try? context.save()
        }
    }

    private func scheduleSensitiveAutoDestroy(for id: UUID) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
            guard let self else { return }
            Task { @MainActor [self] in
                let context = self.modelContainer.mainContext
                let descriptor = FetchDescriptor<ClipboardItem>(
                    predicate: #Predicate<ClipboardItem> { item in
                        item.id == id && item.isSensitive == true
                    }
                )
                if let matches = try? context.fetch(descriptor), !matches.isEmpty {
                    for item in matches {
                        context.delete(item)
                    }
                    try? context.save()
                }
            }
        }
    }

    nonisolated private static func customStoreFileURL(from storedPath: String) -> URL? {
        let trimmed = storedPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return URL(fileURLWithPath: trimmed, isDirectory: true).appendingPathComponent("default.store")
    }

    nonisolated private static func prepareCustomStoreLocationIfNeeded(targetStoreURL: URL) throws {
        let fileManager = FileManager.default
        let targetDirectory = targetStoreURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: targetDirectory, withIntermediateDirectories: true, attributes: nil)

        if fileManager.fileExists(atPath: targetStoreURL.path) {
            return
        }

        let candidates = discoverLikelyStoreFiles()
        for sourceURL in candidates where sourceURL.lastPathComponent.hasPrefix("default.store") {
            let destinationURL = targetDirectory.appendingPathComponent(sourceURL.lastPathComponent)
            guard !fileManager.fileExists(atPath: destinationURL.path) else { continue }
            do {
                try fileManager.moveItem(at: sourceURL, to: destinationURL)
            } catch {
                // 如果数据库仍被占用，后续由新路径重新初始化创建空库；旧库文件保留不删。
                continue
            }
        }
    }

    nonisolated private static func discoverLikelyStoreFiles() -> [URL] {
        let fileManager = FileManager.default
        guard let appSupportURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first,
              let enumerator = fileManager.enumerator(at: appSupportURL, includingPropertiesForKeys: nil)
        else {
            return []
        }

        let bundleID = Bundle.main.bundleIdentifier?.lowercased() ?? "clipboardx"
        var results: [URL] = []
        for case let fileURL as URL in enumerator {
            let lowerName = fileURL.lastPathComponent.lowercased()
            let lowerPath = fileURL.path.lowercased()
            let likelyStore = lowerName.hasPrefix("default.store")
                || lowerName.hasSuffix(".sqlite")
                || lowerName.hasSuffix(".sqlite-wal")
                || lowerName.hasSuffix(".sqlite-shm")
                || lowerName.hasSuffix(".store-wal")
                || lowerName.hasSuffix(".store-shm")
            guard likelyStore else { continue }
            if lowerPath.contains("clipboardx") || lowerPath.contains(bundleID.replacingOccurrences(of: ".", with: "")) {
                results.append(fileURL)
            }
        }
        return results
    }
}
