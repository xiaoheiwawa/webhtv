import Foundation
import JavaScriptCore

enum ScriptLoaderError: LocalizedError {
    case assetNotFound(String)
    case moduleNotFound(String)
    case evaluationFailed(String)

    var errorDescription: String? {
        switch self {
        case .assetNotFound(let m): return "Asset not found: \(m)"
        case .moduleNotFound(let m): return "Module not found: \(m)"
        case .evaluationFailed(let msg): return "JS evaluation failed: \(msg)"
        }
    }
}

/// CommonJS-style synchronous module loader over JavaScriptCore.
///
/// `__webhtv_require(id)` is a Swift-backed JS function that lazily resolves, transforms, and
/// evaluates a module, returning its `exports`. Modules are cached by normalized id.
final class ScriptLoader {

    private unowned let context: JSContext
    private let assetProvider: (String) -> String?
    private var cache: [String: JSValue]

    init(context: JSContext, assetProvider: @escaping (String) -> String?) {
        self.context = context
        self.assetProvider = assetProvider
        self.cache = [:]
        installRequire()
    }

    /// Load a module by specifier relative to `base`.
    @discardableResult
    func load(_ specifier: String, base: String? = nil) throws -> JSValue {
        let id = ModuleID.resolve(base, specifier)
        if let cached = cache[id] { return cached }
        guard let source = fetch(id) else { throw ScriptLoaderError.moduleNotFound(id) }
        return try evaluate(source: source, moduleID: id)
    }

    /// Load an already-obtained JS source under a given module id.
    @discardableResult
    func loadModule(source: String, moduleID: String) throws -> JSValue {
        if let cached = cache[moduleID] { return cached }
        return try evaluate(source: source, moduleID: moduleID)
    }

    // MARK: - Require

    private func installRequire() {
        let requireBlock: @convention(block) (String) -> JSValue = { [weak self] name in
            guard let self else { return JSValue(undefinedIn: JSContext()) }
            do {
                return try self.load(name)
            } catch {
                NSLog("[ScriptLoader] require(%@) failed: %@", name, error.localizedDescription)
                return JSValue(undefinedIn: self.context)
            }
        }
        context.globalObject.setObject(requireBlock, forKeyedSubscript: "__webhtv_require" as NSString)
    }

    // MARK: - Loading

    private func fetch(_ id: String) -> String? {
        if id.hasPrefix("http://") || id.hasPrefix("https://") {
            let res = Network.sync(url: id)
            return res.content.isEmpty ? nil : res.content
        }
        if id.hasPrefix("assets://") {
            return assetProvider(String(id.dropFirst("assets://".count)))
        }
        return assetProvider(id)
    }

    private func evaluate(source: String, moduleID: String) throws -> JSValue {
        let transformed = ESModuleTransformer.transform(source)
        let idLiteral = jsStringLiteral(moduleID)
        let wrapper =
            "(function(){\n" +
            "var $module = { id: \(idLiteral), exports: {} };\n" +
            "var $exports = $module.exports;\n" +
            "var $require = function(name){ return __webhtv_require(name); };\n" +
            "(function(module, exports, require){\n" +
            transformed + "\n" +
            "})($module, $exports, $require);\n" +
            "return $module.exports;\n" +
            "})();"
        guard let result = context.evaluateScript(wrapper, withSourceURL: URL(string: "webhome://\(moduleID)")) else {
            throw ScriptLoaderError.evaluationFailed(moduleID)
        }
        cache[moduleID] = result
        return result
    }

    private func jsStringLiteral(_ s: String) -> String {
        "\"" + s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }
}
