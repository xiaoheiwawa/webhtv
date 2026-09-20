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

/// Payload dictionary from the JS bridge.
typealias BridgePayload = [String: Any]

/// Injected JavaScript that exposes `window.fongmi`:
///   invoke(requestId, method, payload)  -> async reply via `window.fongmi.resolve/reject`
///   resourceUrl(url, options)           -> proxied URL
///   resultLength(id) / resultChunk(id,start) / clearResult(id)
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

    // MARK: - WKScriptMessageHandler

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.name == "fongmi",
              let body = message.body as? [String: Any],
              let id = body["id"] as? String,
              let method = body["method"] as? String else { return }
        let payload = (body["payload"] as? [String: Any]) ?? [:]
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.handleSynchronous(id: id, method: method, payload: payload)
        }
    }

    private func handleSynchronous(id: String, method: String, payload: BridgePayload) {
        do {
            let result = try route(method, payload)
            resolve(id: id, value: result)
        } catch {
            reject(id: id, error: error.localizedDescription)
        }
    }

    /// Dispatch a bridge method to its handler. Returns a JSON-encodable object.
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
        default:
            throw BridgeError.unknownMethod(method)
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
        DispatchQueue.main.async {
            PlayerManager.shared.play(url: url, title: title)
        }
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
            default: break
            }
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
        let json: String
        if let str = value as? String {
            json = str
        } else if let data = try? JSONSerialization.data(withJSONObject: value),
                  let str = String(data: data, encoding: .utf8) {
            json = str
        } else {
            json = "{}"
        }
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
        if responseType == "json" {
            if let data = res.content.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: data) {
                return json
            }
            return res.content
        }
        return ["code": res.code, "status": res.status, "content": res.content]
    }
}

/// Site/config info provider (populated once SiteConfig is loaded).
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
        return [
            "url": SiteStore.currentURL ?? "",
            "driveCheck": false,
        ]
    }
}
