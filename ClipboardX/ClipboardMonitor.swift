//
//  ClipboardMonitor.swift
//  ClipboardX
//
//  Created by Rain Walker on 2026/4/10.
//

import AppKit
import Combine
import SwiftUI

/// 通过轮询 `NSPasteboard.general.changeCount` 监听系统剪贴板变化。
///
/// 该监控器负责把系统剪贴板中的可记录内容（文本、图片、文件）转换为统一的发布状态，
/// 供上层持久化层（SwiftData）消费。这里采用轮询而不是事件回调，是因为 macOS 对
/// 剪贴板变化没有稳定的高层通知 API，`changeCount` 是最可靠的跨应用信号。
final class ClipboardMonitor: ObservableObject {

    /// 是否正在监听（可用于绑定 UI）。
    @Published private(set) var isMonitoring = false

    /// 最近一次捕获的纯文本（与 `captureEventCount` 同步更新，供上层写入 SwiftData）。
    @Published private(set) var lastCapturedText: String?
    /// 最近一次捕获项的类型：`text` / `image` / `file`。
    @Published private(set) var lastCapturedType: String = "text"
    /// 最近一次捕获项的二进制负载（当前仅用于图片）。
    @Published private(set) var lastCapturedData: Data? = nil
    /// 最近一次捕获项是否命中敏感信息规则。
    @Published private(set) var lastCapturedIsSensitive: Bool = false

    /// 每次成功读取到新的纯文本时递增，便于 `onChange` 区分连续相同内容。
    @Published private(set) var captureEventCount: Int = 0

    /// 周期轮询定时器，运行在主线程 RunLoop。
    private var timer: Timer?
    /// 上一次已处理的剪贴板计数，避免重复抓取同一批内容。
    private var lastChangeCount: Int
    /// 逗号分隔的前台应用黑名单 Bundle ID。
    @AppStorage("blacklistedBundleIDs") private var blacklistedBundleIDs: String = ""
    /// 是否启用富媒体记录总开关。
    @AppStorage("enableRichMedia") private var enableRichMedia = true
    /// 是否记录图片内容。
    @AppStorage("recordImages") private var recordImages = true
    /// 是否记录文件内容。
    @AppStorage("recordFiles") private var recordFiles = true
    /// 是否暂停监听剪贴板。
    @AppStorage("isMonitoringPaused") private var isMonitoringPaused = false
    /// 是否自动移除链接中的常见追踪参数。
    @AppStorage("removeTrackingParams") private var removeTrackingParams = false
    /// 追踪参数名匹配正则。
    @AppStorage("trackingParamRegex") private var trackingParamRegex = "^(utm_.*|spm|fbclid|gclid|share_source|vd_source|si)$"
    /// 是否启用敏感信息检测。
    @AppStorage("enableSensitiveDetection") private var enableSensitiveDetection = true

    private static let linkDetector: NSDataDetector? = try? NSDataDetector(
        types: NSTextCheckingResult.CheckingType.link.rawValue
    )
    private static let sensitivePatterns: [NSRegularExpression] = [
        try! NSRegularExpression(pattern: "sk-[a-zA-Z0-9]{32,}", options: []),
        try! NSRegularExpression(pattern: "(^\\d{15}$)|(^\\d{18}$)|(^\\d{17}(\\d|X|x)$)", options: []),
        try! NSRegularExpression(pattern: "\\b\\d{16,19}\\b", options: [])
    ]

    static func playCopySoundIfEnabled() {
        let defaults = UserDefaults.standard
        guard defaults.bool(forKey: "enableCopySound") else { return }
        let soundName = defaults.string(forKey: "copySoundName") ?? "Pop"
        NSSound(named: NSSound.Name(soundName))?.play()
    }

    init() {
        lastChangeCount = NSPasteboard.general.changeCount
        startMonitoring()
    }

    deinit {
        timer?.invalidate()
    }

    /// 每 0.5 秒检查一次剪贴板 `changeCount`，变化时打印纯文本。
    func startMonitoring() {
        guard timer == nil else { return }

        lastChangeCount = NSPasteboard.general.changeCount

        let newTimer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.pollPasteboard()
        }
        RunLoop.main.add(newTimer, forMode: .common)
        timer = newTimer

        isMonitoring = true
    }

    /// 停止监听并释放轮询计时器。
    func stopMonitoring() {
        timer?.invalidate()
        timer = nil
        isMonitoring = false
    }

    /// 执行一次剪贴板轮询并提取可持久化内容。
    ///
    /// 主要步骤：
    /// - 比对 `changeCount`，确保仅处理真实变化；
    /// - 基于前台应用黑名单做来源级过滤；
    /// - 跳过内部回写标记，避免“自己写入自己再次捕获”的回环；
    /// - 按文件 > 图片 > 文本优先级进行内容解析，解决 macOS 多重表征带来的误判。
    private func pollPasteboard() {
        guard !isMonitoringPaused else { return }

        let pasteboard = NSPasteboard.general
        let current = pasteboard.changeCount
        guard current != lastChangeCount else { return }

        lastChangeCount = current

        if let frontBundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier {
            let blacklisted = blacklistedBundleIDs
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            if blacklisted.contains(frontBundleID) {
                return
            }
        }
        
        let internalMarkerType = NSPasteboard.PasteboardType("com.clipboardx.internal")
        if pasteboard.types?.contains(internalMarkerType) == true {
            return
        }

        var capturedType = "text"
        var capturedText = ""
        var capturedData: Data? = nil
        var capturedIsSensitive = false
        let types = pasteboard.types ?? []

        if types.contains(.fileURL) {
            if enableRichMedia,
               recordFiles,
               let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL],
               let firstURL = urls.first {
                capturedType = "file"
                capturedText = firstURL.path
                capturedData = nil
            } else {
                return
            }
        } else if enableRichMedia,
                  recordImages,
                  (types.contains(.tiff) || types.contains(.png)),
                  let imageData = pasteboard.data(forType: .tiff) ?? pasteboard.data(forType: .png) {
            capturedType = "image"
            capturedText = "[Image]"
            capturedData = imageData
        } else if types.contains(.string),
                  let text = pasteboard.string(forType: .string) {
            capturedType = "text"
            capturedText = removeTrackingParams ? sanitizedTrackingLinks(in: text) : text
            capturedData = nil
            if enableSensitiveDetection {
                capturedIsSensitive = isSensitiveText(capturedText)
            }
        } else {
            return
        }

        guard !capturedText.isEmpty else { return }
        lastCapturedText = capturedText
        lastCapturedType = capturedType
        lastCapturedData = capturedData
        lastCapturedIsSensitive = capturedIsSensitive
        captureEventCount += 1
    }

    private func sanitizedTrackingLinks(in text: String) -> String {
        guard let detector = Self.linkDetector else { return text }
        guard let regex = try? NSRegularExpression(pattern: trackingParamRegex, options: [.caseInsensitive]) else {
            return text
        }

        let fullRange = NSRange(text.startIndex..<text.endIndex, in: text)
        let matches = detector.matches(in: text, options: [], range: fullRange)
        guard !matches.isEmpty else { return text }

        let mutable = NSMutableString(string: text)
        for match in matches.reversed() {
            guard let originalURL = match.url else { continue }
            let cleanedURLString = sanitizedURLString(from: originalURL, regex: regex)
            if cleanedURLString != originalURL.absoluteString {
                mutable.replaceCharacters(in: match.range, with: cleanedURLString)
            }
        }
        return mutable as String
    }

    private func sanitizedURLString(from url: URL, regex: NSRegularExpression) -> String {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let queryItems = components.queryItems,
              !queryItems.isEmpty
        else {
            return url.absoluteString
        }

        let filtered = queryItems.filter { item in
            let name = item.name
            let range = NSRange(name.startIndex..<name.endIndex, in: name)
            let lower = name.lowercased()
            let builtInTrackedParams: Set<String> = [
                "spm",
                "fbclid",
                "gclid",
                "dclid",
                "msclkid",
                "mc_cid",
                "mc_eid",
                "_hsenc",
                "_hsmi",
                "igshid",
                "share_source",
                "vd_source",
                "si"
            ]
            if lower.hasPrefix("utm_") || builtInTrackedParams.contains(lower) {
                return false
            }
            return regex.firstMatch(in: name, options: [], range: range) == nil
        }

        // queryItems 为空数组时必须置为 nil，避免 URL 尾部残留 '?'
        components.queryItems = filtered.isEmpty ? nil : filtered
        return components.url?.absoluteString ?? url.absoluteString
    }

    private func isSensitiveText(_ text: String) -> Bool {
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return Self.sensitivePatterns.contains { regex in
            regex.firstMatch(in: text, options: [], range: range) != nil
        }
    }
}
