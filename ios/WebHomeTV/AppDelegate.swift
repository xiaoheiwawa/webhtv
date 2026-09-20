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
        // Native phone-style UI: bottom tab bar (点播 / 直播 / 设置), mirroring Android mobile.
        window.rootViewController = MainTabController()
        window.makeKeyAndVisible()
        self.window = window
        return true
    }
}
