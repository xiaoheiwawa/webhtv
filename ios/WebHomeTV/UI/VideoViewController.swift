import UIKit
import AVKit
import AVFoundation

/// AVPlayerViewController host with an on-screen remote-control panel that drives
/// `PlayerManager.shared`. PiP is attached to this controller.
final class VideoViewController: AVPlayerViewController, AVPictureInPictureControllerDelegate {

    private let panel = UIStackView()
    private let row1 = UIStackView()
    private let row2 = UIStackView()
    private let row3 = UIStackView()

    override func viewDidLoad() {
        super.viewDidLoad()
        player = PlayerManager.shared.player
        showsPlaybackControls = true
        view.backgroundColor = .black
        buildPanel()
        PlayerManager.shared.attachPIP(to: self)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        // keep panel visible above default controls
        view.bringSubviewToFront(panel)
    }

    // MARK: - Panel

    private func buildPanel() {
        panel.axis = .vertical
        panel.spacing = 8
        panel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(panel)

        row1.axis = .horizontal
        row1.spacing = 12
        row1.addArrangedSubview(makeButton("⏪", #selector(prevTapped)))
        row1.addArrangedSubview(makeButton("⏵/⏸", #selector(playPauseTapped)))
        row1.addArrangedSubview(makeButton("⏩", #selector(nextTapped)))
        row1.addArrangedSubview(makeButton("-15s", #selector(backwardTapped)))
        row1.addArrangedSubview(makeButton("+15s", #selector(forwardTapped)))

        row2.axis = .horizontal
        row2.spacing = 12
        row2.addArrangedSubview(makeButton("倍速", #selector(speedTapped)))
        row2.addArrangedSubview(makeButton("音轨", #selector(audioTapped)))
        row2.addArrangedSubview(makeButton("字幕", #selector(subtitleTapped)))
        row2.addArrangedSubview(makeButton("PiP", #selector(pipTapped)))
        row2.addArrangedSubview(makeButton("截图", #selector(screenshotTapped)))

        row3.axis = .horizontal
        row3.spacing = 12
        row3.addArrangedSubview(makeButton("AirPlay", #selector(airplayTapped)))
        row3.addArrangedSubview(makeButton("返回", #selector(backTapped)))

        panel.addArrangedSubview(row1)
        panel.addArrangedSubview(row2)
        panel.addArrangedSubview(row3)

        NSLayoutConstraint.activate([
            panel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            panel.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -24),
        ])
    }

    private func makeButton(_ title: String, _ action: Selector) -> UIButton {
        let b = UIButton(type: .system)
        b.setTitle(title, for: .normal)
        b.setTitleColor(.white, for: .normal)
        b.backgroundColor = UIColor.white.withAlphaComponent(0.2)
        b.layer.cornerRadius = 8
        b.addTarget(self, action: action, for: .touchUpInside)
        b.translatesAutoresizingMaskIntoConstraints = false
        b.widthAnchor.constraint(greaterThanOrEqualToConstant: 56).isActive = true
        b.heightAnchor.constraint(equalToConstant: 32).isActive = true
        return b
    }

    // MARK: - Actions

    @objc private func playPauseTapped() { PlayerManager.shared.togglePlayPause() }
    @objc private func nextTapped() { PlayerManager.shared.next() }
    @objc private func prevTapped() { PlayerManager.shared.prev() }
    @objc private func backwardTapped() { PlayerManager.shared.seekRelative(-15) }
    @objc private func forwardTapped() { PlayerManager.shared.seekRelative(15) }
    @objc private func speedTapped() { PlayerManager.shared.cycleSpeed(); flash("\(PlayerManager.shared.status.rate)x") }
    @objc private func audioTapped() { PlayerManager.shared.cycleAudioTrack() }
    @objc private func subtitleTapped() { PlayerManager.shared.cycleSubtitleTrack() }
    @objc private func pipTapped() {
        if PlayerManager.shared.isPIPActive { PlayerManager.shared.stopPIP() }
        else { PlayerManager.shared.startPIP() }
    }
    @objc private func screenshotTapped() {
        guard let img = PlayerManager.shared.screenshot(), let data = img.pngData() else {
            flash("截图失败"); return
        }
        let size = data.count
        flash("已截图 \(size/1024) KB")
    }
    @objc private func airplayTapped() {
        let vc = AVRoutePickerView(frame: CGRect(x: 0, y: 0, width: 1, height: 1))
        view.addSubview(vc)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { vc.showRoutePicker() }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { vc.removeFromSuperview() }
    }
    @objc private func backTapped() { PlayerManager.shared.stop(); dismiss(animated: true) }

    private func flash(_ text: String) {
        // minimal toast: set panel button title? use a quick label
        let label = UILabel()
        label.text = text
        label.textColor = .white
        label.backgroundColor = UIColor.black.withAlphaComponent(0.7)
        label.textAlignment = .center
        label.layer.cornerRadius = 8
        label.clipsToBounds = true
        label.frame = CGRect(x: 0, y: 0, width: 160, height: 40)
        label.center = view.center
        view.addSubview(label)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { label.removeFromSuperview() }
    }

    // MARK: - PiP delegate

    func pictureInPictureControllerWillStartPictureInPicture(_ c: AVPictureInPictureController) {}
    func pictureInPictureControllerDidStopPictureInPicture(_ c: AVPictureInPictureController) {}
}
