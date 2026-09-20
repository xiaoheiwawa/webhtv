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
        userContent.add(bridge, name: "fongmi")

        loadHome()
    }

    private func loadHome() {
        let page = site.homePage
        if page.hasPrefix("http://") || page.hasPrefix("https://") {
            if let url = URL(string: page) {
                webView.load(URLRequest(url: url))
                return
            }
        }
        // relative `./xxx.html`: resolve against config URL.
        if let base = SiteStore.currentURL, !base.isEmpty,
           let resolved = URL(string: page, relativeTo: URL(string: base)) {
            webView.load(URLRequest(url: resolved))
            return
        }
        // local file or inline
        if page.hasPrefix("file://") || page.hasPrefix("assets://") {
            let path = page.replacingOccurrences(of: "file://", with: "").replacingOccurrences(of: "assets://", with: "")
            if let url = Bundle.main.url(forResource: path, withExtension: nil) {
                webView.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
                return
            }
        }
        webView.loadHTMLString(page, baseURL: nil)
    }
}

extension WebHomeViewController: WKNavigationDelegate {
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        // optional: log loaded title
    }
}
