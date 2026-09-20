import Foundation
import JavaScriptCore

/// Native bridge injected into the JS runtime.
///
/// Mirrors Android `quickjs/.../method/Global.java` and `Local.java`. Provides:
///   - global `req`/`http` and `console`, `setTimeout`
///   - global object named `native` with `s2t/t2s/getPort/getProxy/js2Proxy/req/joinUrl/md5/aes/rsa`
///   - local cache (`native.localGet/localSet/localDelete`) via `UserDefaults`
final class GlobalBridge: NSObject {

    private unowned var context: JSContext
    private var nextTimerID = 1

    init(context: JSContext) {
        self.context = context
    }

    func install() {
        installNative()
        installConsole()
        installGlobals()
    }

    // MARK: - native

    private func installNative() {
        let ctx = context
        let native = ctx.evaluateScript("({})")
        guard let native else { return }

        let set: (String, Any) -> Void = { key, obj in
            native.setObject(obj, forKeyedSubscript: key as NSString)
        }

        set("s2t") { (text: String) -> String in SimplifiedConverter.s2t(text) }
        set("t2s") { (text: String) -> String in SimplifiedConverter.t2s(text) }
        set("getPort") { () -> Int in 8080 }
        set("getProxy") { (local: Bool) -> String in Self.proxyURL(local: local) }
        set("js2Proxy") { (dynamic: Bool, siteType: Int, siteKey: String, url: String, headers: JSValue) -> String in
            Self.js2Proxy(dynamic: dynamic, siteType: siteType, siteKey: siteKey, url: url, headers: headers)
        }
        set("req") { (url: String, options: JSValue) -> JSValue in
            Self.dispatch(http: url, options: options, context: ctx)
        }
        set("joinUrl") { (parent: String, child: String) -> String in
            guard let base = URL(string: parent), let resolved = URL(string: child, relativeTo: base) else { return child }
            return resolved.absoluteString
        }
        set("md5") { (text: String) -> String in CryptoUtil.md5(text) }
        set("aes") { (mode: String, encrypt: Bool, input: String, inBase64: Bool, key: String, iv: String, outBase64: Bool) -> String in
            CryptoUtil.aes(mode: mode, encrypt: encrypt, input: input, inBase64: inBase64, key: key, iv: iv, outBase64: outBase64)
        }
        set("rsa") { (mode: String, pub: Bool, encrypt: Bool, input: String, inBase64: Bool, key: String, outBase64: Bool) -> String in
            CryptoUtil.rsa(mode: mode, pub: pub, encrypt: encrypt, input: input, inBase64: inBase64, key: key, outBase64: outBase64)
        }
        set("localGet") { (rule: String, key: String) -> String in Self.cacheGet(rule, key) }
        set("localSet") { (rule: String, key: String, value: String) in Self.cacheSet(rule, key, value: value) }
        set("localDelete") { (rule: String, key: String) in Self.cacheDelete(rule, key) }

        ctx.globalObject.setObject(native, forKeyedSubscript: "native" as NSString)
    }

    // MARK: - console & globals

    private func installConsole() {
        let ctx = context
        let console = ctx.evaluateScript("({})")
        guard let console else { return }
        let log: @convention(block) (Any) -> Void = { obj in
            NSLog("[JSLog] %@", "\(obj)")
        }
        console.setObject(log, forKeyedSubscript: "log" as NSString)
        console.setObject(log, forKeyedSubscript: "error" as NSString)
        console.setObject(log, forKeyedSubscript: "warn" as NSString)
        ctx.globalObject.setObject(console, forKeyedSubscript: "console" as NSString)
    }

    private func installGlobals() {
        let ctx = context
        // global `req(url, options)` -> synchronous response (used by http.js `async:false`)
        let req: @convention(block) (String, JSValue) -> JSValue = { url, options in
            Self.dispatch(http: url, options: options, context: ctx)
        }
        ctx.globalObject.setObject(req, forKeyedSubscript: "req" as NSString)
        ctx.globalObject.setObject(req, forKeyedSubscript: "http" as NSString)

        // setTimeout
        let timeout: @convention(block) (JSValue, Double) -> Void = { fn, delay in
            let timer = Timer(timeInterval: max(delay, 0) / 1000.0, repeats: false) { _ in
                fn.call(withArguments: [])
            }
            RunLoop.main.add(timer, forMode: .common)
        }
        ctx.globalObject.setObject(timeout, forKeyedSubscript: "setTimeout" as NSString)
    }

    // MARK: - HTTP dispatch

    /// Route a JS http call. If `options.complete` is set, call it asynchronously with the response;
    /// otherwise return the response JS object synchronously.
    static func dispatch(http url: String, options: JSValue, context ctx: JSContext) -> JSValue {
        let optionsDict = options.toDictionary()
        let method = (optionsDict["method"] as? String) ?? "GET"
        let headers = (optionsDict["headers"] as? [String: String]) ?? [:]
        let body = (optionsDict["body"] as? String)?.data(using: .utf8)
        let timeout = (optionsDict["time"] as? Double) ?? 0

        let complete = options.objectForKeyedSubscript("complete")
        let isAsync = complete != nil && !complete.isUndefined

        if isAsync {
            Network.async(url: url, method: method, headers: headers, body: body) { res in
                DispatchQueue.main.async {
                    complete.call(withArguments: [Self.buildResponse(res, context: ctx)])
                }
            }
            return JSValue(undefinedIn: ctx)
        } else {
            let res = Network.sync(url: url, method: method, headers: headers, body: body)
            return Self.buildResponse(res, context: ctx)
        }
    }

    private static func buildResponse(_ res: HTTPResponse, context ctx: JSContext) -> JSValue {
        let obj = ctx.evaluateScript("({})")
        obj?.setObject(res.code, forKeyedSubscript: "code" as NSString)
        obj?.setObject(res.status, forKeyedSubscript: "status" as NSString)
        obj?.setObject(res.content, forKeyedSubscript: "content" as NSString)
        obj?.setObject(res.headers, forKeyedSubscript: "headers" as NSString)
        return obj ?? JSValue(newObjectIn: ctx)
    }

    // MARK: - Local cache (UserDefaults)

    private static func cacheKey(_ s: String, _ s2: String) -> String {
        "cache_" + (s.isEmpty ? "" : s + "_") + s2
    }
    private static func cacheGet(_ rule: String, _ key: String) -> String {
        UserDefaults.standard.string(forKey: cacheKey(rule, key)) ?? ""
    }
    private static func cacheSet(_ rule: String, _ key: String, value: String) {
        UserDefaults.standard.set(value, forKey: cacheKey(rule, key))
    }
    private static func cacheDelete(_ rule: String, _ key: String) {
        UserDefaults.standard.removeObject(forKey: cacheKey(rule, key))
    }

    private static func proxyURL(local: Bool) -> String {
        local ? "http://127.0.0.1:8080" : "http://127.0.0.1:8080/proxy"
    }
    private static func js2Proxy(dynamic: Bool, siteType: Int, siteKey: String, url: String, headers: JSValue) -> String {
        let h = (headers.toString() ?? "").addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let u = url.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        return "http://127.0.0.1:8080?do=js&from=catvod&siteType=\(siteType)&siteKey=\(siteKey)&header=\(h)&url=\(u)"
    }
}
