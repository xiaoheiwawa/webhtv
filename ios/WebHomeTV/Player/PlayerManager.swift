import Foundation
import AVFoundation
import Combine
import UIKit

/// Playback state surfaced to the WebHome bridge (`player.status`).
struct PlaybackStatus {
    var url: String = ""
    var position: Int64 = 0
    var duration: Int64 = 0
    var isPlaying: Bool = false
    var state: Int = 0

    var dict: [String: Any] {
        [
            "url": url,
            "position": position,
            "duration": duration,
            "isPlaying": isPlaying,
            "state": state,
            "responseType": "json",
        ]
    }
}

/// AVPlayer-backed playback controller. Singleton so the WebHome bridge can drive playback
/// from anywhere. Mirrors the control surface of Android's `PlayerManager`.
final class PlayerManager: NSObject {

    static let shared = PlayerManager()

    private(set) var player: AVPlayer?
    private var timeObserver: Any?
    private var endObserver: NSObjectProtocol?

    private(set) var status = PlaybackStatus()
    /// Present the player UI for playback (supplied by the app's root controller).
    var presenter: ((PlayerManager) -> Void)?

    private override init() {
        super.init()
        try? AVAudioSession.sharedInstance().setCategory(.playback)
    }

    // MARK: - Playback

    func play(url: String, title: String? = nil) {
        guard let u = URL(string: url) else { return }
        let item = AVPlayerItem(url: u)
        player?.pause()
        removeObservers()
        let p = AVPlayer(playerItem: item)
        self.player = p
        status.url = url
        observe(p)
        presenter?(self)
        p.play()
        status.isPlaying = true
    }

    func stop() {
        player?.pause()
        removeObservers()
        player = nil
        status = PlaybackStatus()
    }

    // MARK: - Controls

    func togglePlayPause() {
        guard let player else { return }
        if status.isPlaying {
            player.pause()
            status.isPlaying = false
        } else {
            player.play()
            status.isPlaying = true
        }
    }
    func pause() {
        player?.pause()
        status.isPlaying = false
    }
    func resume() {
        player?.play()
        status.isPlaying = true
    }
    func seek(to seconds: Double) {
        let time = CMTime(seconds: seconds, preferredTimescale: 600)
        player?.seek(to: time)
        status.position = Int64(seconds)
    }
    func next() { /* playlist advance — wired when a playlist exists */ }
    func prev() { /* playlist advance — wired when a playlist exists */ }
    func replay() {
        player?.seek(to: .zero)
        player?.play()
        status.isPlaying = true
    }
    func repeatToggle() {
        status.isPlaying = !status.isPlaying
        if status.isPlaying { player?.play() } else { player?.pause() }
    }

    // MARK: - Observers

    private func observe(_ p: AVPlayer) {
        timeObserver = p.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.5, preferredTimescale: 600), queue: .main) { [weak self] time in
            self?.status.position = Int64(time.seconds)
            self?.status.duration = Int64(p.currentItem?.duration.seconds ?? 0)
        }
        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: p.currentItem,
            queue: .main
        ) { [weak self] _ in
            self?.status.isPlaying = false
        }
    }

    private func removeObservers() {
        if let timeObserver, let player {
            player.removeTimeObserver(timeObserver)
        }
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
        }
        timeObserver = nil
        endObserver = nil
    }
}
