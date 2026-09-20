import UIKit

/// Launcher: enter a TVBox config URL (or raw JSON), load sites, then open a site's WebHome.
final class HomeViewController: UIViewController {

    private let urlField = UITextField()
    private let loadButton = UIButton(type: .system)
    private let tableView = UITableView()
    private var sites: [Site] = []

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        configureLayout()
        loadButton.addTarget(self, action: #selector(loadConfig), for: .touchUpInside)
    }

    private func configureLayout() {
        urlField.placeholder = "输入 TVBox 配置地址 (http://... 或直接 JSON)"
        urlField.textColor = .lightText
        urlField.autocapitalizationType = .none
        urlField.autocorrectionType = .no
        urlField.keyboardType = .URL
        urlField.clearButtonMode = .whileEditing
        urlField.font = .systemFont(ofSize: 15)
        if let cfg = UserDefaults.standard.string(forKey: "configURL") {
            urlField.text = cfg
        }
        urlField.translatesAutoresizingMaskIntoConstraints = false
        urlField.layer.cornerRadius = 6
        urlField.setLeftPaddingPoints(10)

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
        guard let url = urlField.text, !url.isEmpty else { return }
        UserDefaults.standard.set(url, forKey: "configURL")
        urlField.resignFirstResponder()
        loadButton.isEnabled = false
        loadButton.setTitle("加载中…", for: .normal)

        let fetched = ConfigFetcher.load(url: url)
        loadButton.isEnabled = true
        loadButton.setTitle("加载配置", for: .normal)
        guard let data = fetched else {
            presentAlert("配置加载失败")
            return
        }
        do {
            var parsed = try SiteConfig.parse(data: data)
            if parsed.isEmpty, let urls = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any], let arr = urls["urls"] as? [String], let first = arr.first, let d = ConfigFetcher.load(url: first) {
                parsed = (try? SiteConfig.parse(data: d)) ?? []
            }
            sites = parsed.filter { !$0.isSpider || $0.isHome || true }.sorted { $0.name < $1.name }
            SiteStore.currentURL = url
            tableView.reloadData()
        } catch {
            presentAlert("\(error.localizedDescription)")
        }
    }

    private func presentAlert(_ message: String) {
        let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "好", style: .default))
        present(alert, animated: true)
    }
}

extension HomeViewController: UITableViewDataSource, UITableViewDelegate {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        sites.count
    }
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
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

private extension UITextField {
    func setLeftPaddingPoints(_ amount: CGFloat) {
        let v = UIView(frame: CGRect(x: 0, y: 0, width: amount, height: 1))
        leftView = v
        leftViewMode = .always
    }
}
