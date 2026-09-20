import Foundation

/// Normalizes a module specifier against a base (broad port of Android `UriUtil.resolve`).
enum ModuleID {
    static func resolve(_ base: String?, _ spec: String) -> String {
        if spec.hasPrefix("http://") || spec.hasPrefix("https://") || spec.hasPrefix("assets://") {
            return spec
        }
        guard let base, !base.isEmpty else { return spec }
        var result = spec
        if spec.hasPrefix("./") || spec.hasPrefix("../") {
            if let url = URL(string: spec, relativeTo: URL(string: base)), let abs = url.absoluteString {
                result = abs
            }
        } else if !spec.hasPrefix("/") {
            let baseDir = (base as NSString).deletingLastPathComponent
            result = baseDir + "/" + spec
        }
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
