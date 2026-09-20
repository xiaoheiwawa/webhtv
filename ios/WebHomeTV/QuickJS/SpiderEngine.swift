import Foundation
import JavaScriptCore

/// Loads and runs CatVod-compliant JS Spider assets on JavaScriptCore.
/// The JS `lib` assets are copied from `quickjs/src/main/assets/js/lib`.
final class SpiderEngine {

    private let context: JSContext
    private var localStorage: [String: String] = [:]

    init() {
        self.context = JSContext()
        installGlobalBridge()
    }

    private func installGlobalBridge() {
        let bridge = GlobalBridge(
            context: context,
            storageGet: { [weak self] key in self?.localStorage[key, default: ""] ?? "" },
            storageSet: { [weak self] key, value in self?.localStorage[key] = value },
            storageDelete: { [weak self] key in self?.localStorage.removeValue(forKey: key) }
        )
        context.globalObject.setObject(bridge, forKeyedSubscript: "native" as NSString)
    }

    /// Bundle an individual `js/lib` asset. Stage two wires the ES-module loader
    /// (spider.js uses `import * as spider from '%s'`), so this currently evaluates the raw source.
    private func loadLibrary(_ name: String) {
        guard let path = Bundle.main.path(forResource: name, ofType: "js", inDirectory: "Resources/JS/lib") else {
            NSLog("[SpiderEngine] missing library asset: %@", name)
            return
        }
        guard let source = try? String(contentsOfFile: path, encoding: .utf8) else { return }
        context.evaluateScript(source)
    }

    /// Evaluate a CSP spider source; returns the spider object (or nil if the source exposes no default).
    func run(text: String) -> JSValue? {
        // stub — full loader wiring added in the JS milestone
        return nil
    }
}
