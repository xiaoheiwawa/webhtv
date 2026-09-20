import Foundation

extension Notification.Name {
    static let configChanged = Notification.Name("com.webhometv.configChanged")
}

/// Shared config loading used by both the native tab UI and the WebHome launcher.
/// Centralizes fetching (incl. depot `urls` descent), parsing, and the "last used" restore.
final class ConfigManager {

    static let shared = ConfigManager()

    var sites: [Site] = []
    var currentURL: String?

    private init() {}

    var lastURL: String? {
        get { UserDefaults.standard.string(forKey: "configURL") }
        set { UserDefaults.standard.set(newValue ?? "", forKey: "configURL") }
    }

    /// Loads a config URL and returns parsed sites + resolved URL (depot descent), or nil.
    func load(url: String) -> (sites: [Site], resolvedURL: String)? {
        guard var data = ConfigFetcher.load(url: url) else { return nil }
        var resolved = url
        if let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
           obj["sites"] == nil {
            if let urls = obj["urls"] as? [String],
               let first = urls.first,
               let next = ConfigFetcher.load(url: first) {
                data = next
                resolved = first
            }
        }
        guard let parsed = try? SiteConfig.parse(data: data) else { return nil }
        sites = parsed.sorted { $0.name < $1.name }
        currentURL = resolved
        lastURL = url
        ConfigStore.upsert(StoredConfig(type: 0, url: url, name: parsed.first?.name ?? "config", logo: ""))
        NotificationCenter.default.post(name: .configChanged, object: nil)
        return (sites, resolved)
    }

    /// Restore the last-used config on a background queue; returns true if a config was loaded.
    @discardableResult
    func restore(completion: ((Bool) -> Void)? = nil) -> Bool {
        guard let last = lastURL, !last.isEmpty else { return false }
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let ok = self?.load(url: last) != nil
            DispatchQueue.main.async { completion?(ok) }
        }
        return true
    }
}
