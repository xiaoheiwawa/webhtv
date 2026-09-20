import Foundation
import JavaScriptCore

/// Runs CatVod-compliant JS Spider assets on JavaScriptCore.
///
/// Port of `quickjs/.../crawler/Spider.java`. Method names and argument shapes match so the same
/// bundled `js/lib` assets and remote csp spiders work. Loads synchronously on the caller thread.
final class SpiderEngine {

    private let context: JSContext
    private let loader: ScriptLoader
    private var spider: JSValue?
    private var spiderAPI: String = ""
    private var isCat: Bool = false

    private let executionQueue = DispatchQueue(label: "webhometv.spider")

    init() {
        self.context = JSContext()
        self.loader = ScriptLoader(context: context, assetProvider: { name in
            Self.loadAsset(name: name)
        })
        let bridge = GlobalBridge(context: context)
        bridge.install()
        preloadLibs()
    }

    // MARK: - Spider bootstrap

    /// Evaluate and prepare the spider for the given api + extend string.
    func initSpider(api: String, extend: String?) throws {
        spiderAPI = api
        let resolver = SpiderAPI(api)
        guard let source = resolver.fetchSource(assetProvider: { Self.loadAsset(name: $0) }) else {
            throw ScriptLoaderError.moduleNotFound(api)
        }

        isCat = source.contains("__jsEvalReturn")
        let exports: JSValue
        do {
            exports = try loader.loadModule(source: source, moduleID: api)
        } catch { throw error }

        // Resolve the spider object.
        if let evalReturn = exports.objectForKeyedSubscript("__jsEvalReturn"), !evalReturn.isUndefined {
            isCat = true
            spider = evalReturn.call(withArguments: [])
        } else if let def = exports.objectForKeyedSubscript("default"), !def.isUndefined {
            if isFunction(def) {
                spider = def.call(withArguments: [])
            } else {
                spider = def
            }
        } else if exports.isObject {
            spider = exports
        } else {
            throw ScriptLoaderError.evaluationFailed("no default export")
        }

        let ext = buildExt(extend: extend)
        _ = call("init", with: [ext])
    }

    private func buildExt(extend: String?) -> JSValue {
        if isCat {
            let obj = context.evaluateScript("({})") ?? context.null
            obj.setObject(3, forKeyedSubscript: "stype" as NSString)
            obj.setObject(spiderAPI, forKeyedSubscript: "skey" as NSString)
            if let extend, !extend.isEmpty {
                if extend.hasPrefix("{"), let parsed = context.evaluateScript("JSON.parse(arguments[0])", withArguments: [extend]) {
                    obj.setObject(parsed, forKeyedSubscript: "ext" as NSString)
                } else {
                    obj.setObject(extend, forKeyedSubscript: "ext" as NSString)
                }
            }
            return obj
        } else {
            if let extend, !extend.isEmpty, extend.hasPrefix("{") {
                return context.evaluateScript("JSON.parse(arguments[0])", withArguments: [extend]) ?? context.null
            }
            return context.evaluateScript(jsStringLiteral(extend ?? ""))
        }
    }

    // MARK: - Spider methods

    func homeContent(filter: Bool) -> String { callString("home", args: [filter]) }
    func homeVideoContent() -> String { callString("homeVod") }
    func categoryContent(tid: String, pg: String, filter: Bool, extend: [String: String]) -> String {
        let e = jsuObject(extend)
        return callString("category", args: [tid, pg, filter, e])
    }
    func detailContent(id: String) -> String { callString("detail", args: [id]) }
    func searchContent(key: String, quick: Bool) -> String { callString("search", args: [key, quick]) }
    func searchContent(key: String, quick: Bool, pg: String) -> String { callString("search", args: [key, quick, pg]) }
    func playerContent(flag: String, id: String, vipFlags: [String]) -> String {
        return callString("play", args: [flag, id, jsuArray(vipFlags)])
    }
    func liveContent(url: String) -> String { callString("live", args: [url]) }
    func manualVideoCheck() -> Bool { callBool("sniffer") }
    func isVideoFormat(_ url: String) -> Bool { callBool("isVideo", args: [url]) }
    func action(_ action: String) -> String { callString("action", args: [action]) }

    func proxy(params: [String: String]) -> String? {
        guard let obj = jsuObject(params) else { return nil }
        return call("proxy", with: [obj])?.toString()
    }

    func destroy() { _ = call("destroy") }

    // MARK: - Internals

    private func preloadLibs() {
        for lib in ["http", "cat", "crypto-js", "gbk", "similarity"] {
            _ = try? loader.load(lib)
        }
    }

    private func call(_ name: String, with args: [Any]) -> JSValue? {
        guard let fn = spider?.objectForKeyedSubscript(name), !fn.isUndefined else { return nil }
        let jsArgs = args.map { toJS($0) }
        var result: JSValue?
        executionQueue.sync {
            result = fn.call(withArguments: jsArgs)
        }
        return result
    }

    private func callString(_ name: String, args: [Any] = []) -> String {
        (call(name, with: args)?.toString()) ?? ""
    }
    private func callBool(_ name: String, args: [Any] = []) -> Bool {
        call(name, with: args)?.toBool() ?? false
    }

    private func toJS(_ value: Any) -> JSValue {
        switch value {
        case let s as String: return JSValue(object: s, in: context) ?? context.null
        case let b as Bool: return JSValue(bool: b, in: context) ?? context.null
        case let i as Int: return JSValue(int32: Int32(i), in: context) ?? context.null
        default: return JSValue(object: value, in: context) ?? context.null
        }
    }

    private func jsuObject(_ map: [String: String]) -> JSValue? {
        let obj = context.evaluateScript("({})")
        for (k, v) in map { obj?.setObject(v, forKeyedSubscript: k as NSString) }
        return obj
    }
    private func jsuArray(_ items: [String]) -> JSValue {
        let arr = context.evaluateScript("([])") ?? context.null
        for (i, item) in items.enumerated() { arr.setObject(item, forKeyedSubscript: NSNumber(value: i)) }
        return arr
    }

    private static func loadAsset(name: String) -> String? {
        let candidates = [
            "Resources/JS/lib/\(name).js",
            "Resources/JS/\(name).js",
            "Resources/JS/lib/\(name)",
            "Resources/JS/\(name)",
        ]
        for path in candidates {
            if let resolved = Bundle.main.path(forResource: (path as NSString).deletingPathExtension,
                                               ofType: "js",
                                               inDirectory: (path as NSString).deletingLastPathComponent.isEmpty ? nil : (path as NSString).deletingLastPathComponent),
               let src = try? String(contentsOfFile: resolved, encoding: .utf8) {
                return src
            }
            // direct relative path fallback
            if let full = Bundle.main.resourceURL?.appendingPathComponent(path),
               let src = try? String(contentsOfFile: full.path, encoding: .utf8) {
                return src
            }
        }
        return nil
    }

    private func jsStringLiteral(_ s: String) -> String {
        "\"" + s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }
}

    /// Mirrors Android `typeof spider.default === 'function' ? spider.default() : spider.default`.
    /// NSObject/JSCore does not expose `isCallable`, so detect via Object.prototype.toString.
    private func isFunction(_ value: JSValue) -> Bool {
        if value.isUndefined || value.isNull { return false }
        let tag = context.evaluateScript("Object.prototype.toString.call(arguments[0]).slice(8, -1)", withArguments: [value])?.toString()
        return tag == "Function" || tag == "AsyncFunction"
    }
