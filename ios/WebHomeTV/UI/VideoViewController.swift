import UIKit
import AVKit

/// Thin presenter that wraps an AVPlayerViewController around `PlayerManager.shared.player`.
final class VideoViewController: AVPlayerViewController {

    override func viewDidLoad() {
        super.viewDidLoad()
        player = PlayerManager.shared.player
        showsPlaybackControls = true
    }
}

/// Configures playback presentation: presenting an AVPlayerViewController from the top controller.
enum VideoPresenter {
    static func install() {
        PlayerManager.shared.presenter = { manager in
            DispatchQueue.main.async {
                guard let top = Self.topViewController() else { return }
                let vc = VideoViewController()
                vc.player = manager.player
                top.present(vc, animated: true)
            }
        }
    }

    static func topViewController() -> UIViewController? {
        guard let root = UIApplication.shared.connectedScenes
                .compactMap({ ($0 as? UIWindowScene)?.keyWindow })
                .first?.rootViewController else { return nil }
        var top = root
        while let presented = top.presentedViewController { top = presented }
        return top
    }
}
