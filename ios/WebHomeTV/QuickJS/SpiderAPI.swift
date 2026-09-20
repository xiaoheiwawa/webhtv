import Foundation

/// Resolves a spider `api` identifier (jar class name vs JS module) into fetchable content.
/// Mirrors Android `Module.get().fetch(api)` and `Spider.createObj()`.
struct SpiderAPI {

    /// The api string passed into the loader.
    let api: String
    /// True if the api refers to bundled JS (asset) rather than an external URL.
    let isJSModule: Bool

    init(_ api: String) {
        self.api = api
        self.isJSModule = api.lowercased().hasPrefix("assets://") || api.starts(with: "lib/")
    }

    /// Fetch the raw JS for this api, resolving asset names to bundled files.
    /// Returns nil if the api is a jar-backed `csp_X` (handled elsewhere) or unmapped.
    func fetchSource(assetProvider: (String) -> String?) -> String? {
        if api.hasPrefix("http://") || api.hasPrefix("https://") {
            let res = Network.sync(url: api)
            return res.content.isEmpty ? nil : res.content
        }
        if isJSModule {
            var name = api
            if name.hasPrefix("assets://") { name = String(name.dropFirst("assets://".count)) }
            else if name.hasPrefix("lib/") { name = String(name.dropFirst("lib/".count)) }
            return assetProvider(name)
        }
        // bare non-URL, non-asset: try as bundled asset too (some configs use a short name).
        return assetProvider(api)
    }
}
