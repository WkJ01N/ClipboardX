//
//  ClipboardXApp.swift
//  ClipboardX
//
//  Created by Rain Walker on 2026/4/10.
//

import AppKit
import Combine
import CryptoKit
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
    @Published private(set) var startupError: String?
    @AppStorage("historyLimit") private var historyLimit = 100
    @AppStorage("mergeDuplicateText") private var mergeDuplicateText = true
    @AppStorage("retentionDays") private var retentionDays = 30
    @AppStorage("sensitiveRetentionMinutes") private var sensitiveRetentionMinutes = 5

    init() {
        let customStoragePath = UserDefaults.standard.string(forKey: "customStorageURL") ?? ""
        let resolvedContainer: ModelContainer
        var resolvedStartupError: String?
        var resolvedStoreURL: URL?
        do {
            let initialConfiguration: ModelConfiguration
            if let customStoreURL = Self.customStoreFileURL(from: customStoragePath) {
                initialConfiguration = ModelConfiguration(url: customStoreURL)
            } else {
                initialConfiguration = ModelConfiguration()
            }
            try StoreRecoveryManager.applyPendingRestoreIfNeeded(currentStoreURL: initialConfiguration.url)
            let storeURL = try StoreRecoveryManager.applyPendingLocationIfNeeded(currentStoreURL: initialConfiguration.url)
            resolvedStoreURL = storeURL
            _ = try StoreRecoveryManager.createMigrationSnapshotIfNeeded(storeURL: storeURL)
            try PayloadStore.shared.configure(storeURL: storeURL)
            let configuration = ModelConfiguration(url: storeURL)
            resolvedContainer = try ModelContainer(
                for: ClipboardItem.self,
                migrationPlan: ClipboardMigrationPlan.self,
                configurations: configuration
            )
        } catch let versionedMigrationError {
            do {
                guard let resolvedStoreURL else { throw versionedMigrationError }
                resolvedContainer = try StoreRecoveryManager.rebuildUnversionedStore(at: resolvedStoreURL)
                UserDefaults.standard.removeObject(forKey: "lastStoreRecoveryError")
            } catch let legacyMigrationError {
                let message = "\(versionedMigrationError.localizedDescription)\n\(legacyMigrationError.localizedDescription)"
                resolvedStartupError = message
                UserDefaults.standard.set(message, forKey: "lastStoreRecoveryError")
                let fallback = ModelConfiguration(isStoredInMemoryOnly: true)
                do {
                    resolvedContainer = try ModelContainer(
                        for: ClipboardItem.self,
                        migrationPlan: ClipboardMigrationPlan.self,
                        configurations: fallback
                    )
                } catch {
                    preconditionFailure("Unable to create recovery ModelContainer: \(error)")
                }
            }
        }
        modelContainer = resolvedContainer

        clipboardMonitor = ClipboardMonitor()
        panelManager = PanelManager(modelContainer: modelContainer)
        longPressShortcutMonitor = LongPressShortcutMonitor { [weak panelManager] in
            panelManager?.presentPanel()
        }
        doubleClickMonitor = DoubleClickMonitor { [weak panelManager] in
            panelManager?.togglePanel()
        }
        startupError = resolvedStartupError

        captureSubscription = clipboardMonitor.$captureEventCount
            .dropFirst()
            .sink { [weak self] _ in
                Task { await self?.persistLatestCapture() }
            }

        cleanupExpiredItems()
        cleanupSensitiveItems()
        migrateLegacyRecords()
        startCleanupTimer()
        startSensitiveCleanupTimer()
    }

    deinit {
        cleanupTimer?.invalidate()
        sensitiveCleanupTimer?.invalidate()
    }

    private func persistLatestCapture() async {
        guard let capture = clipboardMonitor.lastCapture else { return }
        let text = capture.text
        let type = capture.kind.rawValue
        let context = modelContainer.mainContext

        if mergeDuplicateText {
            let captureHash = capture.contentHash
            let duplicateDescriptor = FetchDescriptor<ClipboardItem>(
                predicate: #Predicate<ClipboardItem> {
                    $0.itemType == type && $0.contentHash == captureHash
                },
                sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
            )
            if let duplicates = try? context.fetch(duplicateDescriptor), !duplicates.isEmpty {
                let keeper = duplicates[0]
                keeper.createdAt = Date()
                for duplicate in duplicates.dropFirst() {
                    PayloadStore.shared.remove(relativePath: duplicate.payloadRelativePath)
                    context.delete(duplicate)
                }
                do {
                    try context.save()
                    ClipboardMonitor.playCopySoundIfEnabled()
                    if keeper.isSensitive && sensitiveRetentionMinutes == 0 {
                        scheduleSensitiveAutoDestroy(for: keeper.id)
                    }
                } catch {
                    startupError = error.localizedDescription
                }
                enforceHistoryLimit(in: context)
                return
            }
        }

        let id = UUID()
        var storedContent = text
        var encryptedContent: Data?
        if capture.isSensitive {
            do {
                encryptedContent = try SensitiveDataService.shared.encrypt(text)
                storedContent = ""
            } catch {
                startupError = error.localizedDescription
                return
            }
        }
        var payloadPath: String?
        if let data = capture.data {
            do {
                payloadPath = try PayloadStore.shared.write(data, id: id)
            } catch {
                startupError = error.localizedDescription
                return
            }
        }
        let item = ClipboardItem(
            id: id,
            content: storedContent,
            itemType: type,
            isSensitive: capture.isSensitive,
            sourceBundleIdentifier: capture.sourceBundleIdentifier,
            sourceAppName: capture.sourceAppName,
            contentHash: capture.contentHash,
            filePaths: capture.filePaths,
            payloadRelativePath: payloadPath,
            payloadByteCount: Int64(capture.data?.count ?? 0),
            payloadTypeIdentifier: capture.payloadTypeIdentifier,
            encryptedContent: encryptedContent,
            encryptionVersion: encryptedContent == nil ? 0 : 1
        )
        context.insert(item)
        do {
            try context.save()
            ClipboardMonitor.playCopySoundIfEnabled()
            if capture.isSensitive && sensitiveRetentionMinutes == 0 {
                scheduleSensitiveAutoDestroy(for: item.id)
            }
        } catch {
            PayloadStore.shared.remove(relativePath: payloadPath)
            startupError = error.localizedDescription
        }
        enforceHistoryLimit(in: context)
    }

    private func migrateLegacyRecords() {
        let context = modelContainer.mainContext
        let descriptor = FetchDescriptor<ClipboardItem>()
        guard let items = try? context.fetch(descriptor) else { return }
        var changed = false
        for item in items {
            if item.kind == .image, item.payloadRelativePath == nil, let data = item.itemData {
                if let path = try? PayloadStore.shared.write(data, id: item.id) {
                    item.payloadRelativePath = path
                    item.payloadByteCount = Int64(data.count)
                    item.itemData = nil
                    changed = true
                }
            }
            if item.isSensitive, item.encryptedContent == nil, !item.content.isEmpty,
               let encrypted = try? SensitiveDataService.shared.encrypt(item.content) {
                item.encryptedContent = encrypted
                item.encryptionVersion = 1
                item.content = ""
                changed = true
            }
            if item.contentHash == nil {
                let source: Data
                if let path = item.payloadRelativePath, let data = try? PayloadStore.shared.read(relativePath: path) {
                    source = data
                } else if item.kind == .file {
                    source = Data(item.filePaths.joined(separator: "\u{0}").utf8)
                } else {
                    source = Data(ClipboardContentResolver.text(for: item).utf8)
                }
                item.contentHash = SHA256.hash(data: source).map { String(format: "%02x", $0) }.joined()
                changed = true
            }
        }
        if changed {
            do { try context.save() }
            catch { UserDefaults.standard.set(error.localizedDescription, forKey: "lastStoreRecoveryError") }
        }
        let paths = Set(items.compactMap(\.payloadRelativePath))
        _ = PayloadStore.shared.removeOrphans(keeping: paths)
    }

    private func enforceHistoryLimit(in context: ModelContext) {
        let descriptor = FetchDescriptor<ClipboardItem>(
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        if let allItems = try? context.fetch(descriptor) {
            let unpinnedItems = allItems.filter { !$0.isPinned }
            if unpinnedItems.count > historyLimit {
                for stale in unpinnedItems.dropFirst(historyLimit) {
                    PayloadStore.shared.remove(relativePath: stale.payloadRelativePath)
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
                PayloadStore.shared.remove(relativePath: item.payloadRelativePath)
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
                PayloadStore.shared.remove(relativePath: item.payloadRelativePath)
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
                        PayloadStore.shared.remove(relativePath: item.payloadRelativePath)
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
