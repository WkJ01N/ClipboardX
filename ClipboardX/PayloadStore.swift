import Foundation

final class PayloadStore: @unchecked Sendable {
    nonisolated static let shared = PayloadStore()

    nonisolated(unsafe) private var rootURL: URL = PayloadStore.defaultRootURL()
    nonisolated private let lock = NSLock()

    nonisolated func configure(storeURL: URL?) throws {
        let base = storeURL?.deletingLastPathComponent() ?? Self.defaultRootURL().deletingLastPathComponent()
        lock.lock()
        rootURL = base.appendingPathComponent("Payloads", isDirectory: true)
        let target = rootURL
        lock.unlock()
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
    }

    nonisolated func write(_ data: Data, id: UUID) throws -> String {
        let root = currentRootURL()
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let relativePath = "\(id.uuidString).blob"
        let destination = root.appendingPathComponent(relativePath)
        try data.write(to: destination, options: [.atomic])
        return relativePath
    }

    nonisolated func read(relativePath: String) throws -> Data {
        try Data(contentsOf: currentRootURL().appendingPathComponent(relativePath), options: [.mappedIfSafe])
    }

    nonisolated func remove(relativePath: String?) {
        guard let relativePath, !relativePath.isEmpty else { return }
        try? FileManager.default.removeItem(at: currentRootURL().appendingPathComponent(relativePath))
    }

    nonisolated func removeOrphans(keeping relativePaths: Set<String>) -> Int {
        let root = currentRootURL()
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return 0 }
        var count = 0
        for url in urls where !relativePaths.contains(url.lastPathComponent) {
            if (try? FileManager.default.removeItem(at: url)) != nil { count += 1 }
        }
        return count
    }

    nonisolated func rootDirectoryURL() -> URL { currentRootURL() }

    nonisolated private func currentRootURL() -> URL {
        lock.lock()
        defer { lock.unlock() }
        return rootURL
    }

    nonisolated private static func defaultRootURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        return base.appendingPathComponent("ClipboardX/Payloads", isDirectory: true)
    }
}
