import XCTest
@testable import WebHomeTV

final class Stage6Tests: XCTestCase {

    override func setUp() {
        super.setUp()
        // isolate persisted configs per test
        ConfigStore.save([])
    }

    func testConfigStoreRoundTrip() {
        ConfigStore.upsert(StoredConfig(type: 0, url: "https://a/1.json", name: "A", logo: ""))
        ConfigStore.upsert(StoredConfig(type: 0, url: "https://b/2.json", name: "B", logo: ""))
        let all = ConfigStore.load()
        XCTAssertEqual(all.count, 2)
        XCTAssertEqual(all.first?.url, "https://b/2.json") // upsert inserts at front

        ConfigStore.upsert(StoredConfig(type: 0, url: "https://a/1.json", name: "A", logo: ""))
        XCTAssertEqual(ConfigStore.load().count, 2) // dedupe by url+type
    }

    func testConfigStoreRemove() {
        ConfigStore.upsert(StoredConfig(type: 0, url: "https://x.json", name: "X", logo: ""))
        ConfigStore.remove(url: "https://x.json")
        XCTAssertTrue(ConfigStore.load().isEmpty)
    }

    func testSpeedCycle() {
        XCTAssertEqual(PlayerManager.shared.status.rate, 1.0)
        // cycleSpeed mutates rate even without a player (uses stored status.rate)
        PlayerManager.shared.setRate(1.0)
        let r1 = PlayerManager.shared.cycleSpeed()
        XCTAssertNotEqual(r1, 1.0)
        XCTAssertEqual(PlayerManager.shared.status.rate, r1)
        // restore default
        PlayerManager.shared.setRate(1.0)
    }
}
