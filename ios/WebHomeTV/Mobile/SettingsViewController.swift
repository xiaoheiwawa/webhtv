import UIKit

/// Android-mobile-style 设置 tab. Grouped table with config / play / about sections.
final class SettingsViewController: UITableViewController {

    private enum SettingAction { case loadConfig, savedConfigs, rate, about }

    private let sections: [(String, [(String, SettingAction)])] = [
        ("配置", [
            ("加载/切换配置", .loadConfig),
            ("已存配置", .savedConfigs),
        ]),
        ("播放", [
            ("默认播放速率", .rate),
        ]),
        ("关于", [
            ("版本", .about),
        ]),
    ]

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "设置"
        tableView.isScrollEnabled = false
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "cell")
        tableView.backgroundColor = .systemGroupedBackground
    }

    override func numberOfSections(in tableView: UITableView) -> Int { sections.count }
    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? { sections[section].0 }
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { sections[section].1.count }
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath)
        let (title, action) = sections[indexPath.section].1[indexPath.row]
        cell.textLabel?.text = title
        cell.accessoryType = action == .rate ? .detailButton : .disclosureIndicator
        if action == .rate {
            cell.detailTextLabel?.text = "\(PlayerManager.shared.status.rate)x"
        }
        return cell
    }
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        switch sections[indexPath.section].1[indexPath.row].1 {
        case .loadConfig: promptLoad()
        case .savedConfigs: showSavedConfigs()
        case .rate: cycleRate()
        case .about: showAbout()
        }
    }

    private func promptLoad() {
        let ac = UIAlertController(title: "加载配置", message: "输入 TVBox 配置地址或直接 JSON", preferredStyle: .alert)
        ac.addTextField { $0.placeholder = "https://... 或 JSON"; $0.keyboardType = .URL }
        ac.addAction(UIAlertAction(title: "加载", style: .default) { [weak self, weak ac] _ in
            let url = ac?.textFields?.first?.text ?? ""
            guard !url.isEmpty else { return }
            self?.loadConfig(url)
        })
        ac.addAction(UIAlertAction(title: "取消", style: .cancel))
        present(ac, animated: true)
    }

    private func loadConfig(_ url: String) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let ok = ConfigManager.shared.load(url: url) != nil
            DispatchQueue.main.async {
                self?.view.makeToast(ok ? "配置已加载" : "配置加载失败")
            }
        }
    }

    private func showSavedConfigs() {
        let configs = ConfigStore.load()
        let ac = UIAlertController(title: "已存配置", message: nil, preferredStyle: .actionSheet)
        for c in configs {
            ac.addAction(UIAlertAction(title: c.name.isEmpty ? c.url : c.name, style: .default) { [weak self] _ in
                self?.loadConfig(c.url)
            })
        }
        ac.addAction(UIAlertAction(title: "取消", style: .cancel))
        present(ac, animated: true)
    }

    private func cycleRate() {
        let rate = PlayerManager.shared.cycleSpeed()
        view.makeToast("\(rate)x")
        tableView.reloadData()
    }

    private func showAbout() {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let ac = UIAlertController(title: "WebHomeTV iOS", message: "版本 \(version)\n与安卓手机端同构的原生界面", preferredStyle: .alert)
        ac.addAction(UIAlertAction(title: "好", style: .default))
        present(ac, animated: true)
    }
}
