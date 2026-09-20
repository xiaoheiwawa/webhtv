import XCTest
@testable import WebHomeTV

final class Stage4Tests: XCTestCase {

    func testPlaybackStatusDictShape() {
        var status = PlaybackStatus()
        status.url = "http://example.com/v.mp4"
        status.position = 30
        status.duration = 120
        status.isPlaying = true
        let dict = status.dict
        XCTAssertEqual(dict["url"] as? String, "http://example.com/v.mp4")
        XCTAssertEqual(dict["position"] as? Int64, 30)
        XCTAssertEqual(dict["duration"] as? Int64, 120)
        XCTAssertEqual(dict["isPlaying"] as? Bool, true)
    }

    func testSiteInfoProviderShape() {
        SiteStore.current = Site.from(dict: [
            "key": "web", "name": "WebHome", "type": 3, "homePage": "https://x/home.html"
        ])
        let info = SiteInfoProvider.site()
        XCTAssertEqual(info["key"] as? String, "web")
        XCTAssertEqual(info["homePage"] as? String, "https://x/home.html")
        XCTAssertEqual(info["type"] as? Int, 3)
    }

    func testLocalProxyAddressFormat() {
        // address should be a localhost URL even before start (port defaults to 0/8080 semantics).
        let addr = LocalHTTPProxy.shared.address
        XCTAssertTrue(addr.hasPrefix("http://127.0.0.1:"), "addr=\(addr)")
    }
}
