import CryptoKit
import Foundation
import Security

enum PasswordBackupError: LocalizedError {
    case invalidEnvelope
    case invalidPassword

    var errorDescription: String? {
        switch self {
        case .invalidEnvelope: return String(localized: "备份文件格式无效")
        case .invalidPassword: return String(localized: "备份口令不正确或文件已损坏")
        }
    }
}

enum PasswordBackupCrypto {
    nonisolated static let iterations = 600_000

    nonisolated static func seal(_ payload: Data, password: String) throws -> EncryptedClipboardBackupEnvelope {
        var salt = Data(count: 16)
        let status = salt.withUnsafeMutableBytes { bytes in
            SecRandomCopyBytes(kSecRandomDefault, bytes.count, bytes.baseAddress!)
        }
        guard status == errSecSuccess else { throw PasswordBackupError.invalidEnvelope }
        let keyData = pbkdf2SHA256(password: Data(password.utf8), salt: salt, iterations: iterations, keyLength: 32)
        let box = try AES.GCM.seal(payload, using: SymmetricKey(data: keyData))
        guard let combined = box.combined else { throw PasswordBackupError.invalidEnvelope }
        return EncryptedClipboardBackupEnvelope(
            format: "ClipboardXEncryptedBackup",
            version: 2,
            kdf: "PBKDF2-HMAC-SHA256",
            iterations: iterations,
            saltBase64: salt.base64EncodedString(),
            sealedPayloadBase64: combined.base64EncodedString()
        )
    }

    nonisolated static func open(_ envelope: EncryptedClipboardBackupEnvelope, password: String) throws -> Data {
        guard envelope.format == "ClipboardXEncryptedBackup",
              envelope.version == 2,
              envelope.kdf == "PBKDF2-HMAC-SHA256",
              envelope.iterations >= 100_000,
              envelope.iterations <= 2_000_000,
              let salt = Data(base64Encoded: envelope.saltBase64),
              let combined = Data(base64Encoded: envelope.sealedPayloadBase64)
        else { throw PasswordBackupError.invalidEnvelope }
        let keyData = pbkdf2SHA256(
            password: Data(password.utf8), salt: salt,
            iterations: envelope.iterations, keyLength: 32
        )
        do {
            return try AES.GCM.open(AES.GCM.SealedBox(combined: combined), using: SymmetricKey(data: keyData))
        } catch {
            throw PasswordBackupError.invalidPassword
        }
    }

    /// RFC 8018 PBKDF2 using HMAC-SHA256. Public for deterministic test vectors.
    nonisolated static func pbkdf2SHA256(
        password: Data, salt: Data, iterations: Int, keyLength: Int
    ) -> Data {
        precondition(iterations > 0 && keyLength > 0)
        let key = SymmetricKey(data: password)
        let hashLength = 32
        let blocks = Int(ceil(Double(keyLength) / Double(hashLength)))
        var output = Data()
        for blockIndex in 1...blocks {
            var input = salt
            var bigEndian = UInt32(blockIndex).bigEndian
            withUnsafeBytes(of: &bigEndian) { input.append(contentsOf: $0) }
            var u = Data(HMAC<SHA256>.authenticationCode(for: input, using: key))
            var accumulator = u
            if iterations > 1 {
                for _ in 2...iterations {
                    u = Data(HMAC<SHA256>.authenticationCode(for: u, using: key))
                    for index in accumulator.indices { accumulator[index] ^= u[index] }
                }
            }
            output.append(accumulator)
        }
        return Data(output.prefix(keyLength))
    }
}
