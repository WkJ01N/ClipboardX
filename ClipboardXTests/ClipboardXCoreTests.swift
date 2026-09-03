import CryptoKit
import SwiftData
import XCTest
@testable import ClipboardX

final class ClipboardXCoreTests: XCTestCase {
    func testAutomaticPasteUsesAccessibilityTrustWithoutCGEventPreflight() {
        XCTAssertTrue(PermissionStatusService.canPostKeyboardEvents(accessibilityTrusted: true))
        XCTAssertFalse(PermissionStatusService.canPostKeyboardEvents(accessibilityTrusted: false))
    }

    @MainActor
    func testPasteCoordinatorCapturesExternalTargetAndClearsInvalidTarget() {
        let coordinator = PasteCoordinator(observeWorkspace: false, dependencies: pasteDependencies())
        let external = PasteApplicationState(processIdentifier: 123, bundleIdentifier: "com.example.target", isTerminated: false)
        let session = coordinator.beginSession(frontmostApplication: external, ownPID: 999, now: Date())
        XCTAssertEqual(session?.processIdentifier, 123)
        XCTAssertEqual(session?.bundleIdentifier, "com.example.target")

        coordinator.beginSession(
            frontmostApplication: PasteApplicationState(processIdentifier: 999, bundleIdentifier: "com.wkj01n.ClipboardX", isTerminated: false),
            ownPID: 999,
            now: Date().addingTimeInterval(2)
        )
        XCTAssertNil(coordinator.targetPID)
    }

    @MainActor
    func testPasteCoordinatorUsesOnlyImmediatePrePanelExternalTarget() {
        let ownPID = ProcessInfo.processInfo.processIdentifier
        let now = Date()
        let coordinator = PasteCoordinator(observeWorkspace: false, dependencies: pasteDependencies())
        coordinator.noteApplicationActivated(
            PasteApplicationState(processIdentifier: 123, bundleIdentifier: "com.example.target", isTerminated: false),
            at: now.addingTimeInterval(-10)
        )
        coordinator.noteApplicationActivated(
            PasteApplicationState(processIdentifier: ownPID, bundleIdentifier: "com.wkj01n.ClipboardX", isTerminated: false),
            at: now
        )
        XCTAssertEqual(
            coordinator.beginSession(
                frontmostApplication: PasteApplicationState(
                    processIdentifier: ownPID,
                    bundleIdentifier: "com.wkj01n.ClipboardX",
                    isTerminated: false
                ),
                ownPID: ownPID,
                now: now.addingTimeInterval(0.5)
            )?.processIdentifier,
            123
        )
        XCTAssertNil(coordinator.beginSession(
            frontmostApplication: PasteApplicationState(
                processIdentifier: ownPID,
                bundleIdentifier: "com.wkj01n.ClipboardX",
                isTerminated: false
            ),
            ownPID: ownPID,
            now: now.addingTimeInterval(2)
        ))
    }

    @MainActor
    func testPasteCoordinatorInvalidatesOldAndTerminatedSessions() {
        let coordinator = PasteCoordinator(observeWorkspace: false, dependencies: pasteDependencies())
        let target = PasteApplicationState(processIdentifier: 123, bundleIdentifier: "com.example.target", isTerminated: false)
        let first = coordinator.beginSession(frontmostApplication: target, ownPID: 999, now: Date())
        let second = coordinator.beginSession(frontmostApplication: target, ownPID: 999, now: Date())
        XCTAssertNotEqual(first?.generation, second?.generation)
        coordinator.noteApplicationTerminated(processIdentifier: 123)
        XCTAssertNil(coordinator.targetSession)
    }

    @MainActor
    func testPasteCoordinatorReportsPermissionAndActivationResults() async {
        let target = PasteApplicationState(processIdentifier: 123, bundleIdentifier: "com.example.target", isTerminated: false)
        let denied = PasteCoordinator(
            observeWorkspace: false,
            dependencies: pasteDependencies(accessibilityTrusted: false, state: target, frontmost: target)
        )
        denied.beginSession(frontmostApplication: target, ownPID: 999, now: Date())
        let deniedResult = await denied.pasteIntoCapturedTarget()
        XCTAssertEqual(deniedResult, .permissionDenied)

        let activationFailed = PasteCoordinator(
            observeWorkspace: false,
            dependencies: pasteDependencies(state: target, frontmost: target, activate: false)
        )
        activationFailed.beginSession(frontmostApplication: target, ownPID: 999, now: Date())
        let activationResult = await activationFailed.pasteIntoCapturedTarget()
        XCTAssertEqual(activationResult, .targetActivationFailed)

        let timedOut = PasteCoordinator(
            observeWorkspace: false,
            dependencies: pasteDependencies(
                state: target,
                frontmost: PasteApplicationState(processIdentifier: 456, bundleIdentifier: "com.example.other", isTerminated: false)
            )
        )
        timedOut.beginSession(frontmostApplication: target, ownPID: 999, now: Date())
        let timeoutResult = await timedOut.pasteIntoCapturedTarget()
        XCTAssertEqual(timeoutResult, .targetActivationTimedOut)
    }

    @MainActor
    func testPasteCoordinatorPostsOnlyAfterTargetIsFrontmost() async {
        let target = PasteApplicationState(processIdentifier: 123, bundleIdentifier: "com.example.target", isTerminated: false)
        var posted = false
        var dependencies = pasteDependencies(state: target, frontmost: target)
        dependencies.postPaste = {
            posted = true
            return true
        }
        let coordinator = PasteCoordinator(observeWorkspace: false, dependencies: dependencies)
        coordinator.beginSession(frontmostApplication: target, ownPID: 999, now: Date())
        let result = await coordinator.pasteIntoCapturedTarget()
        XCTAssertEqual(result, .eventsPosted)
        XCTAssertTrue(posted)
        XCTAssertNil(coordinator.targetSession)
    }

    @MainActor
    func testClosingLastWindowDoesNotTerminateApplication() {
        XCTAssertFalse(ClipboardXApplicationDelegate().applicationShouldTerminateAfterLastWindowClosed(.shared))
    }

    @MainActor
    private func pasteDependencies(
        accessibilityTrusted: Bool = true,
        state: PasteApplicationState? = nil,
        frontmost: PasteApplicationState? = nil,
        activate: Bool = true
    ) -> PasteCoordinatorDependencies {
        PasteCoordinatorDependencies(
            accessibilityTrusted: { accessibilityTrusted },
            frontmostApplication: { frontmost },
            applicationState: { _ in state },
            activate: { _ in activate },
            postPaste: { true },
            sleep: { _ in }
        )
    }

    @MainActor
    func testClipboardWriterRejectsMissingImagePayload() {
        let item = ClipboardItem(content: "[Image]", itemType: ClipboardItemKind.image.rawValue)
        XCTAssertThrowsError(try ClipboardWriter.prepare(item: item)) { error in
            XCTAssertEqual(error as? ClipboardWriteError, .imagePayloadMissing)
        }
    }

    @MainActor
    func testClipboardWriterRejectsUndecryptableSensitiveText() {
        let item = ClipboardItem(content: "", isSensitive: true)
        XCTAssertThrowsError(try ClipboardWriter.prepare(item: item)) { error in
            XCTAssertEqual(error as? ClipboardWriteError, .decryptionFailed)
        }
    }

    @MainActor
    func testClipboardWriterReportsPartialAndFullyMissingFiles() throws {
        let item = ClipboardItem(content: "/exists", itemType: ClipboardItemKind.file.rawValue,
                                 filePaths: ["/exists", "/missing"])
        XCTAssertThrowsError(try ClipboardWriter.prepare(item: item, fileExists: { $0 == "/exists" })) { error in
            XCTAssertEqual(error as? ClipboardWriteError,
                           .filesMissing(existing: ["/exists"], missing: ["/missing"]))
        }
        XCTAssertEqual(
            try ClipboardWriter.prepare(item: item, allowPartialFiles: true, fileExists: { $0 == "/exists" }),
            .files(["/exists"])
        )

        let missing = ClipboardItem(content: "/gone", itemType: ClipboardItemKind.file.rawValue,
                                    filePaths: ["/gone"])
        XCTAssertThrowsError(try ClipboardWriter.prepare(item: missing, allowPartialFiles: true, fileExists: { _ in false }))
    }

    func testHistoryOrderingRespectsPinnedGroups() {
        struct Entry { let id: UUID; let pinned: Bool }
        let pinnedA = Entry(id: UUID(), pinned: true)
        let pinnedB = Entry(id: UUID(), pinned: true)
        let regularA = Entry(id: UUID(), pinned: false)
        let regularB = Entry(id: UUID(), pinned: false)
        let entries = [pinnedA, pinnedB, regularA, regularB]
        XCTAssertTrue(HistoryOrdering.isFirstInGroup(pinnedA, in: entries, id: \.id, isPinned: \.pinned))
        XCTAssertFalse(HistoryOrdering.isFirstInGroup(pinnedB, in: entries, id: \.id, isPinned: \.pinned))
        XCTAssertTrue(HistoryOrdering.isFirstInGroup(regularA, in: entries, id: \.id, isPinned: \.pinned))
        XCTAssertFalse(HistoryOrdering.isFirstInGroup(regularB, in: entries, id: \.id, isPinned: \.pinned))
    }

    func testReorderAnimationPhasesKeepItemHiddenUntilIdle() {
        let id = UUID()
        XCTAssertNil(HistoryReorderAnimationPhase.idle.hiddenItemID)
        XCTAssertEqual(HistoryReorderAnimationPhase.fadingOut(id).hiddenItemID, id)
        XCTAssertEqual(HistoryReorderAnimationPhase.reordering(id).hiddenItemID, id)
        XCTAssertEqual(HistoryReorderAnimationPhase.fadingIn(id).hiddenItemID, id)
    }

    func testPausedClipboardChangesAreConsumedWithoutCapturingAfterResume() {
        var gate = ClipboardChangeGate(lastChangeCount: 10)
        XCTAssertFalse(gate.consume(11, paused: true))
        XCTAssertFalse(gate.consume(11, paused: false))
        XCTAssertTrue(gate.consume(12, paused: false))
    }

    func testLuhnValidation() {
        XCTAssertTrue(SensitiveTextDetector.luhnIsValid("4242424242424242"))
        XCTAssertFalse(SensitiveTextDetector.luhnIsValid("4242424242424241"))
    }

    func testChineseIdentityChecksum() {
        XCTAssertTrue(SensitiveTextDetector.isValidChineseIdentityNumber("11010519491231002X"))
        XCTAssertFalse(SensitiveTextDetector.isValidChineseIdentityNumber("110105194912310021"))
    }

    func testSensitiveDetectionAvoidsArbitraryLongNumbers() {
        XCTAssertFalse(SensitiveTextDetector.isSensitive("order 1234567890123456"))
        XCTAssertTrue(SensitiveTextDetector.isSensitive("token sk-proj-abcdefghijklmnopqrstuvwxyz123456"))
    }

    func testPBKDF2SHA256Vector() {
        let derived = PasswordBackupCrypto.pbkdf2SHA256(
            password: Data("password".utf8),
            salt: Data("salt".utf8),
            iterations: 1,
            keyLength: 32
        )
        XCTAssertEqual(derived.map { String(format: "%02x", $0) }.joined(),
                       "120fb6cffcf8b32c43e7225256c4f837a86548c92ccc35480805987cb70be17b")
    }

    func testEncryptedBackupRejectsWrongPassword() throws {
        var salt = Data(repeating: 7, count: 16)
        let key = PasswordBackupCrypto.pbkdf2SHA256(
            password: Data("correct horse".utf8), salt: salt, iterations: 100_000, keyLength: 32
        )
        let combined = try XCTUnwrap(AES.GCM.seal(Data("payload".utf8), using: SymmetricKey(data: key)).combined)
        let envelope = EncryptedClipboardBackupEnvelope(
            format: "ClipboardXEncryptedBackup", version: 2, kdf: "PBKDF2-HMAC-SHA256",
            iterations: 100_000, saltBase64: salt.base64EncodedString(),
            sealedPayloadBase64: combined.base64EncodedString()
        )
        XCTAssertThrowsError(try PasswordBackupCrypto.open(envelope, password: "wrong password"))
        salt.removeAll()
    }

    @MainActor
    func testV1StoreMigratesToV2() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let storeURL = directory.appendingPathComponent("migration.store")

        do {
            let v1 = try ModelContainer(
                for: ClipboardSchemaV1.ClipboardItem.self,
                configurations: ModelConfiguration(url: storeURL)
            )
            let item = ClipboardSchemaV1.ClipboardItem(content: "keep me", isPinned: true, isFavorite: true)
            v1.mainContext.insert(item)
            try v1.mainContext.save()
        }

        let v2 = try ModelContainer(
            for: ClipboardItem.self,
            migrationPlan: ClipboardMigrationPlan.self,
            configurations: ModelConfiguration(url: storeURL)
        )
        let migrated = try XCTUnwrap(try v2.mainContext.fetch(FetchDescriptor<ClipboardItem>()).first)
        XCTAssertEqual(migrated.content, "keep me")
        XCTAssertTrue(migrated.isPinned)
        XCTAssertTrue(migrated.isFavorite)
        XCTAssertNil(migrated.sourceBundleIdentifier)
    }

    @MainActor
    func testUnversionedRecoveryRebuildPreservesLegacyFields() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let storeURL = directory.appendingPathComponent("legacy.store")
        do {
            let legacy = try ModelContainer(
                for: ClipboardSchemaV1.ClipboardItem.self,
                configurations: ModelConfiguration(url: storeURL)
            )
            legacy.mainContext.insert(ClipboardSchemaV1.ClipboardItem(
                content: "legacy", createdAt: Date(timeIntervalSince1970: 123),
                isPinned: true, isFavorite: true
            ))
            try legacy.mainContext.save()
        }

        let rebuilt = try StoreRecoveryManager.rebuildUnversionedStore(at: storeURL)
        let item = try XCTUnwrap(try rebuilt.mainContext.fetch(FetchDescriptor<ClipboardItem>()).first)
        XCTAssertEqual(item.content, "legacy")
        XCTAssertEqual(item.createdAt, Date(timeIntervalSince1970: 123))
        XCTAssertTrue(item.isPinned)
        XCTAssertTrue(item.isFavorite)
        XCTAssertTrue(FileManager.default.fileExists(atPath: directory.appendingPathComponent("RecoverySnapshots").path))
    }

    func testPayloadStoreRemovesOrphans() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let storeURL = directory.appendingPathComponent("default.store")
        try PayloadStore.shared.configure(storeURL: storeURL)
        let kept = try PayloadStore.shared.write(Data("keep".utf8), id: UUID())
        _ = try PayloadStore.shared.write(Data("remove".utf8), id: UUID())
        XCTAssertEqual(PayloadStore.shared.removeOrphans(keeping: [kept]), 1)
        XCTAssertNotNil(try? PayloadStore.shared.read(relativePath: kept))
    }
}
