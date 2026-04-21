//
//  HistoryListItemView.swift
//  ClipboardX
//
//  Created by Rain Walker on 2026/4/11.
//

import AppKit
import SwiftData
import SwiftUI

/// 剪贴板历史单条卡片视图。
///
/// 负责单条记录的展示（文本/图片/文件）、高亮样式、悬浮反馈与右键菜单动作。
/// 该视图仅处理“行级交互”，不直接参与列表层的搜索与键盘路由编排。
struct HistoryListItemView: View {
    /// 在可见列表中的位置索引（用于显示 Cmd+数字提示）。
    let index: Int
    var isFromPanel: Bool = false
    /// SwiftData 上下文，用于行级右键动作（固定/删除）持久化。
    @Environment(\.modelContext) private var modelContext
    @Environment(\.locale) private var locale
    /// 键盘导览模式绑定：用于与父视图共享高亮控制状态。
    @Binding var isKeyboardMode: Bool
    /// 鼠标悬浮是否会打断键盘高亮（用户可配置）。
    @AppStorage("hoverInterruptsKeyboard") private var hoverInterruptsKeyboard = true
    @AppStorage("timeFormat") private var timeFormat = TimeDisplayFormat.relative.rawValue
    @AppStorage("showSeconds") private var showSeconds = false
    @AppStorage("showItemTimestamp") private var showItemTimestamp = true
    @AppStorage("keepOriginalAfterTransform") private var keepOriginalAfterTransform = true
    @AppStorage("maskSensitiveContent") private var maskSensitiveContent = true
    /// 当前行是否被列表选中。
    let isSelected: Bool
    /// 当前行是否处于淡出阶段（fade 动画）。
    let isFadingOut: Bool
    /// 与列表共享的匹配几何命名空间。
    let namespace: Namespace.ID
    /// 当前行对应的剪贴板数据实体。
    let item: ClipboardItem
    /// 固定卡片高度（双列网格模式下用于统一尺寸与点击区域）。
    let fixedHeight: CGFloat?
    /// 主激活动作（粘贴并执行后续策略）。
    let onActivate: () -> Void
    /// “仅复制”动作（只写回剪贴板，不触发粘贴链路）。
    let onCopyOnly: () -> Void

    /// 鼠标是否悬浮在当前卡片上。
    @State private var isHovering = false
    @State private var thumbnail: NSImage?

    /// 卡片背景色：选中 > 悬浮 > 默认。
    private var cardBackground: Color {
        if isSelected && isKeyboardMode {
            Color.accentColor.opacity(0.12)
        } else if isHovering {
            Color.secondary.opacity(0.15)
        } else {
            Color.black.opacity(0.05)
        }
    }

    /// 卡片描边色：键盘选中或悬浮时显示强调边框。
    private var strokeColor: Color {
        if isSelected && isKeyboardMode {
            Color.accentColor.opacity(0.6)
        } else if isHovering {
            Color.accentColor.opacity(0.6)
        } else {
            Color.clear
        }
    }

    /// 轻微悬浮缩放，增强可点击感知。
    private var scale: CGFloat {
        isHovering ? 1.015 : 1.0
    }

    private var formattedCreatedAt: String {
        let format = TimeDisplayFormat(rawValue: timeFormat) ?? .relative
        switch format {
        case .relative:
            let formatter = RelativeDateTimeFormatter()
            formatter.locale = locale
            formatter.unitsStyle = .full
            return formatter.localizedString(for: item.createdAt, relativeTo: Date())
        case .absolute24:
            return absoluteTimestampString(use24Hour: true)
        case .absolute12:
            return absoluteTimestampString(use24Hour: false)
        }
    }

    private func absoluteTimestampString(use24Hour: Bool) -> String {
        let calendar = Calendar.current
        let itemDay = calendar.startOfDay(for: item.createdAt)
        let today = calendar.startOfDay(for: Date())
        let dayDistance = calendar.dateComponents([.day], from: itemDay, to: today).day ?? 999

        let timeFormatter = DateFormatter()
        timeFormatter.locale = locale
        if use24Hour {
            timeFormatter.dateFormat = showSeconds ? "HH:mm:ss" : "HH:mm"
        } else {
            timeFormatter.dateFormat = showSeconds ? "h:mm:ss a" : "h:mm a"
        }
        let timeText = timeFormatter.string(from: item.createdAt)

        if dayDistance == 0 {
            return timeText
        }
        if dayDistance == 1 {
            let prefix = locale.identifier.hasPrefix("zh") ? "昨天" : "Yesterday"
            return "\(prefix) \(timeText)"
        }
        if dayDistance == 2 {
            let prefix = locale.identifier.hasPrefix("zh") ? "前天" : "2 days ago"
            return "\(prefix) \(timeText)"
        }

        let dateFormatter = DateFormatter()
        dateFormatter.locale = locale
        dateFormatter.dateFormat = "MM-dd"
        return dateFormatter.string(from: item.createdAt)
    }

    private var localizedContentText: String {
        switch item.content {
        case "[Image]", "[图片]":
            return locale.identifier.hasPrefix("zh") ? "[图片]" : "[Image]"
        default:
            return item.content
        }
    }

    private var displayContentText: String {
        guard item.itemType == "text", item.isSensitive, maskSensitiveContent else {
            return localizedContentText
        }
        return maskedSensitiveText(item.content)
    }

    private func maskedSensitiveText(_ text: String) -> String {
        let count = text.count
        guard count > 0 else { return text }
        if count <= 4 { return String(repeating: "•", count: count) }
        let prefix = String(text.prefix(2))
        let suffix = String(text.suffix(2))
        let maskedBody = String(repeating: "•", count: max(4, count - 4))
        return "\(prefix)\(maskedBody)\(suffix)"
    }

    var body: some View {
        Button(action: onActivate) {
            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 5) {
                    if item.itemType == "image" {
                        if let thumbnail {
                            Image(nsImage: thumbnail)
                                .resizable()
                                .scaledToFit()
                                .frame(maxHeight: 120, alignment: .leading)
                                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                        } else {
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(Color.secondary.opacity(0.12))
                                .frame(height: 120)
                                .overlay {
                                    ProgressView()
                                        .controlSize(.small)
                                }
                        }
                    } else if item.itemType == "file" {
                        HStack(spacing: 6) {
                            Image(systemName: "doc.fill")
                            Text((item.content as NSString).lastPathComponent)
                                .lineLimit(2)
                                .multilineTextAlignment(.leading)
                        }
                    } else {
                        Text(displayContentText)
                            .lineLimit(3)
                            .multilineTextAlignment(.leading)
                            .textSelection(.enabled)
                    }
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 4) {
                    HStack(spacing: 6) {
                        if item.isFavorite {
                            Image(systemName: "star.fill")
                                .font(.caption2)
                                .foregroundColor(.yellow)
                        }

                        if index < 9 {
                            Text("⌘\(index + 1)")
                                .font(.caption2)
                                .foregroundStyle(.secondary.opacity(0.5))
                        }

                        if item.isPinned {
                            Image(systemName: "pin.fill")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .rotationEffect(.degrees(45))
                        }

                        if item.isSensitive {
                            Image(systemName: "lock.fill")
                                .font(.caption2)
                                .foregroundStyle(.orange)
                        }
                    }

                    if showItemTimestamp {
                        Text(formattedCreatedAt)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }
            .frame(maxWidth: .infinity, minHeight: fixedHeight, maxHeight: fixedHeight, alignment: .topLeading)
            .contentShape(Rectangle())
            .padding(12)
            .background(cardBackground)
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(strokeColor, lineWidth: 1.5)
            )
            .scaleEffect(scale)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isHovering)
            .animation(.easeOut(duration: 0.15), value: isSelected)
        }
        .buttonStyle(.plain)
        .matchedGeometryEffect(id: item.id, in: namespace)
        .transition(.opacity)
        .opacity(isFadingOut ? 0 : 1)
        .animation(.easeInOut(duration: 0.12), value: isFadingOut)
        .onHover { hovering in
            isHovering = hovering
            if hovering && hoverInterruptsKeyboard {
                isKeyboardMode = false
            }
        }
        .task(id: item.id) {
            guard item.itemType == "image" else {
                thumbnail = nil
                return
            }
            thumbnail = await ImageThumbnailManager.shared.getThumbnail(for: item, targetHeight: 120)
        }
        .contextMenu {
            Button {
                item.isPinned.toggle()
                try? modelContext.save()
            } label: {
                Label(item.isPinned ? "取消固定" : "固定在顶部", systemImage: item.isPinned ? "pin.slash" : "pin")
            }

            Button {
                item.isFavorite.toggle()
                try? modelContext.save()
            } label: {
                Label(item.isFavorite ? "取消常用" : "加入常用", systemImage: item.isFavorite ? "star.slash" : "star")
            }

            if item.itemType == "text" {
                Divider()

                Menu {
                    if let autoDecrypted = CryptoManager.autoDecrypt(item.content) {
                        Button {
                            transformAndCopy(autoDecrypted)
                        } label: {
                            Label {
                                Text("智能解密并复制")
                            } icon: {
                                Image(systemName: "wand.and.stars")
                            }
                        }

                        Divider()
                    }

                    Button {
                        guard let encoded = CryptoManager.base64Encode(item.content) else { return }
                        transformAndCopy(encoded)
                    } label: {
                        Text("Base64 编码")
                    }

                    Button {
                        guard let decoded = CryptoManager.base64Decode(item.content) else { return }
                        transformAndCopy(decoded)
                    } label: {
                        Text("Base64 解密")
                    }

                    Button {
                        guard let encoded = CryptoManager.urlEncode(item.content) else { return }
                        transformAndCopy(encoded)
                    } label: {
                        Text("URL 编码")
                    }

                    Button {
                        guard let decoded = CryptoManager.urlDecode(item.content) else { return }
                        transformAndCopy(decoded)
                    } label: {
                        Text("URL 解密")
                    }
                } label: {
                    Label {
                        Text("加密 / 解密")
                    } icon: {
                        Image(systemName: "lock.shield")
                    }
                }
            }

            Button {
                onCopyOnly()
            } label: {
                Label("仅复制", systemImage: "doc.on.doc")
            }

            Button(role: .destructive) {
                modelContext.delete(item)
                try? modelContext.save()
            } label: {
                Label("删除此记录", systemImage: "trash")
            }
        }
    }

    private func writeToPasteboard(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    private func transformAndCopy(_ text: String) {
        writeToPasteboard(text)
        guard !keepOriginalAfterTransform else { return }
        modelContext.delete(item)
        try? modelContext.save()
    }
}
