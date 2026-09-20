import UIKit
import WebKit

/// Renders a site's custom WebHome page inside WKWebView, with `window.fongmi` native bridge.
final class WebHomeViewController: UIViewController {

    private let site: Site
    private var webView: WKWebView!
    private var bridge: FongmiBridge!

    init(site: Site) {
        self.site = site
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        configureWebView()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        // A page may have hidden the bar via `ui.setToolbar(false)`.
        navigationController?.setNavigationBarHidden(false, animated: animated)
    }

    private func configureWebView() {
        title = site.name.isEmpty ? site.key : site.name
        view.backgroundColor = .black

        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()

        let userContent = WKUserContentController()
        config.userContentController = userContent

        webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = self
        webView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(webView)
        NSLayoutConstraint.activate([
            webView.topAnchor.constraint(equalTo: view.topAnchor),
            webView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            webView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        webView.backgroundColor = .black
        webView.isOpaque = false

        bridge = FongmiBridge(webView: webView)
        // `ui.setToolbar(false)` hides the navigation bar for immersive pages.
        bridge.onToolbarVisible = { [weak self] visible in
            self?.navigationController?.setNavigationBarHidden(!visible, animated: true)
        }
        userContent.add(bridge, name: "fongmi")

        loadHome()
    }

    private func loadHome() {
        let page = site.homePage
        guard !page.isEmpty else {
            showMessage("该站点没有配置 WebHome 首页")
            return
        }
        // Bundled asset first (`assets://` / `file://`).
        if page.hasPrefix("file://") || page.hasPrefix("assets://") {
            let path = page.replacingOccurrences(of: "file://", with: "").replacingOccurrences(of: "assets://", with: "")
            if let url = Bundle.main.url(forResource: path, withExtension: nil) {
                webView.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
            } else {
                showMessage("找不到本地 WebHome 资源：\(path)")
            }
            return
        }
        // http(s) or a path relative to the config URL (as on Android).
        if let url = HomePageResolver.url(for: page, configURL: SiteStore.currentURL) {
            webView.load(URLRequest(url: url))
            return
        }
        // Inline HTML stored in the config.
        webView.loadHTMLString(page, baseURL: nil)
    }

    /// Visible fallback: a failed load must never leave the user staring at a black screen.
    private func showMessage(_ text: String) {
        let html = """
        <html><head><meta charset="utf-8">
        <meta name="viewport" content="width=device-width,initial-scale=1"></head>
        <body style="margin:0;height:100vh;display:flex;align-items:center;justify-content:center;background:#000;color:#e6e6e6;font:16px -apple-system,sans-serif;text-align:center;padding:24px">\(text)</body>
        </html>
        """
        webView.loadHTMLString(html, baseURL: nil)
    }
}

extension WebHomeViewController: WKNavigationDelegate {
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        // optional: log loaded title
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        showMessage("页面加载失败：\(error.localizedDescription)")
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        showMessage("页面加载失败：\(error.localizedDescription)")
    }
}
