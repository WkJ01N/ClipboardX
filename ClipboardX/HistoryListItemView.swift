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
    /// 键盘导览模式绑定：用于与父视图共享高亮控制状态。
    @Binding var isKeyboardMode: Bool
    /// 鼠标悬浮是否会打断键盘高亮（用户可配置）。
    @AppStorage("hoverInterruptsKeyboard") private var hoverInterruptsKeyboard = true
    /// 当前行是否被列表选中。
    let isSelected: Bool
    /// 当前行是否处于淡出阶段（fade 动画）。
    let isFadingOut: Bool
    /// 与列表共享的匹配几何命名空间。
    let namespace: Namespace.ID
    /// 当前行对应的剪贴板数据实体。
    let item: ClipboardItem
    /// 主激活动作（粘贴并执行后续策略）。
    let onActivate: () -> Void
    /// “仅复制”动作（只写回剪贴板，不触发粘贴链路）。
    let onCopyOnly: () -> Void

    /// 鼠标是否悬浮在当前卡片上。
    @State private var isHovering = false

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

    var body: some View {
        Button(action: onActivate) {
            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 5) {
                    if item.itemType == "image",
                       let data = item.itemData,
                       let nsImage = NSImage(data: data) {
                        Image(nsImage: nsImage)
                            .resizable()
                            .scaledToFit()
                            .frame(maxHeight: 120, alignment: .leading)
                            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    } else if item.itemType == "file" {
                        HStack(spacing: 6) {
                            Image(systemName: "doc.fill")
                            Text((item.content as NSString).lastPathComponent)
                                .lineLimit(2)
                                .multilineTextAlignment(.leading)
                        }
                    } else {
                        Text(item.content)
                            .lineLimit(3)
                            .multilineTextAlignment(.leading)
                            .textSelection(.enabled)
                    }
                }

                Spacer()

                HStack(spacing: 6) {
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
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
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
        .contextMenu {
            Button {
                item.isPinned.toggle()
                try? modelContext.save()
            } label: {
                Label(item.isPinned ? "取消固定" : "固定在顶部", systemImage: item.isPinned ? "pin.slash" : "pin")
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
}
