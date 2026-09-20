import Foundation

/// A parsed site entry from a TVBox-style config (`sites` array).
struct Site: Equatable {
    let key: String
    let name: String
    let api: String
    let ext: String
    let jar: String
    let click: String
    let playUrl: String
    let homePage: String
    let type: Int
    let hide: Int
    let searchable: Int
    let changeable: Int
    let quickSearch: Int
    let header: [String: String]

    var isSpider: Bool { type == 3 }
    var isHome: Bool { !homePage.isEmpty }

    /// Parse a site JSON object. Mirrors `Site.objectFrom` (gson field mapping).
    static func from(dict: [String: Any]) -> Site? {
        guard let key = dict["key"] as? String, !key.isEmpty else { return nil }
        func str(_ key: String) -> String { dict[key] as? String ?? "" }
        func int(_ key: String) -> Int { dict[key] as? Int ?? Int(dict[key] as? String ?? "") ?? 0 }
        func first(_ keys: [String]) -> String {
            for k in keys { if let v = dict[k] as? String, !v.isEmpty { return v } }
            return ""
        }
        var header: [String: String] = [:]
        if let h = dict["header"] as? [String: Any] {
            for (k, v) in h { header[k] = "\(v)" }
        } else if let h = dict["header"] as? [String: String] {
            header = h
        }
        return Site(
            key: key,
            name: str("name"),
            api: str("api"),
            ext: str("ext"),
            jar: str("jar"),
            click: str("click"),
            playUrl: str("playUrl"),
            homePage: first(["homePage", "home_page", "webHome", "web_home"]),
            type: int("type"),
            hide: int("hide"),
            searchable: int("searchable"),
            changeable: int("changeable"),
            quickSearch: int("quickSearch"),
            header: header
        )
    }
}

/// Process-global holder for the currently selected site and config URL.
enum SiteStore {
    static var current: Site?
    static var currentURL: String?
}

/// Resolves a site `homePage` into a loadable URL, mirroring Android `HomeWebController.getHomePage`.
/// Absolute URLs pass through; scheme-less ones are resolved against the config URL.
enum HomePageResolver {
    static func url(for page: String, configURL: String?) -> URL? {
        guard !page.isEmpty else { return nil }
        if let url = URL(string: page), let scheme = url.scheme, !scheme.isEmpty { return url }
        guard let configURL, !configURL.isEmpty, let base = URL(string: configURL) else { return nil }
        return URL(string: page, relativeTo: base)?.absoluteURL
    }
}

/// Parses a TVBox-style config JSON into a site list.
enum SiteConfig {
    /// Config-level default site key (`home`), mirroring Android `Config.getHome()`.
    static func homeKey(data: Data) -> String {
        guard let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return "" }
        return object["home"] as? String ?? ""
    }

    static func parse(data: Data) throws -> [Site] {
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let object else {
            throw NSError(domain: "SiteConfig", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid JSON"])
        }
        guard let sitesArr = object["sites"] as? [Any] else { return [] }
        var sites: [Site] = []
        for element in sitesArr {
            if let dict = element as? [String: Any], let site = Site.from(dict: dict) {
                sites.append(site)
            }
        }
        return sites
    }
}

/// Reads a config from a URL (http) or a raw/local JSON string, returning its data.
enum ConfigFetcher {
    static func load(url: String) -> Data? {
        if url.hasPrefix("http://") || url.hasPrefix("https://") {
            let res = Network.sync(url: url)
            return res.content.data(using: .utf8)
        }
        if url.hasPrefix("{") || url.hasPrefix("[") {
            return url.data(using: .utf8)
        }
        let path = url.replacingOccurrences(of: "file://", with: "")
        return FileManager.default.contents(atPath: path)
    }
}
