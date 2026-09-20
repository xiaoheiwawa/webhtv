import UIKit
import AVKit

/// Native detail + playback screen, mirroring Android `VideoActivity`:
/// poster + meta + description + a flag/episode picker, then AVPlayer playback.
final class VodDetailViewController: UIViewController {

    private let site: Site
    private let vodId: String
    private var vod: Vod?
    private var engine: SiteEngine?

    private let scrollView = UIScrollView()
    private let contentView = UIStackView()
    private let posterView = UIImageView()
    private let titleLabel = UILabel()
    private let metaLabel = UILabel()
    private let descLabel = UILabel()
    private var flagChips: [UIButton] = []
    private var episodeButtons: [UIButton] = []
    private let episodesStack = UIStackView()
    private let flagsStack = UIStackView()
    private var selectedFlag = 0
    private var selectedEpisode = 0

    init(site: Site, vodId: String, title: String, poster: String) {
        self.site = site
        self.vodId = vodId
        super.init(nibName: nil, bundle: nil)
        self.title = title.isEmpty ? "详情" : title
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        engine = VodService.shared.engine(for: site)
        configureLayout()
        loadDetail()
    }

    private func configureLayout() {
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scrollView)
        contentView.axis = .vertical
        contentView.spacing = 12
        contentView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(contentView)

        posterView.contentMode = .scaleAspectFill
        posterView.backgroundColor = .secondarySystemBackground
        posterView.clipsToBounds = true
        posterView.layer.cornerRadius = 10
        posterView.widthAnchor.constraint(equalToConstant: 120).isActive = true
        posterView.heightAnchor.constraint(equalToConstant: 168).isActive = true

        let titleArea = UIStackView(arrangedSubviews: [titleLabel, metaLabel])
        titleArea.axis = .vertical
        titleArea.spacing = 6
        titleLabel.font = .boldSystemFont(ofSize: 18)
        titleLabel.numberOfLines = 0
        metaLabel.font = .systemFont(ofSize: 13)
        metaLabel.textColor = .secondaryLabel
        metaLabel.numberOfLines = 0

        let topRow = UIStackView(arrangedSubviews: [posterView, titleArea])
        topRow.axis = .horizontal
        topRow.alignment = .top
        topRow.spacing = 12
        topRow.translatesAutoresizingMaskIntoConstraints = false

        descLabel.font = .systemFont(ofSize: 14)
        descLabel.textColor = .secondaryLabel
        descLabel.numberOfLines = 0

        let descHeader = UILabel()
        descHeader.text = "简介"
        descHeader.font = .boldSystemFont(ofSize: 15)

        let flagHeader = UILabel()
        flagHeader.text = "片源"
        flagHeader.font = .boldSystemFont(ofSize: 15)

        flagsStack.axis = .horizontal
        flagsStack.spacing = 8
        flagsStack.alignment = .leading

        let episodeHeader = UILabel()
        episodeHeader.text = "选集"
        episodeHeader.font = .boldSystemFont(ofSize: 15)

        episodesStack.axis = .vertical
        episodesStack.spacing = 8
        episodesStack.alignment = .leading

        contentView.addArrangedSubview(topRow)
        contentView.addArrangedSubview(descHeader)
        contentView.addArrangedSubview(descLabel)
        contentView.addArrangedSubview(flagHeader)
        contentView.addArrangedSubview(flagsStack)
        contentView.addArrangedSubview(episodeHeader)
        contentView.addArrangedSubview(episodesStack)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            contentView.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: 12),
            contentView.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor, constant: 16),
            contentView.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor, constant: -16),
            contentView.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -16),
            contentView.widthAnchor.constraint(equalTo: scrollView.widthAnchor, constant: -32),
        ])
    }

    private func loadDetail() {
        guard let engine else { view.makeToast("站点无 spider"); return }
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            let r = engine.detail(id: self.vodId)
            DispatchQueue.main.async { self.apply(r) }
        }
    }

    private func apply(_ result: Result) {
        guard let vod = result.list.first else {
            view.makeToast(result.msg.isEmpty ? "详情为空" : result.msg)
            return
        }
        self.vod = vod
        title = vod.vodName
        titleLabel.text = vod.vodName
        var meta = [vod.typeName, vod.vodYear, vod.vodArea].filter { !$0.isEmpty }.joined(separator: " · ")
        if !vod.vodActor.isEmpty { meta += "\n主演：\(vod.vodActor)" }
        if !vod.vodDirector.isEmpty { meta += "\n导演：\(vod.vodDirector)" }
        metaLabel.text = meta
        descLabel.text = vod.vodContent.isEmpty ? "暂无简介" : vod.vodContent
        if let url = URL(string: vod.vodPic), !vod.vodPic.isEmpty {
            ImageLoader.shared.load(url: url) { [weak self] img in self?.posterView.image = img }
        }
        buildFlagsAndEpisodes()
    }

    private func buildFlagsAndEpisodes() {
        guard let vod else { return }
        flagChips.forEach { $0.removeFromSuperview() }
        episodeButtons.forEach { $0.removeFromSuperview() }
        flagChips = []
        episodeButtons = []
        let flags = vod.flags
        for (i, f) in flags.enumerated() {
            let b = makeChip(f.flag, selected: i == selectedFlag)
            b.tag = i
            b.addTarget(self, action: #selector(flagTapped(_:)), for: .touchUpInside)
            flagsStack.addArrangedSubview(b)
            flagChips.append(b)
        }
        renderEpisodes()
    }

    private func renderEpisodes() {
        guard let vod, vod.flags.indices.contains(selectedFlag) else { return }
        episodeButtons.forEach { $0.removeFromSuperview() }
        episodeButtons = []
        let eps = vod.flags[selectedFlag].episodes
        guard !eps.isEmpty else {
            appendNoEpisodes(vod)
            return
        }
        var row: UIStackView?
        var count = 0
        func nextRow() -> UIStackView {
            let s = UIStackView()
            s.axis = .horizontal
            s.spacing = 8
            s.alignment = .leading
            episodesStack.addArrangedSubview(s)
            return s
        }
        row = nextRow()
        for (i, ep) in eps.enumerated() {
            if count >= 6 { row = nextRow(); count = 0 }
            let b = UIButton(type: .system)
            b.setTitle(ep.name, for: .normal)
            b.titleLabel?.font = .systemFont(ofSize: 13)
            b.layer.cornerRadius = 6
            b.backgroundColor = .secondarySystemBackground
            b.setTitleColor(.label, for: .normal)
            b.tag = i
            b.addTarget(self, action: #selector(episodeTapped(_:)), for: .touchUpInside)
            row?.addArrangedSubview(b)
            episodeButtons.append(b)
            count += 1
        }
        if let first = episodeButtons.first { episodeTapped(first) }
    }

    private func appendNoEpisodes(_ vod: Vod) {
        if !vod.vodPlayUrl.isEmpty {
            let b = makeChip("播放", selected: true)
            b.tag = 0
            b.addTarget(self, action: #selector(episodeTapped(_:)), for: .touchUpInside)
            episodeButtons.append(b)
            episodesStack.addArrangedSubview(b)
        } else {
            let l = UILabel()
            l.text = "无可播放资源"
            l.font = .systemFont(ofSize: 13)
            l.textColor = .secondaryLabel
            episodesStack.addArrangedSubview(l)
        }
    }

    private func makeChip(_ text: String, selected: Bool) -> UIButton {
        let b = UIButton(type: .system)
        b.setTitle(text, for: .normal)
        b.titleLabel?.font = .systemFont(ofSize: 13)
        b.layer.cornerRadius = 6
        b.backgroundColor = selected ? .systemBlue : .secondarySystemBackground
        b.setTitleColor(selected ? .white : .label, for: .normal)
        return b
    }

    @objc private func flagTapped(_ sender: UIButton) {
        selectedFlag = sender.tag
        for (i, b) in flagChips.enumerated() {
            let sel = i == selectedFlag
            b.backgroundColor = sel ? .systemBlue : .secondarySystemBackground
            b.setTitleColor(sel ? .white : .label, for: .normal)
        }
        renderEpisodes()
    }

    @objc private func episodeTapped(_ sender: UIButton) {
        selectedEpisode = sender.tag
        for (i, b) in episodeButtons.enumerated() {
            let sel = i == selectedEpisode
            b.backgroundColor = sel ? .systemBlue : .secondarySystemBackground
            b.setTitleColor(sel ? .white : .label, for: .normal)
        }
        play()
    }

    private func play() {
        guard let engine, let vod, vod.flags.indices.contains(selectedFlag) else { return }
        let flag = vod.flags[selectedFlag].flag
        let eps = vod.flags[selectedFlag].episodes
        // A single-play flag may carry the raw url in vodPlayUrl instead of episodes.
        if eps.isEmpty, vod.vodPlayUrl.isEmpty, selectedFlag > 0 { return }
        let targetRaw = eps.indices.contains(selectedEpisode) ? eps[selectedEpisode].url : vod.vodPlayUrl
        let epName = eps.indices.contains(selectedEpisode) ? eps[selectedEpisode].name : "播放"
        guard !targetRaw.isEmpty else { view.makeToast("无可播地址"); return }
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            let r = engine.player(flag: flag, id: targetRaw, vipFlags: [])
            DispatchQueue.main.async {
                let target = r.playUrl.isEmpty ? targetRaw : r.playUrl
                guard !target.isEmpty else { self.view.makeToast("解析失败"); return }
                PlayerManager.shared.play(url: target, title: "\(vod.vodName)  \(epName)")
            }
        }
    }

/// Entry point to open a vod into the detail screen, used by browser & search.
enum AppScreens {
    static func openVod(from vc: UIViewController, site: Site, vod: Vod) {
        let detail = VodDetailViewController(site: site, vodId: vod.vodId, title: vod.vodName, poster: vod.vodPic)
        vc.navigationController?.pushViewController(detail, animated: true)
    }
}
