import Foundation

/// The JS SDK injected into every WebHome page.
///
/// The surface mirrors Android `HomeWebController.getSdk()` / `HomeWebBridge` so pages written for
/// the Android app keep working unchanged:
///
/// - `window.fongmi` — `invoke`, `player`, `net`, `cache`, `pan`, `ui`, `app`, `device`, `site`,
///   `config`, `navigation`
/// - `window.fm` — the Android short aliases (`req`/`res`/`play`/`vod`/`ctrl`/`stat`/`check`/…)
/// - `window.fongmiClient`, `html.fm-native`, the `fmsdk` event
/// - the low-level `window.fongmiBridge` / `window.fongmiNative` protocol, including the
///   `__fmResultId` result store used for payloads larger than 12 000 characters
///
/// Replies travel over the `fongmi` `WKScriptMessageHandler` as `{type,id,method,payload}`.
enum FongmiSDK {

    /// SDK source with the proxy address / client mode substituted in.
    static func source(base: String, mode: String = "mobile", isLeanback: Bool = false) -> String {
        raw
            .replacingOccurrences(of: "__FM_BASE__", with: JSONLiteral.quote(base))
            .replacingOccurrences(of: "__FM_MODE__", with: JSONLiteral.quote(mode))
            .replacingOccurrences(of: "__FM_LEANBACK__", with: isLeanback ? "true" : "false")
    }

    private static let raw = #"""
(function () {
  if (window.fm && window.fongmi) {
    fireSdkEvent();
    return;
  }

  var BASE = __FM_BASE__;
  var CHUNK = 60000;
  var callbacks = {};
  var results = {};
  var seq = 0;

  function markNative() {
    try {
      if (document && document.documentElement && document.documentElement.classList) {
        document.documentElement.classList.add('fm-native');
      }
    } catch (e) {}
  }

  function fireSdkEvent() {
    try {
      if (typeof CustomEvent === 'function') window.dispatchEvent(new CustomEvent('fmsdk'));
      else window.dispatchEvent({ type: 'fmsdk' });
    } catch (e) {}
  }

  function bridgeHandler() {
    var wk = window.webkit;
    return wk && wk.messageHandlers ? wk.messageHandlers.fongmi : null;
  }

  function post(message) {
    var handler = bridgeHandler();
    if (!handler || typeof handler.postMessage !== 'function') throw new Error('fongmi bridge unavailable');
    handler.postMessage(message);
  }

  function encode(value) {
    return encodeURIComponent(value == null ? '' : String(value));
  }

  function normalizeOptions(options) {
    if (!options) return {};
    if (typeof options === 'string') {
      try { return JSON.parse(options) || {}; } catch (e) { return {}; }
    }
    return options;
  }

  function resourceUrl(url, options) {
    var opts = normalizeOptions(options);
    var out = BASE + '/webResource?url=' + encode(url);
    if (opts.headers) out += '&headers=' + encode(typeof opts.headers === 'string' ? opts.headers : JSON.stringify(opts.headers));
    if (opts.credentials === 'include') out += '&credentials=include';
    return out;
  }

  function invoke(method, payload) {
    return new Promise(function (resolve, reject) {
      var id = 'fm_' + Date.now() + '_' + (++seq);
      callbacks[id] = { resolve: resolve, reject: reject };
      try {
        post({ type: 'invoke', id: id, method: method, payload: payload || {} });
      } catch (e) {
        delete callbacks[id];
        reject(e);
      }
    });
  }

  function pushResult(id, text, append) {
    var value = text == null ? '' : String(text);
    results[id] = append && results[id] != null ? results[id] + value : value;
  }

  function resultLength(id) {
    return results[id] == null ? 0 : results[id].length;
  }

  function resultChunk(id, start) {
    var value = results[id];
    if (value == null || start < 0 || start >= value.length) return '';
    return value.substring(start, Math.min(start + CHUNK, value.length));
  }

  function clearResult(id) {
    delete results[id];
  }

  function hydrate(data) {
    if (!data || !data.__fmResultId) return data;
    var resultId = data.__fmResultId;
    var length = resultLength(resultId);
    var text = '';
    for (var start = 0; start < length; start += CHUNK) text += resultChunk(resultId, start);
    clearResult(resultId);
    return JSON.parse(text);
  }

  var player = {
    playUrl: function (url, title, options) { return invoke('player.playUrl', Object.assign({}, options || {}, { url: url, title: title })); },
    playVod: function (siteKey, vodId, title, pic, options) { return invoke('player.playVod', Object.assign({}, options || {}, { siteKey: siteKey, vodId: vodId, title: title, pic: pic })); },
    control: function (action) { return invoke('player.control', { action: action }); },
    status: function () { return invoke('player.status', {}); }
  };

  var net = {
    request: function (url, options) { return invoke('net.request', Object.assign({}, options || {}, { url: url })); },
    resourceUrl: function (url, options) { return resourceUrl(url, options); }
  };

  var cache = {
    get: function (key, rule) { return invoke('cache.get', { key: key, rule: rule }); },
    set: function (key, value, rule) { return invoke('cache.set', { key: key, value: value, rule: rule }); },
    del: function (key, rule) { return invoke('cache.del', { key: key, rule: rule }); }
  };

  var pan = {
    check: function (items) { return invoke('pan.check', { items: items }); },
    play: function (payload) { return invoke('pan.play', payload || {}); }
  };

  var ui = {
    setToolbar: function (visible) { return invoke('ui.setToolbar', { visible: visible !== false }); }
  };

  var app = {
    search: function (keyword, options) { return invoke('app.search', Object.assign({}, options || {}, { keyword: keyword })); },
    openLive: function () { return invoke('app.openLive', {}); },
    openKeep: function () { return invoke('app.openKeep', {}); },
    history: function () { return invoke('app.history', {}); }
  };

  var device = { info: function () { return invoke('device.info', {}); } };
  var site = { info: function () { return invoke('site.info', {}); } };
  var config = { info: function () { return invoke('config.info', {}); } };
  var navigation = {
    back: function () { return invoke('navigation.back', {}); },
    reload: function () { return invoke('navigation.reload', {}); }
  };

  window.fongmiClient = { mode: __FM_MODE__, isLeanback: __FM_LEANBACK__ };

  window.fongmiBridge = {
    invoke: function (id, method, payload) { post({ type: 'invoke', id: id, method: method, payload: normalizeOptions(payload) }); },
    resourceUrl: function (url, options) { return resourceUrl(url, options); },
    resultLength: resultLength,
    resultChunk: resultChunk,
    clearResult: clearResult,
    pushResult: pushResult,
    __push: pushResult
  };

  window.fongmiNative = {
    resolve: function (id, data) {
      var callback = callbacks[id];
      if (!callback) return;
      delete callbacks[id];
      callback.resolve(hydrate(data));
    },
    reject: function (id, error) {
      var callback = callbacks[id];
      if (!callback) return;
      delete callbacks[id];
      callback.reject(new Error(error || ''));
    }
  };

  window.fongmi = {
    invoke: invoke,
    player: player,
    net: net,
    cache: cache,
    pan: pan,
    ui: ui,
    app: app,
    device: device,
    site: site,
    config: config,
    navigation: navigation,
    client: window.fongmiClient,
    _resolve: function (id, value) { window.fongmiNative.resolve(id, value); },
    _reject: function (id, error) { window.fongmiNative.reject(id, error); }
  };

  window.fm = {
    req: net.request,
    res: net.resourceUrl,
    play: player.playUrl,
    vod: player.playVod,
    ctrl: player.control,
    stat: player.status,
    search: app.search,
    openLive: app.openLive,
    openKeep: app.openKeep,
    history: app.history,
    pan: pan,
    check: pan.check,
    cache: cache,
    ui: ui,
    device: device.info,
    site: site.info,
    config: config.info,
    back: navigation.back,
    reload: navigation.reload,
    invoke: invoke,
    player: player,
    net: net,
    app: app,
    navigation: navigation
  };

  markNative();
  fireSdkEvent();
})();
"""#
}

/// JSON helpers for values handed to `evaluateJavaScript`.
enum JSONLiteral {

    /// JSON text for a bridge handler result.
    ///
    /// `String` values are treated as already-encoded JSON, matching Android where every handler
    /// returns JSON text (`HomeWebBridge.resolve` inserts it verbatim, empty results become `null`).
    static func encode(_ value: Any) -> String {
        if let text = value as? String { return text.isEmpty ? "null" : text }
        if let data = try? JSONSerialization.data(withJSONObject: value, options: [.fragmentsAllowed]),
           let text = String(data: data, encoding: .utf8) {
            return text
        }
        return "null"
    }

    /// Quotes a Swift string as a JSON string literal, safe to embed in JS source.
    static func quote(_ text: String) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: [text]),
              var json = String(data: data, encoding: .utf8) else { return "\"\"" }
        json.removeFirst()
        json.removeLast()
        return json
            .replacingOccurrences(of: "\u{2028}", with: "\\u2028")
            .replacingOccurrences(of: "\u{2029}", with: "\\u2029")
    }
}