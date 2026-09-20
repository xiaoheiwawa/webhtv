import Foundation
import UIKit
import WebKit

/// Errors surfaced to the JS bridge.
enum BridgeError: LocalizedError {
    case unknownMethod(String)
    case emptyURL
    case notSupported(String)
    case network(String)
    var errorDescription: String? {
        switch self {
        case .unknownMethod(let m): return "Unknown method: \(m)"
        case .emptyURL: return "url cannot be empty"
        case .notSupported(let m): return "iOS 端暂未实现: \(m)"
        case .network(let msg): return msg
        }
    }
}

typealias BridgePayload = [String: Any]

/// WebHome native bridge over `WKScriptMessageHandler`.
///
/// Mirrors Android `HomeWebBridge`: JS posts `{type,id,method,payload}` (see `FongmiSDK`), the reply
/// is delivered through `window.fongmiNative.resolve/reject`. Results larger than `inlineLimit` go
/// through the `window.fongmiBridge` result store, the same 12 000 char / 60 000 char chunk contract
/// the Android bridge uses.
final class FongmiBridge: NSObject, WKScriptMessageHandler {

    /// Android `HomeWebBridge.INLINE_LIMIT`.
    static let inlineLimit = 12000

    private weak var webView: WKWebView?

    /// `ui.setToolbar` hook, wired by `WebHomeViewController`.
    var onToolbarVisible: ((Bool) -> Void)?

    init(webView: WKWebView) {
        self.webView = webView
        super.init()
        injectScript()
    }

    // MARK: - Injection

    private func injectScript() {
        let source = FongmiSDK.source(base: LocalHTTPProxy.shared.address)
        let script = WKUserScript(source: source, injectionTime: .atDocumentStart, forMainFrameOnly: true)
        webView?.configuration.userContentController.addUserScript(script)
    }

    // MARK: - Message handler

    func userContentController(_ ucc: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.name == "fongmi",
              let body = message.body as? [String: Any],
              let id = body["id"] as? String,
              let method = body["method"] as? String else { return }
        let payload = (body["payload"] as? [String: Any]) ?? [:]
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.handle(id: id, method: method, payload: payload)
        }
    }

    private func handle(id: String, method: String, payload: BridgePayload) {
        do {
            resolve(id: id, value: try route(method, payload))
        } catch {
            reject(id: id, error: error.localizedDescription)
        }
    }

    /// Method table, kept in sync with Android `HomeWebBridge.handle`.
    private func route(_ method: String, _ payload: BridgePayload) throws -> Any {
        switch method {
        case "net.request": return try NetRequest.handle(payload)
        case "net.resourceUrl": return JSONLiteral.quote(resourceUrl(payload))
        case "sys.info": return systemInfo()
        case "device.info": return DeviceInfo.current()
        case "site.info": return SiteInfoProvider.site()
        case "config.info": return SiteInfoProvider.config()
        case "cache.get": return JSONLiteral.quote(cacheGet(payload))
        case "cache.set": cacheSet(payload); return "{}"
        case "cache.del": cacheDelete(payload); return "{}"
        case "player.playUrl": return playerPlayUrl(payload)
        case "player.playVod": return try playerPlayVod(payload)
        case "player.control": return playerControl(payload)
        case "player.status": return PlayerManager.shared.status.dict
        case "player.speed": return playerSpeed()
        case "player.track": return playerTrack(payload)
        case "player.pip": return playerPIP()
        case "player.screenshot": return playerScreenshot()
        case "airplay.toggle": return toggleAirplay()
        case "pan.check": return PanCheck.handle(payload)
        case "pan.play": return try panPlay(payload)
        case "app.search": return unsupported("搜索（app.search）")
        case "app.openLive": return unsupported("电视直播（app.openLive）")
        case "app.openKeep": return unsupported("收藏（app.openKeep）")
        case "app.history": return history()
        case "ui.setToolbar": return setToolbar(payload)
        case "navigation.back": return navigateBack()
        case "navigation.reload": AppRouter.reload(webView: webView); return "{}"
        default: throw BridgeError.unknownMethod(method)
        }
    }

    // MARK: - net

    /// Mirrors Android `HomeWebBridge.resourceUrl`: `<proxy>/webResource?url=…[&headers=…][&credentials=include]`.
    private func resourceUrl(_ payload: BridgePayload) -> String {
        guard let url = payload["url"] as? String, !url.isEmpty else { return "" }
        var out = "\(LocalHTTPProxy.shared.address)/webResource?url=\(Self.encodeURIComponent(url))"
        if let headers = payload["headers"] {
            let text = (headers as? String) ?? JSONLiteral.encode(headers)
            if !text.isEmpty { out += "&headers=\(Self.encodeURIComponent(text))" }
        }
        if (payload["credentials"] as? String) == "include" { out += "&credentials=include" }
        return out
    }

    /// Percent-encodes exactly like JS `encodeURIComponent` so both SDK paths agree.
    static let uriComponentAllowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_.!~*'()")

    static func encodeURIComponent(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: uriComponentAllowed) ?? ""
    }

    private func systemInfo() -> String { "{}" }

    // MARK: - player

    private func playerPlayUrl(_ payload: BridgePayload) -> String {
        guard let raw = payload["url"] as? String, !raw.isEmpty else { return "{}" }
        // Android routes through the local proxy when headers/cookies are requested.
        let includeCookies = (payload["credentials"] as? String) == "include"
        let url = (payload["headers"] != nil || includeCookies) ? resourceUrl(payload) : raw
        let title = (payload["title"] as? String) ?? ""
        DispatchQueue.main.async { PlayerManager.shared.play(url: url, title: title.isEmpty ? url : title) }
        return "{}"
    }

    private func playerPlayVod(_ payload: BridgePayload) throws -> String {
        // The Spider engine is not wired to a site detail/playback screen on iOS yet.
        NotImplementedFeature.notify("播放站点视频（player.playVod）")
        throw BridgeError.notSupported("player.playVod")
    }

    private func playerControl(_ payload: BridgePayload) -> String {
        guard let action = payload["action"] as? String else { return "{}" }
        DispatchQueue.main.async {
            switch action {
            case "play": PlayerManager.shared.resume()
            case "pause": PlayerManager.shared.pause()
            case "stop": PlayerManager.shared.stop()
            case "prev": PlayerManager.shared.prev()
            case "next": PlayerManager.shared.next()
            case "replay": PlayerManager.shared.replay()
            case "loop": PlayerManager.shared.repeatToggle()
            case "forward": PlayerManager.shared.seekRelative(15)
            case "backward": PlayerManager.shared.seekRelative(-15)
            default: break
            }
        }
        return "{}"
    }

    private func playerSpeed() -> String {
        let rate = PlayerManager.shared.cycleSpeed()
        return "{\"rate\":\(rate)}"
    }

    private func playerTrack(_ payload: BridgePayload) -> String {
        let type = (payload["type"] as? String) ?? "audio"
        DispatchQueue.main.async {
            if type == "subtitle" { PlayerManager.shared.cycleSubtitleTrack() }
            else { PlayerManager.shared.cycleAudioTrack() }
        }
        return "{}"
    }

    private func playerPIP() -> String {
        DispatchQueue.main.async {
            if PlayerManager.shared.isPIPActive { PlayerManager.shared.stopPIP() }
            else { PlayerManager.shared.startPIP() }
        }
        return "{}"
    }

    private func playerScreenshot() -> String {
        guard let image = PlayerManager.shared.screenshot(),
              let data = image.jpegData(compressionQuality: 0.8) else { return #"{"ok":false}"# }
        let base64 = data.base64EncodedString()
        return "{\"ok\":true,\"image\":\"data:image/jpeg;base64,\(base64)\"}"
    }
    private func toggleAirplay() -> String {
        // AVPlayer allows external playback by default; expose as a passthrough toggle hook.
        return "{\"airplay\":true}"
    }

    // MARK: - pan / app / ui

    /// Android `HomeWebBridge.playPan`: `push://` is stripped and the link plays directly.
    private func panPlay(_ payload: BridgePayload) throws -> String {
        guard let raw = payload["url"] as? String, !raw.isEmpty else { throw BridgeError.emptyURL }
        let url = raw.lowercased().hasPrefix("push://") ? String(raw.dropFirst("push://".count)) : raw
        let title = (payload["title"] as? String) ?? ""
        DispatchQueue.main.async { PlayerManager.shared.play(url: url, title: title.isEmpty ? url : title) }
        return "{}"
    }

    private func history() -> String {
        // No local watch-history store on iOS yet; an empty list keeps page rendering intact.
        return "[]"
    }

    /// Android-only UI entry points: answer with a shape pages can inspect and tell the user once.
    private func unsupported(_ feature: String) -> String {
        NotImplementedFeature.notify(feature)
        return #"{"unsupported":true}"#
    }

    private func setToolbar(_ payload: BridgePayload) -> String {
        let visible = (payload["visible"] as? Bool) ?? true
        DispatchQueue.main.async { [weak self] in self?.onToolbarVisible?(visible) }
        return "{}"
    }

    private func navigateBack() -> String {
        DispatchQueue.main.async { [weak self] in
            guard let webView = self?.webView else { AppRouter.pop(); return }
            if webView.canGoBack { webView.goBack() } else { AppRouter.pop() }
        }
        return "{}"
    }

    // MARK: - cache

    private func cacheGet(_ payload: BridgePayload) -> String {
        UserDefaults.standard.string(forKey: cacheKey(payload)) ?? ""
    }
    private func cacheSet(_ payload: BridgePayload) {
        if let value = payload["value"] as? String {
            UserDefaults.standard.set(value, forKey: cacheKey(payload))
        }
    }
    private func cacheDelete(_ payload: BridgePayload) {
        UserDefaults.standard.removeObject(forKey: cacheKey(payload))
    }
    private func cacheKey(_ payload: BridgePayload) -> String {
        let rule = (payload["rule"] as? String) ?? ""
        let key = (payload["key"] as? String) ?? ""
        return "cache_" + (rule.isEmpty ? "" : rule + "_") + key
    }

    // MARK: - Reply

    private func resolve(id: String, value: Any) {
        let json = JSONLiteral.encode(value)
        guard let webView = webView else { return }
        guard json.count > Self.inlineLimit else {
            webView.evaluateJavaScript("window.fongmiNative&&window.fongmiNative.resolve(\(JSONLiteral.quote(id)), \(json))") { _, _ in }
            return
        }
        // Large payload: park it in the JS result store first, then hand back the handle.
        let resultId = "\(id)_\(Int(Date().timeIntervalSince1970 * 1000))"
        let script = "window.fongmiBridge&&window.fongmiBridge.pushResult(\(JSONLiteral.quote(resultId)), \(JSONLiteral.quote(json)), false);"
            + "window.fongmiNative&&window.fongmiNative.resolve(\(JSONLiteral.quote(id)), {\"__fmResultId\":\(JSONLiteral.quote(resultId))});"
        webView.evaluateJavaScript(script) { _, _ in }
    }

    private func reject(id: String, error: String) {
        webView?.evaluateJavaScript("window.fongmiNative&&window.fongmiNative.reject(\(JSONLiteral.quote(id)), \(JSONLiteral.quote(error)))") { _, _ in }
    }
}

/// `net.request` handler. Mirrors Android `WebCall.request` payload keys.
private enum NetRequest {
    static func handle(_ payload: BridgePayload) throws -> Any {
        guard let url = payload["url"] as? String, !url.isEmpty else { throw BridgeError.emptyURL }
        let method = (payload["method"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "GET"
        let headers = (payload["headers"] as? [String: String]) ?? [:]
        let body = (payload["body"] as? String)?.data(using: .utf8)
        let timeout = (payload["timeout"] as? NSNumber)?.doubleValue
        let responseType = (payload["responseType"] as? String) ?? "text"
        let res = Network.sync(url: url, method: method, headers: headers, body: body, timeout: timeout ?? Network.defaultTimeout)
        if responseType == "json",
           let data = res.content.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) {
            return json
        }
        return ["code": res.code, "status": res.status, "content": res.content]
    }
}

/// Pan(网盘) link check stub — deep integration with the drive-detection service is a later milestone.
enum PanCheck {
    static func handle(_ payload: BridgePayload) -> Any {
        let items = (payload["items"] as? [Any]) ?? []
        var out: [[String: Any]] = []
        for it in items {
            if let dict = it as? [String: Any] {
                out.append(["url": dict["url"] ?? "", "ok": false, "type": "unknown"])
            }
        }
        return out
    }
}

/// Device info for `device.info` (Android serves the same keys from `/device`).
enum DeviceInfo {
    private static var cached: [String: Any]?

    static func current() -> [String: Any] {
        if let cached = cached { return cached }
        let info: [String: Any]
        if Thread.isMainThread {
            info = build()
        } else {
            var boxed: [String: Any] = [:]
            DispatchQueue.main.sync { boxed = build() }
            info = boxed
        }
        cached = info
        return info
    }

    private static func build() -> [String: Any] {
        let device = UIDevice.current
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
        return [
            "uuid": device.identifierForVendor?.uuidString ?? "",
            "name": device.name,
            "type": 1,
            "serial": "",
            "ip": "",
            "eth": "",
            "wlan": "",
            "model": device.model,
            "system": "\(device.systemName) \(device.systemVersion)",
            "app": "WebHomeTV \(version)",
            "time": Int(Date().timeIntervalSince1970),
        ]
    }
}

/// Android-only features: tell the user once instead of failing silently.
enum NotImplementedFeature {
    private static var shown: Set<String> = []

    static func notify(_ feature: String) {
        DispatchQueue.main.async {
            guard !shown.contains(feature) else { return }
            shown.insert(feature)
            NSLog("[FongmiBridge] not implemented on iOS: %@", feature)
            guard let top = VideoPresenter.topViewController() else { return }
            let alert = UIAlertController(title: "iOS 端暂未实现", message: feature, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "好", style: .default))
            top.present(alert, animated: true)
        }
    }
}

/// App navigation helpers for `navigation.*`.
enum AppRouter {
    static func pop() {
        DispatchQueue.main.async {
            VideoPresenter.topViewController()?.navigationController?.popViewController(animated: true)
        }
    }
    static func reload(webView: WKWebView?) {
        webView?.reload()
    }
}

/// Site/config info provider.
enum SiteInfoProvider {
    static func site() -> [String: Any] {
        let site = SiteStore.current
        return [
            "key": site?.key ?? "",
            "name": site?.name ?? "",
            "homePage": site?.homePage ?? "",
            "type": site?.type ?? 0,
            "header": site?.header ?? [:],
        ]
    }
    static func config() -> [String: Any] {
        return ["url": SiteStore.currentURL ?? "", "driveCheck": false]
    }
}