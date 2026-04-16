//
//  ImageThumbnailManager.swift
//  ClipboardX
//
//  Created by Codex on 2026/4/16.
//

import AppKit
import Foundation
import ImageIO

actor ImageThumbnailManager {
    static let shared = ImageThumbnailManager()

    private let cache = NSCache<NSUUID, NSImage>()

    private init() {
        cache.countLimit = 300
    }

    func getThumbnail(for item: ClipboardItem, targetHeight: CGFloat = 120) async -> NSImage? {
        let cacheKey = item.id as NSUUID
        if let cached = cache.object(forKey: cacheKey) {
            return cached
        }

        guard item.itemType == "image", let data = item.itemData else {
            return nil
        }

        let maxPixelSize = max(Int(targetHeight * 2.5), 300)

        let thumbnail = await Task.detached(priority: .utility) { () -> NSImage? in
            let options: [CFString: Any] = [
                kCGImageSourceShouldCache: false
            ]
            guard let source = CGImageSourceCreateWithData(data as CFData, options as CFDictionary) else {
                return nil
            }

            let downsampleOptions: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceShouldCacheImmediately: false,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
            ]
            guard let cgImage = CGImageSourceCreateThumbnailAtIndex(
                source,
                0,
                downsampleOptions as CFDictionary
            ) else {
                return nil
            }

            return NSImage(
                cgImage: cgImage,
                size: NSSize(width: cgImage.width, height: cgImage.height)
            )
        }.value

        guard let thumbnail else {
            return nil
        }

        cache.setObject(thumbnail, forKey: cacheKey)
        return thumbnail
    }
}
