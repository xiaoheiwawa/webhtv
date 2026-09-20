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
        loadButton.addTarget(self, action: #selector(loadConfigTapped), for: .touchUpInside)
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

    @objc private func loadConfigTapped() {
        let url = urlField.text ?? ""
        guard !url.isEmpty else { return }
        urlField.resignFirstResponder()
        UserDefaults.standard.set(url, forKey: "configURL")
        loadConfig(url: url)
    }

    /// Loads the config (and depot hops) off the main thread: `ConfigFetcher` is synchronous and
    /// would otherwise block the UI up to the network timeout.
    private func loadConfig(url: String) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            guard let result = self.fetchConfig(url: url) else {
                DispatchQueue.main.async { self.presentAlert("配置加载失败") }
                return
            }
            do {
                let parsed = try SiteConfig.parse(data: result.data)
                let home = SiteConfig.homeKey(data: result.data)
                DispatchQueue.main.async {
                    self.apply(parsed, url: result.url)
                    ConfigStore.upsert(StoredConfig(type: 0, url: url, name: parsed.first?.name ?? "config", logo: ""))
                    self.openHome(sites: parsed, home: home)
                }
            } catch {
                DispatchQueue.main.async { self.presentAlert(error.localizedDescription) }
            }
        }
    }

    private func restoreLastConfig() {
        guard let last = UserDefaults.standard.string(forKey: "configURL"), !last.isEmpty else { return }
        urlField.text = last
        loadConfig(url: last)
    }

    /// Returns the config body plus the URL it was really loaded from (depots hop to `urls[0]`).
    private func fetchConfig(url: String) -> (data: Data, url: String)? {
        guard var data = ConfigFetcher.load(url: url) else { return nil }
        var resolved = url
        // depot (`urls` array): descend into first reachable config.
        if let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
           obj["sites"] == nil, let urls = obj["urls"] as? [String], let first = urls.first,
           let next = ConfigFetcher.load(url: first) {
            data = next
            resolved = first
        }
        return (data, resolved)
    }

    private func apply(_ parsed: [Site], url: String) {
        // Relative `homePage` values resolve against the config URL (Android `VodConfig.getUrl()`).
        SiteStore.currentURL = url
        sites = parsed.sorted { $0.name < $1.name }
        savedConfigs = ConfigStore.load()
        tableView.reloadData()
    }

    /// Mirrors Android `VodConfig`: open the `home` site (or the first WebHome site) on launch.
    private func openHome(sites: [Site], home: String) {
        var target = sites.first { $0.isHome }
        if !home.isEmpty, let preferred = sites.first(where: { $0.key == home && $0.isHome }) { target = preferred }
        guard let target else { return }
        SiteStore.current = target
        navigationController?.popToRootViewController(animated: false)
        navigationController?.pushViewController(WebHomeViewController(site: target), animated: true)
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
            loadConfigTapped()
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
