import Foundation
import AVFoundation
import AVKit
import Combine
import UIKit

/// Playback state surfaced to the WebHome bridge (`player.status`).
struct PlaybackStatus {
    var url: String = ""
    var position: Int64 = 0
    var duration: Int64 = 0
    var isPlaying: Bool = false
    var state: Int = 0
    var rate: Float = 1.0
    var enableAudioTrack: Int = -1
    var enableSubtitleTrack: Int = -1

    var dict: [String: Any] {
        [
            "url": url,
            "position": position,
            "duration": duration,
            "isPlaying": isPlaying,
            "state": state,
            "rate": rate,
            "audioTrack": enableAudioTrack,
            "subtitleTrack": enableSubtitleTrack,
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
    private var tracksObserver: NSObjectProtocol?
    private var audioTracks: [AVMediaSelectionOption] = []
    private var subtitleTracks: [AVMediaSelectionOption] = []
    private var pipController: AVPictureInPictureController?

    private(set) var status = PlaybackStatus()
    /// Present the player UI for playback (supplied by the app's root controller).
    var presenter: ((PlayerManager) -> Void)?
    /// Called when picture-in-picture availability changes.
    var pipAvailabilityHandler: ((Bool) -> Void)?

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
        p.allowsExternalPlayback = true
        p.appliesMediaSelectionCriteriaAutomatically = false
        self.player = p
        status = PlaybackStatus()
        status.url = url
        observe(p)
        presenter?(self)
        p.play()
        status.isPlaying = true
    }

    func stop() {
        player?.pause()
        stopPIP()
        removeObservers()
        player = nil
        audioTracks = []
        subtitleTracks = []
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
    func seekRelative(_ delta: Double) {
        seek(to: Double(status.position) + delta)
    }
    func next() {
        seekRelative(15)
    }
    func prev() {
        seekRelative(-15)
    }
    func replay() {
        player?.seek(to: .zero)
        player?.play()
        status.isPlaying = true
    }
    func repeatToggle() {
        status.isPlaying = !status.isPlaying
        if status.isPlaying { player?.play() } else { player?.pause() }
    }

    // MARK: - Rate / speed

    /// Cycle through common playback speeds (1.0 、1.5、2.0、0.5).
    @discardableResult
    func cycleSpeed() -> Float {
        let speeds: [Float] = [1.0, 1.5, 2.0, 0.5]
        let next = speeds[(speeds.firstIndex(of: status.rate).map { ($0 + 1) % speeds.count }) ?? 0]
        setRate(next)
        return next
    }
    func setRate(_ rate: Float) {
        status.rate = rate
        guard let player else { return }
        if status.isPlaying {
            player.rate = rate
        } else {
            player.rate = 1.0
            status.rate = 1.0
        }
    }

    // MARK: - Tracks

    /// Load audio / subtitle media selection groups asynchronously.
    func loadTracks() {
        guard let item = player?.currentItem else { return }
        Task {
            if let group = item.asset.mediaSelectionGroup(forMediaCharacteristic: .audible) {
                self.audioTracks = group.options
            }
            if let group = item.asset.mediaSelectionGroup(forMediaCharacteristic: .legible) {
                self.subtitleTracks = group.options
            }
        }
    }

    /// Cycle to the next audio track.
    func cycleAudioTrack() {
        guard let item = player?.currentItem,
              let group = item.asset.mediaSelectionGroup(forMediaCharacteristic: .audible), !audioTracks.isEmpty else { return }
        let next = (status.enableAudioTrack + 1) % audioTracks.count
        item.select(audioTracks[next], in: group)
        status.enableAudioTrack = next
    }

    /// Cycle to the next subtitle track (or turn them off).
    func cycleSubtitleTrack() {
        guard let item = player?.currentItem,
              let group = item.asset.mediaSelectionGroup(forMediaCharacteristic: .legible), !subtitleTracks.isEmpty else { return }
        let next = (status.enableSubtitleTrack + 1) % (subtitleTracks.count + 1)
        if next >= subtitleTracks.count {
            item.select(nil, in: group)
            status.enableSubtitleTrack = -1
        } else {
            item.select(subtitleTracks[next], in: group)
            status.enableSubtitleTrack = next
        }
    }

    // MARK: - Picture in Picture

    func attachPIP(to controller: AVPictureInPictureControllerDelegate?) {
        guard let player, AVPictureInPictureController.isPictureInPictureSupported() else { return }
        let pip = AVPictureInPictureController(playerLayer: AVPlayerLayer(player: player))
        pip?.delegate = controller
        pipController = pip
        pipAvailabilityHandler?(pip?.isPictureInPicturePossible ?? false)
    }
    func startPIP() {
        guard let pip = pipController, pip.isPictureInPicturePossible else { return }
        pip.startPictureInPicture()
    }
    func stopPIP() {
        pipController?.stopPictureInPicture()
        pipController = nil
    }
    var isPIPActive: Bool { pipController?.isPictureInPictureActive ?? false }

    // MARK: - Screenshot

    /// Capture the current frame into a UIImage.
    func screenshot() -> UIImage? {
        guard let asset = player?.currentItem?.asset else { return nil }
        let gen = AVAssetImageGenerator(asset: asset)
        gen.appliesPreferredTrackTransform = true
        let time = player?.currentTime() ?? .zero
        guard let cg = try? gen.copyCGImage(at: time, actualTime: nil) else { return nil }
        return UIImage(cgImage: cg)
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
        // Re-prime track list once the item is ready.
        tracksObserver = NotificationCenter.default.addObserver(
            forName: AVPlayerItem.newAccessLogEntryNotification,
            object: p.currentItem,
            queue: .main
        ) { [weak self] _ in self?.loadTracks() }
    }

    private func removeObservers() {
        if let timeObserver, let player {
            player.removeTimeObserver(timeObserver)
        }
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
        }
        if let tracksObserver {
            NotificationCenter.default.removeObserver(tracksObserver)
        }
        timeObserver = nil
        endObserver = nil
        tracksObserver = nil
    }
}




