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
        self.context = JSContext()!
        self.loader = ScriptLoader(context: context, assetProvider: { name in
            Self.loadAsset(name: name)
        })
        let bridge = GlobalBridge(context: context)
        bridge.install()
        preloadLibs()
    }

    private var jsNull: JSValue { JSValue(object: NSNull(), in: context) }

    // MARK: - Spider bootstrap

    func initSpider(api: String, extend: String?) throws {
        spiderAPI = api
        let resolver = SpiderAPI(api)
        guard let source = resolver.fetchSource(assetProvider: { Self.loadAsset(name: $0) }) else {
            throw ScriptLoaderError.moduleNotFound(api)
        }

        isCat = source.contains("__jsEvalReturn")
        let exports = try loader.loadModule(source: source, moduleID: api)

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
        let obj = context.evaluateScript("({})") ?? jsNull
        if isCat {
            obj.setObject(3, forKeyedSubscript: "stype" as NSString)
            obj.setObject(spiderAPI, forKeyedSubscript: "skey" as NSString)
            if let extend, !extend.isEmpty {
                obj.setObject(parseJSONOrString(extend), forKeyedSubscript: "ext" as NSString)
            }
            return obj
        } else {
            if let extend, !extend.isEmpty, extend.hasPrefix("{") {
                return parseJSONOrString(extend)
            }
            return context.evaluateScript(jsStringLiteral(extend ?? "")) ?? jsNull
        }
    }

    /// Parse `extend` as JSON object when possible, otherwise as a plain string value.
    private func parseJSONOrString(_ text: String) -> JSValue {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let literal = jsStringLiteral(text)
        if trimmed.hasPrefix("{") || trimmed.hasPrefix("[") {
            return context.evaluateScript("JSON.parse(" + literal + ")") ?? jsNull
        }
        return context.evaluateScript(literal) ?? jsNull
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

    func destroy() { _ = call("destroy", with: []) }

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
        let jsValue: JSValue?
        switch value {
        case let s as String: jsValue = JSValue(object: s, in: context)
        case let b as Bool: jsValue = JSValue(bool: b, in: context)
        case let i as Int: jsValue = JSValue(int32: Int32(i), in: context)
        default: jsValue = JSValue(object: value, in: context)
        }
        return jsValue ?? jsNull
    }

    private func jsuObject(_ map: [String: String]) -> JSValue? {
        guard let obj = context.evaluateScript("({})") else { return nil }
        for (k, v) in map { obj.setObject(v, forKeyedSubscript: k as NSString) }
        return obj
    }
    private func jsuArray(_ items: [String]) -> JSValue {
        let arr = context.evaluateScript("([])") ?? jsNull
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

    /// Mirrors Android `typeof spider.default === 'function' ? spider.default() : spider.default`.
    private lazy var isFunctionChecker: JSValue? = {
        context.evaluateScript("(function(){ return function(v){ return typeof v === 'function'; }; })()")
    }()

    private func isFunction(_ value: JSValue) -> Bool {
        if value.isUndefined || value.isNull { return false }
        return isFunctionChecker?.call(withArguments: [value])?.toBool() ?? false
    }
}
