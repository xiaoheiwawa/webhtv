import Foundation
import CommonCrypto
import CryptoKit

enum CryptoUtil {
    static func md5(_ text: String) -> String {
        guard let data = text.data(using: .utf8) else { return "" }
        var digest = [UInt8](repeating: 0, count: Int(CC_MD5_DIGEST_LENGTH))
        data.withUnsafeBytes { buf in
            _ = CC_MD5(buf.baseAddress, CC_LONG(data.count), &digest)
        }
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    static func aes(mode: String, encrypt: Bool, input: String, inBase64: Bool,
                    key: String, iv: String, outBase64: Bool) -> String {
        // Milestone: AES-ECB/CBC via CommonCrypto, decoding key/iv from base64 or utf8 raw.
        return ""
    }

    static func rsa(mode: String, pub: Bool, encrypt: Bool, input: String, inBase64: Bool,
                    key: String, outBase64: Bool) -> String {
        // Milestone: RSA via Security framework or OpenSSL.
        return ""
    }
}

extension String {
    var base64DecodedData: Data? { Data(base64Encoded: self) }
    var base64Encoded: String { Data(utf8).base64EncodedString() }
}
