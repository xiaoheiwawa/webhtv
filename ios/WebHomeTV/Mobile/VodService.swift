import Foundation

/// Per-site holder of a loaded spider JS engine.
final class SiteEngine {
    private let engine: SpiderEngine
    let site: Site

    init(site: Site) throws {
        self.site = site
        self.engine = SpiderEngine()
        try engine.initSpider(api: site.api, extend: site.ext)
    }

    func home(filter: Bool) -> Result { Result.parse(engine.homeContent(filter: filter)) }
    func homeVod() -> Result { Result.parse(engine.homeVideoContent()) }
    func category(tid: String, pg: String, filter: Bool, extend: [String: String]) -> Result {
        Result.parse(engine.categoryContent(tid: tid, pg: pg, filter: filter, extend: extend))
    }
    func detail(id: String) -> Result { Result.parse(engine.detailContent(id: id)) }
    func search(key: String, quick: Bool, pg: String) -> Result {
        Result.parse(engine.searchContent(key: key, quick: quick, pg: pg))
    }
    func player(flag: String, id: String, vipFlags: [String]) -> Result {
        Result.parse(engine.playerContent(flag: flag, id: id, vipFlags: vipFlags))
    }
    func live(url: String) -> Result { Result.parse(engine.liveContent(url: url)) }
}

/// Registry + facade the native UI uses to talk to the site spiders.
final class VodService {

    static let shared = VodService()

    /// The declared flat `.api` source for a site's engine (its `homePage`-free api).
    private var engines: [String: SiteEngine] = [:]
    private let lock = NSLock()

    private init() {
        // Reserve a fixed port once; LocalHTTPProxy is started in AppDelegate.
    }

    /// Returns the engine for a site, creating it on demand.
    func engine(for site: Site) -> SiteEngine? {
        // A site whose api is empty cannot run a spider; fall back to a WebHome-only site.
        guard !site.api.isEmpty else { return nil }
        lock.lock(); defer { lock.unlock() }
        if let cached = engines[site.key] { return cached }
        do {
            let e = try SiteEngine(site: site)
            engines[site.key] = e
            return e
        } catch {
            NSLog("[VodService] engine init failed %@: %@", site.key, error.localizedDescription)
            return nil
        }
    }

    func release(siteKey: String) {
        lock.lock(); defer { lock.unlock() }
        engines.removeValue(forKey: siteKey)
    }
}
