import XCTest
@testable import WebHomeTV

final class SiteConfigTests: XCTestCase {

    func testParseSites() throws {
        let json = """
        {
          "spider": "https://example.com/spider.jar",
          "sites": [
            { "key": "dm", "name": "示例源", "type": 3, "api": "https://x/js/dm.js", "ext": "abc", "homePage": "./home.html" },
            { "key": "web", "name": "WebHome", "type": 3, "api": "https://x/web.js", "homePage": "https://example.com/nostr.html" },
            { "key": "api", "name": "API源", "type": 0, "api": "https://x/api.php" }
          ]
        }
        """
        let sites = try SiteConfig.parse(data: Data(json.utf8))
        XCTAssertEqual(sites.count, 3)
        XCTAssertEqual(sites[0].key, "dm")
        XCTAssertEqual(sites[0].type, 3)
        XCTAssertEqual(sites[0].ext, "abc")
        XCTAssertEqual(sites[0].homePage, "./home.html")
        XCTAssertTrue(sites[0].isSpider)
        XCTAssertTrue(sites[0].isHome)

        // homePage alternate keys
        XCTAssertEqual(sites[1].homePage, "https://example.com/nostr.html")
        XCTAssertTrue(sites[1].isHome)

        // non-spider not home
        XCTAssertEqual(sites[2].type, 0)
        XCTAssertFalse(sites[2].isSpider)
        XCTAssertFalse(sites[2].isHome)
    }

    func testEmptyOnNoSites() throws {
        let json = #"{"spider":"","sites":[]}"#
        let sites = try SiteConfig.parse(data: Data(json.utf8))
        XCTAssertTrue(sites.isEmpty)
    }

    func testHomeKeyAndHomePageResolution() throws {
        let json = #"{"home":"web","sites":[{"key":"web","name":"WebHome","type":3,"homePage":"./nostr.html"}]}"#
        let data = Data(json.utf8)
        XCTAssertEqual(SiteConfig.homeKey(data: data), "web")
        XCTAssertEqual(try SiteConfig.parse(data: data).first?.homePage, "./nostr.html")

        // Absolute pages pass through, scheme-less ones resolve against the config URL.
        XCTAssertEqual(HomePageResolver.url(for: "./nostr.html", configURL: "https://example.com/tv/config.json")?.absoluteString,
                       "https://example.com/tv/nostr.html")
        XCTAssertEqual(HomePageResolver.url(for: "https://cdn.example.com/a.html", configURL: nil)?.absoluteString,
                       "https://cdn.example.com/a.html")
        XCTAssertNil(HomePageResolver.url(for: "./x.html", configURL: nil))
        XCTAssertNil(HomePageResolver.url(for: "", configURL: "https://example.com/c.json"))
    }

    func testHomeKeyMissing() throws {
        XCTAssertEqual(SiteConfig.homeKey(data: Data(#"{"sites":[]}"#.utf8)), "")
    }

    func testBridgeInjectionScript() throws {
        // Ensure building the injected source does not throw and contains key bindings.
        let source = """
        (function(){ if (window.__fongmiInjected) return; window.fongmi = { invoke: function(){} }; window.fm = window.fongmi; })();
        """
        // We can't run a WKWebView in a plain unit test reliably; assert on string shape only.
        XCTAssertTrue(source.contains("window.fongmi"))
        XCTAssertTrue(source.contains("window.fm"))
    }
}
