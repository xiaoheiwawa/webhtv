import UIKit

/// Launcher: enter a TVBox config URL (or raw JSON), load sites, open a site's WebHome.
/// Also persists the config list and restores the last-used config on launch.
final class HomeViewController: UIViewController {

    private let urlField = UITextField()
    private let loadButton = UIButton(type: .system)
    private let tableView = UITableView()
    private var sites: [Site] = []
    private var savedConfigs: [StoredConfig] = []

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "WebHomeTV"
        view.backgroundColor = .black
        configureLayout()
        loadButton.addTarget(self, action: #selector(loadConfig), for: .touchUpInside)
        savedConfigs = ConfigStore.load()
        restoreLastConfig()
    }

    private func configureLayout() {
        urlField.placeholder = "输入 TVBox 配置地址或直接 JSON"
        urlField.textColor = .lightText
        urlField.autocapitalizationType = .none
        urlField.autocorrectionType = .no
        urlField.keyboardType = .URL
        urlField.clearButtonMode = .whileEditing
        urlField.font = .systemFont(ofSize: 15)
        urlField.layer.cornerRadius = 6

        loadButton.setTitle("加载配置", for: .normal)
        loadButton.setTitleColor(.systemBlue, for: .normal)

        let inputLine = UIStackView(arrangedSubviews: [urlField, loadButton])
        inputLine.axis = .horizontal
        inputLine.spacing = 8
        inputLine.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(inputLine)

        tableView.dataSource = self
        tableView.delegate = self
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "cell")
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "cfg")
        tableView.backgroundColor = .black
        tableView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(tableView)

        NSLayoutConstraint.activate([
            inputLine.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 12),
            inputLine.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            inputLine.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            tableView.topAnchor.constraint(equalTo: inputLine.bottomAnchor, constant: 8),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }

    @objc private func loadConfig() {
        let url = urlField.text ?? ""
        guard !url.isEmpty else { return }
        UserDefaults.standard.set(url, forKey: "configURL")
        if let data = fetchConfig(url: url) {
            do {
                let parsed = try SiteConfig.parse(data: data)
                apply(parsed)
                ConfigStore.upsert(StoredConfig(type: 0, url: url, name: parsed.first?.name ?? "config", logo: ""))
            } catch {
                presentAlert(error.localizedDescription)
            }
        } else {
            presentAlert("配置加载失败")
        }
    }

    private func restoreLastConfig() {
        if let last = UserDefaults.standard.string(forKey: "configURL"), !last.isEmpty {
            urlField.text = last
            if let data = fetchConfig(url: last) {
                if let parsed = try? SiteConfig.parse(data: data) {
                    apply(parsed)
                }
            }
        }
    }

    private func fetchConfig(url: String) -> Data? {
        urlField.resignFirstResponder()
        var data = ConfigFetcher.load(url: url)
        // depot (`urls` array): descend into first reachable config.
        if let obj = data.flatMap({ try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }),
           obj["sites"] == nil, let urls = obj["urls"] as? [String], let first = urls.first {
            data = ConfigFetcher.load(url: first)
        }
        return data
    }

    private func apply(_ parsed: [Site]) {
        sites = parsed.sorted { $0.name < $1.name }
        savedConfigs = ConfigStore.load()
        tableView.reloadData()
    }

    private func presentAlert(_ message: String) {
        let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "好", style: .default))
        present(alert, animated: true)
    }
}

extension HomeViewController: UITableViewDataSource, UITableViewDelegate {
    func numberOfSections(in tableView: UITableView) -> Int { 2 }
    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        section == 0 ? "已存配置" : "站点"
    }
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        section == 0 ? savedConfigs.count : sites.count
    }
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        if indexPath.section == 0 {
            let cell = tableView.dequeueReusableCell(withIdentifier: "cfg", for: indexPath)
            let cfg = savedConfigs[indexPath.row]
            cell.backgroundColor = .black
            cell.textLabel?.textColor = .systemBlue
            cell.textLabel?.font = .systemFont(ofSize: 14)
            cell.textLabel?.text = cfg.name.isEmpty ? cfg.url : "\(cfg.name)"
            return cell
        }
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath)
        let site = sites[indexPath.row]
        cell.backgroundColor = .black
        cell.textLabel?.textColor = .white
        cell.textLabel?.font = .systemFont(ofSize: 15)
        cell.textLabel?.text = site.name.isEmpty ? site.key : "\(site.name)  (\(site.key))"
        cell.accessoryType = site.isHome ? .disclosureIndicator : .none
        return cell
    }
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        if indexPath.section == 0 {
            urlField.text = savedConfigs[indexPath.row].url
            loadConfig()
            return
        }
        let site = sites[indexPath.row]
        SiteStore.current = site
        if site.isHome {
            let vc = WebHomeViewController(site: site)
            navigationController?.pushViewController(vc, animated: true)
        } else {
            presentAlert("该站点没有 WebHome 首页")
        }
    }
}
