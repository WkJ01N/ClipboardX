import CryptoKit
import Foundation
import Security

enum SensitiveDataError: LocalizedError {
    case keychain(OSStatus)
    case invalidCiphertext

    var errorDescription: String? {
        switch self {
        case .keychain(let status): return "Keychain error (\(status))"
        case .invalidCiphertext: return "Sensitive record could not be decrypted"
        }
    }
}

struct SensitiveDataService: Sendable {
    static let shared = SensitiveDataService()
    private static let service = "com.wkj01n.ClipboardX.sensitive-data"
    private static let account = "local-aes-gcm-key-v1"

    func encrypt(_ text: String) throws -> Data {
        let key = try loadOrCreateKey()
        guard let combined = try AES.GCM.seal(Data(text.utf8), using: key).combined else {
            throw SensitiveDataError.invalidCiphertext
        }
        return combined
    }

    func decrypt(_ data: Data) throws -> String {
        let key = try loadOrCreateKey()
        let box = try AES.GCM.SealedBox(combined: data)
        let clear = try AES.GCM.open(box, using: key)
        guard let text = String(data: clear, encoding: .utf8) else {
            throw SensitiveDataError.invalidCiphertext
        }
        return text
    }

    private func loadOrCreateKey() throws -> SymmetricKey {
        let baseQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
            kSecAttrAccount as String: Self.account
        ]
        var readQuery = baseQuery
        readQuery[kSecReturnData as String] = true
        readQuery[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(readQuery as CFDictionary, &result)
        if status == errSecSuccess, let data = result as? Data {
            return SymmetricKey(data: data)
        }
        guard status == errSecItemNotFound else { throw SensitiveDataError.keychain(status) }

        let key = SymmetricKey(size: .bits256)
        let data = key.withUnsafeBytes { Data($0) }
        var addQuery = baseQuery
        addQuery[kSecValueData as String] = data
        addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
        guard addStatus == errSecSuccess || addStatus == errSecDuplicateItem else {
            throw SensitiveDataError.keychain(addStatus)
        }
        if addStatus == errSecDuplicateItem { return try loadOrCreateKey() }
        return key
    }
}

enum SensitiveTextDetector {
    private static let secretPatterns: [NSRegularExpression] = [
        try! NSRegularExpression(pattern: "\\b(?:sk|rk|pk)-(?:proj-)?[A-Za-z0-9_-]{20,}\\b", options: [.caseInsensitive]),
        try! NSRegularExpression(pattern: "\\bAKIA[0-9A-Z]{16}\\b"),
        try! NSRegularExpression(pattern: "-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----")
    ]

    static func isSensitive(_ text: String) -> Bool {
        let fullRange = NSRange(text.startIndex..<text.endIndex, in: text)
        if secretPatterns.contains(where: { $0.firstMatch(in: text, range: fullRange) != nil }) { return true }
        let digits = text.filter(\.isNumber)
        if isValidChineseIdentityNumber(text) { return true }
        if (13...19).contains(digits.count), luhnIsValid(digits) { return true }
        return false
    }

    static func luhnIsValid(_ digits: String) -> Bool {
        guard digits.count >= 13, digits.allSatisfy(\.isNumber) else { return false }
        let values = digits.compactMap(\.wholeNumberValue).reversed()
        let sum = values.enumerated().reduce(0) { result, entry in
            let (offset, value) = entry
            if offset.isMultiple(of: 2) { return result + value }
            let doubled = value * 2
            return result + (doubled > 9 ? doubled - 9 : doubled)
        }
        return sum.isMultiple(of: 10)
    }

    static func isValidChineseIdentityNumber(_ raw: String) -> Bool {
        let normalized = raw.uppercased().filter { $0.isNumber || $0 == "X" }
        guard normalized.count == 18 else { return false }
        let chars = Array(normalized)
        guard chars.prefix(17).allSatisfy({ $0.isNumber }) else { return false }
        let weights = [7, 9, 10, 5, 8, 4, 2, 1, 6, 3, 7, 9, 10, 5, 8, 4, 2]
        let checks = Array("10X98765432")
        let sum = zip(chars.prefix(17), weights).reduce(0) { $0 + (($1.0.wholeNumberValue ?? 0) * $1.1) }
        return chars[17] == checks[sum % 11]
    }
}
