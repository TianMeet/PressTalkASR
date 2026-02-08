import Foundation
import CryptoKit

enum APIKeyFingerprint {
    static func masked(key: String) -> String {
        _ = key
        return "••••••••••••••••"
    }

    static func fingerprint(key: String, salt: Data, length: Int = 10) -> String {
        var input = Data()
        input.append(salt)
        input.append(Data(key.utf8))

        let digest = SHA256.hash(data: input)
        let hex = digest.compactMap { String(format: "%02x", $0) }.joined()
        return String(hex.prefix(max(8, min(12, length))))
    }

    static func validationError(for key: String) -> String? {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "请输入 API Key。" }
        guard trimmed.hasPrefix("sk-") else { return "Key 格式看起来不正确：应以 sk- 开头。" }
        guard trimmed.count >= 20 else { return "Key 长度过短，请检查是否粘贴完整。" }
        return nil
    }
}
