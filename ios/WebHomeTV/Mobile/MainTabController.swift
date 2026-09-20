import UIKit

/// Android-mobile-style root: a bottom tab bar with 点播 / 直播 / 设置.
/// Mirrors `HomeActivity` + `menu_nav`.
final class MainTabController: UITabBarController {

    override func viewDidLoad() {
        super.viewDidLoad()

        let vodNav = UINavigationController(rootViewController: VodBrowserViewController())
        vodNav.tabBarItem = UITabBarItem(title: "点播", image: UIImage(systemName: "play.rectangle"), selectedImage: nil)

        let liveNav = UINavigationController(rootViewController: LiveViewController())
        liveNav.tabBarItem = UITabBarItem(title: "直播", image: UIImage(systemName: "tv"), selectedImage: nil)

        let settingNav = UINavigationController(rootViewController: SettingsViewController())
        settingNav.tabBarItem = UITabBarItem(title: "设置", image: UIImage(systemName: "gearshape"), selectedImage: nil)

        viewControllers = [vodNav, liveNav, settingNav]
        selectedIndex = 0
        TabBarAppearance.apply(to: tabBar)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        if ConfigManager.shared.sites.isEmpty {
            ConfigManager.shared.restore()
        }
        // Refresh the vod browser once a config is restored.
        if let nav = viewControllers?.first as? UINavigationController,
           let browser = nav.viewControllers.first as? VodBrowserViewController {
            browser.reloadFromConfig()
        }
    }
}

enum TabBarAppearance {
    static func apply(to bar: UITabBar) {
        if #available(iOS 15.0, *) {
            let appearance = UITabBarAppearance()
            appearance.configureWithOpaqueBackground()
            appearance.backgroundColor = .systemBackground
            bar.standardAppearance = appearance
            bar.scrollEdgeAppearance = appearance
        }
    }
}
