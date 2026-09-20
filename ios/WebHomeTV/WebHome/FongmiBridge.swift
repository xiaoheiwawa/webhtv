import Foundation
import WebKit

/// Errors surfaced to the JS bridge.
enum BridgeError: LocalizedError {
    case unknownMethod(String)
    case emptyURL
    case network(String)
    var errorDescription: String? {
        switch self {
        case .unknownMethod(let m): return "Unknown method: \(m)"
        case .emptyURL: return "url cannot be empty"
        case .network(let msg): return msg
        }
    }
}

typealias BridgePayload = [String: Any]

/// WebHome native bridge over `WKScriptMessageHandler`.
final class FongmiBridge: NSObject, WKScriptMessageHandler {

    private weak var webView: WKWebView?

    init(webView: WKWebView) {
        self.webView = webView
        super.init()
        injectScript()
    }

    // MARK: - Injection

    private func injectScript() {
        let source = """
        (function(){
          if (window.__fongmiInjected) return; window.__fongmiInjected = true;
          var pending = {};
          function invoke(method, payload) {
            return new Promise((resolve, reject) => {
              var id = 'r' + (Date.now()) + '_' + Math.floor(Math.random()*1e6);
              pending[id] = { resolve, reject };
              window.webkit.messageHandlers.fongmi.postMessage({ type: 'invoke', id: id, method: method, payload: payload || {} });
            });
          }
          window.fongmi = {
            invoke: invoke,
            request: function(url, opts) { return invoke('net.request', Object.assign({ url: url }, opts||{})); },
            resourceUrl: function(url, opts) { return invoke('net.resourceUrl', Object.assign({ url: url }, opts||{})); },
            site: function() { return invoke('site.info'); },
            config: function() { return invoke('config.info'); },
            play: function(url, title) { return invoke('player.playUrl', { url: url, title: title||'' }); },
            playerControl: function(action) { return invoke('player.control', { action: action }); },
            playerStatus: function() { return invoke('player.status', {}); },
            speed: function() { return invoke('player.speed', {}); },
            audioTrack: function() { return invoke('player.track', { type: 'audio' }); },
            subtitleTrack: function() { return invoke('player.track', { type: 'subtitle' }); },
            pictureInPicture: function() { return invoke('player.pip', {}); },
            screenshot: function() { return invoke('player.screenshot', {}); },
            flip: function() { return invoke('airplay.toggle', {}); },
            back: function() { return invoke('navigation.back', {}); },
            reload: function() { return invoke('navigation.reload', {}); },
            panCheck: function(items) { return invoke('pan.check', { items: items || [] }); },
            cacheGet: function(rule, key) { return invoke('cache.get', { rule: rule, key: key }); },
            cacheSet: function(rule, key, value) { return invoke('cache.set', { rule: rule, key: key, value: value }); },
            cacheDel: function(rule, key) { return invoke('cache.del', { rule: rule, key: key }); }
          };
          window.fm = window.fongmi;
          window.fongmi._resolve = function(id, value) {
            var p = pending[id]; if (!p) return; delete pending[id]; p.resolve(JSON.parse(value || 'null'));
          };
          window.fongmi._reject = function(id, error) {
            var p = pending[id]; if (!p) return; delete pending[id]; p.reject(new Error(error || 'error'));
          };
        })();
        """
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

    private func route(_ method: String, _ payload: BridgePayload) throws -> Any {
        switch method {
        case "net.request": return NetRequest.handle(payload)
        case "net.resourceUrl": return resourceUrl(payload)
        case "sys.info": return systemInfo()
        case "site.info": return SiteInfoProvider.site()
        case "config.info": return SiteInfoProvider.config()
        case "cache.get": return cacheGet(payload)
        case "cache.set": cacheSet(payload); return "{}"
        case "cache.del": cacheDelete(payload); return "{}"
        case "player.playUrl": return playerPlayUrl(payload)
        case "player.control": return playerControl(payload)
        case "player.status": return PlayerManager.shared.status.dict
        case "player.speed": return playerSpeed()
        case "player.track": return playerTrack(payload)
        case "player.pip": return playerPIP()
        case "player.screenshot": return playerScreenshot()
        case "airplay.toggle": return toggleAirplay()
        case "pan.check": return PanCheck.handle(payload)
        case "navigation.back": AppRouter.pop(); return "{}"
        case "navigation.reload": AppRouter.reload(webView: webView); return "{}"
        default: throw BridgeError.unknownMethod(method)
        }
    }

    // MARK: - net

    private func resourceUrl(_ payload: BridgePayload) -> String {
        guard let url = payload["url"] as? String, !url.isEmpty else { return "" }
        let base = LocalHTTPProxy.shared.address
        return "\(base)/webResource?url=\(url.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")"
    }

    private func systemInfo() -> String { "{}" }

    // MARK: - player

    private func playerPlayUrl(_ payload: BridgePayload) -> String {
        guard let url = payload["url"] as? String, !url.isEmpty else { return "{}" }
        let title = (payload["title"] as? String) ?? ""
        DispatchQueue.main.async { PlayerManager.shared.play(url: url, title: title) }
        return "{}"
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
        let json: String
        if let str = value as? String { json = str }
        else if let data = try? JSONSerialization.data(withJSONObject: value), let str = String(data: data, encoding: .utf8) { json = str }
        else { json = "{}" }
        webView?.evaluateJavaScript("window.fongmi._resolve('\(id)', \(jsStringLiteral(json)))") { _, _ in }
    }
    private func reject(id: String, error: String) {
        webView?.evaluateJavaScript("window.fongmi._reject('\(id)', \(jsStringLiteral(error)))") { _, _ in }
    }
    private func jsStringLiteral(_ s: String) -> String {
        "\"" + s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }
}

/// `net.request` handler.
private enum NetRequest {
    static func handle(_ payload: BridgePayload) throws -> Any {
        guard let url = payload["url"] as? String, !url.isEmpty else { throw BridgeError.emptyURL }
        let method = (payload["method"] as? String) ?? "GET"
        let headers = (payload["headers"] as? [String: String]) ?? [:]
        let responseType = (payload["responseType"] as? String) ?? "text"
        let res = Network.sync(url: url, method: method, headers: headers)
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

