import XCTest
import JavaScriptCore
@testable import WebHomeTV

/// Compiles the injected WebHome SDK and checks the Android-compatible surface it must expose.
final class FongmiSDKTests: XCTestCase {

    private static let base = "http://127.0.0.1:8080"

    /// A JSContext standing in for a page: `window`, `document` and the `fongmi` message handler.
    private func makeContext(withBridge: Bool = true, source: String? = nil) -> JSContext {
        let context = JSContext()!
        let bridge = withBridge
            ? "window.webkit = { messageHandlers: { fongmi: { postMessage: function (message) { window.__posted.push(message); } } } };"
            : ""
        context.evaluateScript("""
        var window = {};
        var document = { documentElement: { classList: { add: function (name) { (window.__classes = window.__classes || []).push(name); } } } };
        window.dispatchEvent = function (event) { (window.__events = window.__events || []).push(event && event.type); };
        window.__posted = [];
        \(bridge)
        """)
        context.evaluateScript(source ?? FongmiSDK.source(base: Self.base))
        return context
    }

    private func jsType(_ context: JSContext, _ path: String) -> String {
        context.evaluateScript("typeof \(path)")?.toString() ?? "undefined"
    }

    func testAndroidApiSurface() {
        let context = makeContext()
        let functions = [
            "window.fongmi.invoke",
            "window.fongmi.player.playUrl", "window.fongmi.player.playVod",
            "window.fongmi.player.control", "window.fongmi.player.status",
            "window.fongmi.net.request", "window.fongmi.net.resourceUrl",
            "window.fongmi.cache.get", "window.fongmi.cache.set", "window.fongmi.cache.del",
            "window.fongmi.pan.check", "window.fongmi.pan.play",
            "window.fongmi.ui.setToolbar",
            "window.fongmi.app.search", "window.fongmi.app.openLive",
            "window.fongmi.app.openKeep", "window.fongmi.app.history",
            "window.fongmi.device.info", "window.fongmi.site.info", "window.fongmi.config.info",
            "window.fongmi.navigation.back", "window.fongmi.navigation.reload",
            // Android `window.fm` short aliases.
            "window.fm.req", "window.fm.res", "window.fm.play", "window.fm.vod", "window.fm.ctrl",
            "window.fm.stat", "window.fm.search", "window.fm.openLive", "window.fm.openKeep",
            "window.fm.history", "window.fm.check",
            // Low-level protocol.
            "window.fongmiBridge.invoke", "window.fongmiBridge.resourceUrl",
            "window.fongmiBridge.resultLength", "window.fongmiBridge.resultChunk",
            "window.fongmiBridge.clearResult", "window.fongmiBridge.pushResult",
            "window.fongmiNative.resolve", "window.fongmiNative.reject",
        ]
        for path in functions {
            XCTAssertEqual(jsType(context, path), "function", path)
        }
        XCTAssertEqual(jsType(context, "window.fongmiClient"), "object")
    }

    func testAliasesNativeFlagAndSdkEvent() {
        let context = makeContext()
        let aliases = [
            "window.fm.req === window.fongmi.net.request",
            "window.fm.res === window.fongmi.net.resourceUrl",
            "window.fm.play === window.fongmi.player.playUrl",
            "window.fm.vod === window.fongmi.player.playVod",
            "window.fm.ctrl === window.fongmi.player.control",
            "window.fm.stat === window.fongmi.player.status",
            "window.fm.check === window.fongmi.pan.check",
            "window.fm.pan === window.fongmi.pan",
            "window.fm.cache === window.fongmi.cache",
            "window.fm.ui === window.fongmi.ui",
            "window.fm.openLive === window.fongmi.app.openLive",
            "window.fm.device === window.fongmi.device.info",
            "window.fm.site === window.fongmi.site.info",
            "window.fm.config === window.fongmi.config.info",
            "window.fm.back === window.fongmi.navigation.back",
        ]
        for expression in aliases {
            XCTAssertTrue(context.evaluateScript(expression)?.toBool() ?? false, expression)
        }
        XCTAssertEqual(context.evaluateScript("window.fongmiClient.mode")?.toString(), "mobile")
        XCTAssertTrue(context.evaluateScript("window.fongmiClient.isLeanback === false")?.toBool() ?? false)
        XCTAssertTrue(context.evaluateScript("window.__classes.indexOf('fm-native') >= 0")?.toBool() ?? false)
        XCTAssertTrue(context.evaluateScript("window.__events.indexOf('fmsdk') >= 0")?.toBool() ?? false)
    }

    func testSourceSubstitution() {
        let source = FongmiSDK.source(base: "http://127.0.0.1:9999", mode: "leanback", isLeanback: true)
        XCTAssertTrue(source.contains(#"var BASE = "http://127.0.0.1:9999";"#))
        XCTAssertTrue(source.contains(#"mode: "leanback""#))
        XCTAssertTrue(source.contains("isLeanback: true"))
        XCTAssertFalse(source.contains("__FM_"))
    }

    func testResourceUrlMatchesAndroidShape() {
        let context = makeContext()
        let expected = "http://127.0.0.1:8080/webResource?url=https%3A%2F%2Fa.com%2Fx.mp4%20%26%20y"
        XCTAssertEqual(context.evaluateScript(#"window.fm.res('https://a.com/x.mp4 & y')"#)?.toString(), expected)
        // The native helper must encode exactly like the JS one.
        XCTAssertEqual(FongmiBridge.encodeURIComponent("https://a.com/x.mp4 & y"), "https%3A%2F%2Fa.com%2Fx.mp4%20%26%20y")
        XCTAssertEqual(
            context.evaluateScript(#"window.fm.res('u', { headers: { Referer: 'https://a.com/' }, credentials: 'include' })"#)?.toString(),
            "http://127.0.0.1:8080/webResource?url=u&headers=%7B%22Referer%22%3A%22https%3A%2F%2Fa.com%2F%22%7D&credentials=include"
        )
    }

    func testInvokePostsBridgeEnvelopeAndResolves() {
        let context = makeContext()
        let expectation = self.expectation(description: "resolved")
        var resolved: JSValue?
        let callback: @convention(block) (JSValue) -> Void = { value in
            resolved = value
            expectation.fulfill()
        }
        context.setObject(callback, forKeyedSubscript: "__onResolved" as NSString)

        context.evaluateScript("window.fongmi.net.request('https://api.example/x', { method: 'POST' }).then(__onResolved);")

        XCTAssertEqual(context.evaluateScript("window.__posted.length")?.toInt32(), 1)
        XCTAssertEqual(context.evaluateScript("window.__posted[0].type")?.toString(), "invoke")
        XCTAssertEqual(context.evaluateScript("window.__posted[0].method")?.toString(), "net.request")
        XCTAssertEqual(context.evaluateScript("window.__posted[0].payload.url")?.toString(), "https://api.example/x")
        XCTAssertEqual(context.evaluateScript("window.__posted[0].payload.method")?.toString(), "POST")

        let id = context.evaluateScript("window.__posted[0].id")?.toString() ?? ""
        XCTAssertFalse(id.isEmpty)
        context.evaluateScript("window.fongmiNative.resolve(\(JSONLiteral.quote(id)), { \"code\": 200, \"content\": \"ok\" })")

        wait(for: [expectation], timeout: 2)
        XCTAssertEqual(resolved?.objectForKeyedSubscript("code")?.toInt32(), 200)
        XCTAssertEqual(resolved?.objectForKeyedSubscript("content")?.toString(), "ok")
    }

    func testLargeResultTravelsThroughTheResultStore() {
        let context = makeContext()
        let body = String(repeating: "x", count: 70000)
        let json = "{\"big\":\"\(body)\"}"
        XCTAssertGreaterThan(json.count, FongmiBridge.inlineLimit)

        let resultId = "fm_1_1"
        context.evaluateScript("window.fongmiBridge.pushResult(\(JSONLiteral.quote(resultId)), \(JSONLiteral.quote(json)), false);")
        XCTAssertEqual(context.evaluateScript("window.fongmiBridge.resultLength(\(JSONLiteral.quote(resultId)))")?.toInt32(), Int32(json.count))
        XCTAssertEqual(context.evaluateScript("window.fongmiBridge.resultChunk(\(JSONLiteral.quote(resultId)), 0).length")?.toInt32(), 60000)
        XCTAssertEqual(context.evaluateScript("window.fongmiBridge.resultChunk(\(JSONLiteral.quote(resultId)), 60000).length")?.toInt32(), Int32(json.count - 60000))

        let expectation = self.expectation(description: "hydrated")
        var resolved: JSValue?
        let callback: @convention(block) (JSValue) -> Void = { value in
            resolved = value
            expectation.fulfill()
        }
        context.setObject(callback, forKeyedSubscript: "__onResolved" as NSString)
        context.evaluateScript("window.fongmi.net.request('https://api.example/big').then(__onResolved);")
        let id = context.evaluateScript("window.__posted[0].id")?.toString() ?? ""
        context.evaluateScript("window.fongmiNative.resolve(\(JSONLiteral.quote(id)), { \"__fmResultId\": \(JSONLiteral.quote(resultId)) })")

        wait(for: [expectation], timeout: 2)
        XCTAssertEqual(resolved?.objectForKeyedSubscript("big")?.toString().count, 70000)
        XCTAssertEqual(context.evaluateScript("window.fongmiBridge.resultLength(\(JSONLiteral.quote(resultId)))")?.toInt32(), 0)
    }

    func testInvokeRejectsWithoutBridge() {
        let context = makeContext(withBridge: false)
        let expectation = self.expectation(description: "rejected")
        var message = ""
        let callback: @convention(block) (JSValue) -> Void = { error in
            message = error.objectForKeyedSubscript("message")?.toString() ?? ""
            expectation.fulfill()
        }
        context.setObject(callback, forKeyedSubscript: "__onRejected" as NSString)
        context.evaluateScript("window.fongmi.net.request('https://api.example/x').catch(__onRejected);")
        wait(for: [expectation], timeout: 2)
        XCTAssertEqual(message, "fongmi bridge unavailable")
    }
}