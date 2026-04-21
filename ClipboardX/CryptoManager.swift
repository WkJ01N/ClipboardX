import Foundation

struct CryptoManager {
    static func base64Encode(_ text: String) -> String? {
        guard let data = text.data(using: .utf8) else { return nil }
        return data.base64EncodedString()
    }

    static func base64Decode(_ text: String) -> String? {
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return nil }
        guard let data = Data(base64Encoded: normalized, options: [.ignoreUnknownCharacters]) else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    static func urlEncode(_ text: String) -> String? {
        text.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)
    }

    static func urlDecode(_ text: String) -> String? {
        text.removingPercentEncoding
    }

    static func autoDecrypt(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if trimmed.contains("%"),
           let urlDecoded = urlDecode(trimmed),
           urlDecoded != trimmed {
            return urlDecoded
        }

        let compact = trimmed.replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)
        let isBase64Charset = compact.range(
            of: "^[A-Za-z0-9+/]+={0,2}$",
            options: .regularExpression
        ) != nil
        if (compact.hasSuffix("=") || isBase64Charset),
           let decoded = base64Decode(compact),
           decoded != trimmed {
            return decoded
        }

        return nil
    }
}
