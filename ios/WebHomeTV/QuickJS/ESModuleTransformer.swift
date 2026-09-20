import Foundation

/// Converts ES-module sources into CommonJS-compatible scripts that run on JavaScriptCore.
///
/// Android runs these assets through a QuickJS ES-module loader. JavaScriptCore has no
/// `import`/`export`, so we transform the syntax this project emits:
///   - `import * as X from "id"`, `import X from "id"`      -> `var X = require("id")`
///   - `import "id"`                                        -> `require("id")`
///   - `export { a, b as c }`                               -> `exports.a = a; exports.c = b`
///   - `export { a } from "id"`                             -> re-export from required module
///   - `export default <expr>`                              -> `exports.default = <expr>`
///   - `export const/let/var X`, `export function/class X`  -> drop `export`, append `exports.X = X`
enum ESModuleTransformer {

    static func transform(_ source: String) -> String {
        var out = source
        if out.hasPrefix("\u{FEFF}") { out = String(out.dropFirst()) }
        if out.hasPrefix("#!") {
            if let nl = out.firstIndex(of: "\n") { out = String(out[out.index(after: nl)...]) }
        }

        var plan: [(NSRange, String)] = []

        helperPlan(#"import\s+([\s\S]*?)\s+from\s+["']([^"']+)["'];?"#, out, &plan) { c in
            "var \(c[0]) = require(\"\(c[1])\");"
        }
        helperPlan(#"import\s+["']([^"']+)["'];?"#, out, &plan) { c in
            "require(\"\(c[0])\");"
        }
        helperPlan(#"export\s*\{([^}]*)\}\s*from\s*["']([^"']+)["'];"#, out, &plan) { c in
            reexport(c[0], from: c[1])
        }
        helperPlan(#"export\s*\{([^}]*)\}"#, out, &plan) { c in
            namedExports(c[0])
        }
        // default: `export default <expr>` -> `exports.default = <expr>`
        helperPlan(#"export\s+default\s+"#, out, &plan) { _ in "exports.default = " }

        // need to also leave a marker for module.exports optimisation handled in loader; none needed.

        // declaration exports — capture declared names to re-expose
        let declNames = declarationNames(in: out)
        helperPlan(#"export\s+(async\s+function|function)\s+"#, out, &plan) { c in "\(c[0]) " }
        helperPlan(#"export\s+(class)\s+"#, out, &plan) { c in "\(c[0]) " }
        helperPlan(#"export\s+(const|let|var)\s+"#, out, &plan) { c in "\(c[0]) " }
        if !declNames.isEmpty {
            let exportLine = declNames.map { "exports.\($0) = \($0);" }.joined(separator: " ")
            out = out + "\n;(" + exportLine + ")\n"
        }

        for (range, replacement) in plan.sorted(by: { $0.0.location > $1.0.location }) {
            out = (out as NSString).replacingCharacters(in: range, with: replacement)
        }
        return out
    }

    // MARK: - building blocks

    private static func reexport(_ itemsRaw: String, from mod: String) -> String {
        var s = "var __re = require(\"\(mod)\"); "
        for item in splitList(itemsRaw) {
            if let r = item.range(of: " as ") {
                s += "exports.\(item[r.upperBound...]) = __re.\(item[..<r.lowerBound]); "
            } else {
                s += "exports.\(item) = __re.\(item); "
            }
        }
        return s
    }

    private static func namedExports(_ itemsRaw: String) -> String {
        var s = ""
        for item in splitList(itemsRaw) {
            if let r = item.range(of: " as ") {
                s += "exports.\(item[r.upperBound...]) = \(item[..<r.lowerBound]); "
            } else {
                s += "exports.\(item) = \(item); "
            }
        }
        return s.isEmpty ? "" : s
    }

    private static func declarationNames(in source: String) -> [String] {
        var names: [String] = []
        let pattern = #"export\s+(?:async\s+function|function|class|const|let|var)\s+([A-Za-z_$][\w$]*)"#
        if let regex = try? NSRegularExpression(pattern: pattern) {
            let ns = source as NSString
            for m in regex.matches(in: source, range: NSRange(location: 0, length: ns.length)) {
                if m.numberOfRanges > 1, m.range(at: 1).location != NSNotFound {
                    names.append(ns.substring(with: m.range(at: 1)))
                }
            }
        }
        return names
    }

    private static func helperPlan(_ pattern: String, _ source: String,
                                   _ plan: inout [(NSRange, String)],
                                   _ builder: ([String]) -> String) {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return }
        let ns = source as NSString
        for m in regex.matches(in: source, range: NSRange(location: 0, length: ns.length)) {
            var caps: [String] = []
            for i in 0..<m.numberOfRanges where i > 0 {
                let r = m.range(at: i)
                caps.append(r.location == NSNotFound ? "" : ns.substring(with: r))
            }
            plan.append((m.range, builder(caps)))
        }
    }

    private static func splitList(_ s: String) -> [String] {
        s.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }
}
