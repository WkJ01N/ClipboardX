import AppKit
import Foundation

enum ClipboardWritePayload: Equatable {
    case text(String)
    case image(Data, typeIdentifier: String)
    case files([String])
}

enum ClipboardWriteError: LocalizedError, Equatable {
    case decryptionFailed
    case imagePayloadMissing
    case filesMissing(existing: [String], missing: [String])
    case pasteboardRejectedContent

    var errorDescription: String? {
        switch self {
        case .decryptionFailed:
            return String(localized: "无法解密此敏感记录，未执行复制或粘贴。")
        case .imagePayloadMissing:
            return String(localized: "图片数据已损坏或丢失，未执行粘贴。")
        case .filesMissing(let existing, let missing):
            if existing.isEmpty {
                return String(localized: "记录中的文件均已移动或删除。")
            }
            return String(localized: "有 \(missing.count) 个文件已移动或删除。")
        case .pasteboardRejectedContent:
            return String(localized: "无法将内容写入系统剪贴板。")
        }
    }
}

@MainActor
enum ClipboardWriter {
    private static let internalMarkerType = NSPasteboard.PasteboardType("com.clipboardx.internal")

    static func prepare(
        item: ClipboardItem,
        forcePlainText: Bool = false,
        allowPartialFiles: Bool = false,
        fileExists: (String) -> Bool = FileManager.default.fileExists(atPath:)
    ) throws -> ClipboardWritePayload {
        if item.kind == .image, !forcePlainText {
            guard let data = try ClipboardContentResolver.resolvedImageData(for: item) else {
                throw ClipboardWriteError.imagePayloadMissing
            }
            return .image(
                data,
                typeIdentifier: item.payloadTypeIdentifier ?? NSPasteboard.PasteboardType.tiff.rawValue
            )
        }

        if item.kind == .file, !forcePlainText {
            let existing = item.filePaths.filter(fileExists)
            let missing = item.filePaths.filter { !fileExists($0) }
            if !missing.isEmpty, !allowPartialFiles || existing.isEmpty {
                throw ClipboardWriteError.filesMissing(existing: existing, missing: missing)
            }
            guard !existing.isEmpty else {
                throw ClipboardWriteError.filesMissing(existing: [], missing: item.filePaths)
            }
            return .files(existing)
        }

        return .text(try ClipboardContentResolver.resolvedText(for: item))
    }

    static func write(_ payload: ClipboardWritePayload, to pasteboard: NSPasteboard = .general) throws {
        pasteboard.clearContents()
        let accepted: Bool
        switch payload {
        case .text(let text):
            accepted = pasteboard.setString(text, forType: .string)
        case .image(let data, let typeIdentifier):
            accepted = pasteboard.setData(data, forType: NSPasteboard.PasteboardType(typeIdentifier))
        case .files(let paths):
            accepted = pasteboard.writeObjects(paths.map { URL(fileURLWithPath: $0) as NSURL })
        }
        guard accepted else { throw ClipboardWriteError.pasteboardRejectedContent }
        pasteboard.setString("true", forType: internalMarkerType)
    }
}
