import UIKit

/// Live channel browser mirroring Android's live tab: group sections + channel rows.
/// Loads a live config URL (TVBox live JSON or m3u `#genre#` list) from `UserDefaults["liveConfig"]`.
final class LiveViewController: UITableViewController {

    private var groups: [LiveGroup] = []
    private let refresh = UIRefreshControl()

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "直播"
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "cell")
        refresh.addTarget(self, action: #selector(reload), for: .valueChanged)
        tableView.refreshControl = refresh
        navigationItem.rightBarButtonItem = UIBarButtonItem(title: "地址", style: .plain, target: self, action: #selector(setURL))
        reload()
    }

    @objc private func reload() {
        let url = UserDefaults.standard.string(forKey: "liveConfig") ?? ""
        guard !url.isEmpty else {
            groups = []
            tableView.reloadData()
            refresh.endRefreshing()
            return
        }
        navigationItem.prompt = nil
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let text = (Network.sync(url: url).content)
            DispatchQueue.main.async {
                guard let self else { return }
                if text.hasPrefix("{") {
                    self.groups = LiveParser.parseGroups(text)
                } else {
                    self.groups = LiveParser.parseM3U(text)
                }
                self.tableView.reloadData()
                self.refresh.endRefreshing()
            }
        }
    }

    @objc private func setURL() {
        let ac = UIAlertController(title: "直播地址", message: "输入 TVBox live / m3u 地址", preferredStyle: .alert)
        ac.addTextField { $0.text = UserDefaults.standard.string(forKey: "liveConfig") ?? ""; $0.keyboardType = .URL }
        ac.addAction(UIAlertAction(title: "加载", style: .default) { [weak self, weak ac] _ in
            let url = ac?.textFields?.first?.text ?? ""
            UserDefaults.standard.set(url, forKey: "liveConfig")
            self?.reload()
        })
        ac.addAction(UIAlertAction(title: "取消", style: .cancel))
        present(ac, animated: true)
    }

    override func numberOfSections(in tableView: UITableView) -> Int { max(groups.count, 1) }
    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        groups.isEmpty ? nil : groups[section].name
    }
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        groups.isEmpty ? 1 : groups[section].channels.count
    }
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath)
        if groups.isEmpty {
            cell.textLabel?.text = "未配置直播（点右上角输入地址）"
            cell.textLabel?.textColor = .secondaryLabel
            return cell
        }
        cell.textLabel?.text = groups[indexPath.section].channels[indexPath.row].name
        cell.textLabel?.textColor = .label
        return cell
    }
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard !groups.isEmpty else { return }
        let ch = groups[indexPath.section].channels[indexPath.row]
        PlayerManager.shared.play(url: ch.url, title: ch.name)
    }
}
