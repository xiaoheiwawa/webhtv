import UIKit

@main
final class AppDelegate: UIResponder, UIApplicationDelegate {

    var window: UIWindow?

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        // Start local HTTP proxy for `net.resourceUrl` / spider playback.
        try? LocalHTTPProxy.shared.start()

        // Configure playback presentation (AVPlayerViewController).
        VideoPresenter.install()

        let window = UIWindow(frame: UIScreen.main.bounds)
        let root = UINavigationController(rootViewController: HomeViewController())
        window.rootViewController = root
        window.makeKeyAndVisible()
        self.window = window
        return true
    }
}
