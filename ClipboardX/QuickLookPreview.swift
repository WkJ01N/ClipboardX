//
//  QuickLookPreview.swift
//  ClipboardX
//
//  Created by Rain Walker on 2026/4/11.
//

import SwiftUI

/// 历史项的全屏快速预览层（Quick Look 风格）。
///
/// 用于在不立即粘贴的前提下查看完整内容，避免长文本/大图在列表卡片中被截断。
struct QuickLookPreview: View {
    /// 需要预览的历史项。
    let item: ClipboardItem
    /// 关闭预览层回调。
    let onClose: () -> Void
    @State private var previewImage: NSImage?

    var body: some View {
        ZStack {
            Color.black.opacity(0.4)
                .background(.ultraThinMaterial)
                .ignoresSafeArea()
                .onTapGesture {
                    onClose()
                }

            Group {
                if item.itemType == "image", let previewImage {
                    Image(nsImage: previewImage)
                        .resizable()
                        .scaledToFit()
                        .padding(20)
                        .shadow(radius: 12)
                } else if item.itemType == "file" {
                    VStack(spacing: 12) {
                        Image(systemName: "doc.fill")
                            .font(.system(size: 72))
                        Text(item.filePaths.joined(separator: "\n"))
                            .multilineTextAlignment(.center)
                            .textSelection(.enabled)
                    }
                    .padding(24)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .padding(24)
                } else {
                    ScrollView {
                        Text(ClipboardContentResolver.text(for: item))
                            .font(.body)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                            .padding(20)
                    }
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .padding(24)
                }
            }
            .onTapGesture { }
        }
        .task(id: item.id) {
            guard item.itemType == "image",
                  let data = ClipboardContentResolver.imageData(for: item)
            else {
                previewImage = nil
                return
            }
            previewImage = NSImage(data: data)
        }
    }
}
