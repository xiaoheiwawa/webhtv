import Foundation
import JavaScriptCore

/// JSBridge object conforming to the global bridge protocol.
/// All method calls originate and complete on the main thread via JavaScriptCore.
final class GlobalBridge: NSObject, SpiderGlobalProtocol {

    private let context: JSContext
    private let storageGet: (String) -> String
    private let storageSet: (String, String) -> Void
    private let storageDelete: (String) -> Void

    init(context: JSContext,
         storageGet: @escaping (String) -> String,
         storageSet: @escaping (String, String) -> Void,
         storageDelete: @escaping (String) -> Void) {
        self.context = context
        self.storageGet = storageGet
        self.storageSet = storageSet
        self.storageDelete = storageDelete
    }

    func s2t(_ text: String) -> String { SimplifiedConverter.s2t(text) }
    func t2s(_ text: String) -> String { SimplifiedConverter.t2s(text) }

    func getPort() -> Int { 8080 }
    func getProxy(_ local: Bool) -> String {
        local ? "http://127.0.0.1:8080" : "http://127.0.0.1:8080/proxy"
    }
    func js2Proxy(_ dynamic: Bool, _ siteType: Int, _ siteKey: String,
                  _ url: String, _ headers: JSValue) -> String {
        let headerQuery = (headers.toString() ?? "").addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let urlQuery = url.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        return "http://127.0.0.1:8080?do=js&from=catvod&siteType=\(siteType)&siteKey=\(siteKey)&header=\(headerQuery)&url=\(urlQuery)"
    }

    func req(_ url: String, _ options: JSValue) -> JSValue {
        // Options carries { method, body, headers:{...}, time, ... }. Async callback path is separate.
        Network.request(url: url, options: options.toDictionary())
        return JSValue(newObjectIn: context)
    }

    func joinUrl(_ parent: String, _ child: String) -> String {
        guard let base = URL(string: parent), let resolved = URL(string: child, relativeTo: base) else { return child }
        return resolved.absoluteString
    }

    func md5(_ text: String) -> String { CryptoUtil.md5(text) }
    func aes(_ mode: String, _ encrypt: Bool, _ input: String, _ inBase64: Bool,
             _ key: String, _ iv: String, _ outBase64: Bool) -> String {
        CryptoUtil.aes(mode: mode, encrypt: encrypt, input: input, inBase64: inBase64,
                       key: key, iv: iv, outBase64: outBase64)
    }
    func rsa(_ mode: String, _ pub: Bool, _ encrypt: Bool, _ input: String, _ inBase64: Bool,
             _ key: String, _ outBase64: Bool) -> String {
        CryptoUtil.rsa(mode: mode, pub: pub, encrypt: encrypt, input: input, inBase64: inBase64,
                       key: key, outBase64: outBase64)
    }

    func localGet(_ rule: String, _ key: String) -> String { storageGet(cacheKey(rule, key)) }
    func localSet(_ rule: String, _ key: String, _ value: String) { storageSet(cacheKey(rule, key), value) }
    func localDelete(_ rule: String, _ key: String) { storageDelete(cacheKey(rule, key)) }

    private func cacheKey(_ rule: String, _ key: String) -> String {
        "cache_" + (rule.isEmpty ? "" : rule + "_") + key
    }
}
