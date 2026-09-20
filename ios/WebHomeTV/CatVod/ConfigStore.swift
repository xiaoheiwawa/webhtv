import Foundation

/// Persistent reference to a TVBox config (mirrors Android `Config`).
struct StoredConfig: Codable {
    var type: Int
    var url: String
    var name: String
    var logo: String
}

/// Simple persistence for the config list (UserDefaults-backed).
enum ConfigStore {
    private static let key = "stored_configs"

    static func save(_ configs: [StoredConfig]) {
        if let data = try? JSONEncoder().encode(configs) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
    static func load() -> [StoredConfig] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let decoded = try? JSONDecoder().decode([StoredConfig].self, from: data) else { return [] }
        return decoded
    }
    static func upsert(_ config: StoredConfig) {
        var all = load()
        all.removeAll { $0.url == config.url && $0.type == config.type }
        all.insert(config, at: 0)
        save(all)
    }
    static func remove(url: String) {
        save(load().filter { $0.url != url })
    }
}
