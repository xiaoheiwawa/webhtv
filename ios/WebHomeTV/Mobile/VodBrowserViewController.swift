import UIKit

/// Native VOD browser mirroring Android's mobile `VodFragment`:
/// a category chip row + a video grid, with a site switcher / search / config entry.
final class VodBrowserViewController: UIViewController {

    private var sites: [Site] = ConfigManager.shared.sites
    private var currentSite: Site?
    private var engine: SiteEngine?
    private var classes: [VodClass] = []
    private var vods: [Vod] = []
    private var page = 1
    private var hasMore = true

    private let categoryView = UICollectionView(frame: .zero, collectionViewLayout: UICollectionViewFlowLayout())
    private let gridView = UICollectionView(frame: .zero, collectionViewLayout: UICollectionViewFlowLayout())
    private let titleButton = UIButton(type: .system)
    private let searchButton = UIButton(type: .system)
    private let configButton = UIButton(type: .system)
    private var selectedClass = -1

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "点播"
        view.backgroundColor = .systemBackground
        configureToolbar()
        configureCollections()
        reloadFromConfig()
        NotificationCenter.default.addObserver(self, selector: #selector(configChanged), name: .configChanged, object: nil)
    }

    @objc private func configChanged() {
        reloadFromConfig()
    }
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setNavigationBarHidden(false, animated: false)
    }

    // MARK: - Toolbar

    private func configureToolbar() {
        titleButton.setTitleColor(.label, for: .normal)
        titleButton.titleLabel?.font = .boldSystemFont(ofSize: 17)
        titleButton.addTarget(self, action: #selector(changeSite), for: .touchUpInside)
        titleButton.setTitle("选择站点", for: .normal)

        searchButton.setImage(UIImage(systemName: "magnifyingglass"), for: .normal)
        searchButton.addTarget(self, action: #selector(openSearch), for: .touchUpInside)

        configButton.setImage(UIImage(systemName: "gearshape"), for: .normal)
        configButton.addTarget(self, action: #selector(openConfigs), for: .touchUpInside)

        navigationItem.leftBarButtonItem = UIBarButtonItem(customView: titleButton)
        navigationItem.rightBarButtonItems = [
            UIBarButtonItem(customView: configButton),
            UIBarButtonItem(customView: searchButton),
        ]
    }

    private func configureCollections() {
        let chipLayout = UICollectionViewFlowLayout()
        chipLayout.scrollDirection = .horizontal
        chipLayout.sectionInset = UIEdgeInsets(top: 6, left: 8, bottom: 6, right: 8)
        chipLayout.minimumInteritemSpacing = 8
        categoryView.collectionViewLayout = chipLayout
        categoryView.backgroundColor = .clear
        categoryView.delegate = self
        categoryView.dataSource = self
        categoryView.showsHorizontalScrollIndicator = false
        categoryView.register(CategoryChipCell.self, forCellWithReuseIdentifier: CategoryChipCell.id)
        categoryView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(categoryView)

        let gridLayout = UICollectionViewFlowLayout()
        gridLayout.scrollDirection = .vertical
        gridLayout.minimumInteritemSpacing = 8
        gridLayout.minimumLineSpacing = 12
        gridLayout.sectionInset = UIEdgeInsets(top: 4, left: 8, bottom: 8, right: 8)
        gridView.collectionViewLayout = gridLayout
        gridView.backgroundColor = .clear
        gridView.delegate = self
        gridView.dataSource = self
        gridView.alwaysBounceVertical = true
        gridView.register(VodCell.self, forCellWithReuseIdentifier: VodCell.id)
        gridView.register(LoadingFooter.self, forSupplementaryViewOfKind: UICollectionView.elementKindSectionFooter, withReuseIdentifier: LoadingFooter.id)
        gridView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(gridView)

        NSLayoutConstraint.activate([
            categoryView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            categoryView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            categoryView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            categoryView.heightAnchor.constraint(equalToConstant: 44),

            gridView.topAnchor.constraint(equalTo: categoryView.bottomAnchor),
            gridView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            gridView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            gridView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }

    // MARK: - Data

    func reloadFromConfig() {
        sites = ConfigManager.shared.sites
        guard !sites.isEmpty else { return }
        // Prefer a spider site; fall back to any site.
        if let current = sites.first(where: { $0.key == SiteStore.current?.key }) {
            currentSite = current
        } else if let spider = sites.first(where: { $0.isSpider }) {
            currentSite = spider
        } else {
            currentSite = sites.first
        }
        guard let site = currentSite else { return }
        SiteStore.current = site
        titleButton.setTitle(site.name, for: .normal)
        engine = VodService.shared.engine(for: site)
        loadHome(site: site)
    }

    private func loadHome(site: Site) {
        classes = []
        vods = []
        selectedClass = -1
        categoryView.reloadData()
        gridView.reloadData()

        guard let engine else {
            view.makeToast("该站点无 spider，仅支持 WebHome")
            openWebHome(site: site)
            return
        }
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            let home = engine.home(filter: true)
            DispatchQueue.main.async {
                self.classes = home.types
                self.vods = home.list
                self.categoryView.reloadData()
                self.gridView.reloadData()
                if home.list.isEmpty, !home.types.isEmpty {
                    // Some sites put the initial list under the first category.
                    self.loadCategory(index: 0)
                }
            }
        }
    }

    private func loadCategory(index: Int, reset: Bool = true) {
        guard let engine, index >= 0, index < classes.count else { return }
        selectedClass = index
        page = reset ? 1 : page
        hasMore = true
        if reset { vods = [] }
        gridView.reloadData()
        let cls = classes[index]
        let extenders: [String: String] = [:]
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            let result = engine.category(tid: cls.typeId, pg: "\(self.page)", filter: true, extend: extenders)
            DispatchQueue.main.async {
                if result.msg != "0" {
                    self.vods.append(contentsOf: result.list)
                }
                self.pagecount = result.pagecount
                self.hasMore = self.page < max(1, result.pagecount)
                self.gridView.reloadData()
            }
        }
    }

    private var pagecount = 1

    // MARK: - Navigation

    @objc private func changeSite() {
        let ac = UIAlertController(title: "选择站点", message: nil, preferredStyle: .actionSheet)
        for site in sites {
            ac.addAction(UIAlertAction(title: site.name, style: .default, handler: { [weak self] _ in
                self?.selectSite(site)
            }))
        }
        ac.addAction(UIAlertAction(title: "加载配置", style: .default, handler: { [weak self] _ in
            self?.promptConfig()
        }))
        ac.addAction(UIAlertAction(title: "取消", style: .cancel))
        present(ac, animated: true)
    }

    private func selectSite(_ site: Site) {
        currentSite = site
        SiteStore.current = site
        titleButton.setTitle(site.name, for: .normal)
        engine = VodService.shared.engine(for: site)
        loadHome(site: site)
    }

    private func openWebHome(site: Site) {
        let vc = WebHomeViewController(site: site)
        navigationController?.pushViewController(vc, animated: true)
    }

    func openVod(_ vod: Vod) {
        guard let site = currentSite else { return }
        AppScreens.openVod(from: self, site: site, vod: vod)
    }

    @objc private func openSearch() {
        let ac = UIAlertController(title: "搜索", message: nil, preferredStyle: .alert)
        ac.addTextField { $0.placeholder = "输入关键词" }
        ac.addAction(UIAlertAction(title: "搜索", style: .default, handler: { [weak self, weak ac] _ in
            let key = ac?.textFields?.first?.text ?? ""
            guard !key.isEmpty else { return }
            self?.pushSearch(keyword: key)
        }))
        ac.addAction(UIAlertAction(title: "取消", style: .cancel))
        present(ac, animated: true)
    }

    private func pushSearch(keyword: String) {
        guard let site = currentSite else { return }
        let vc = SearchViewController(site: site, keyword: keyword)
        navigationController?.pushViewController(vc, animated: true)
    }

    @objc private func openConfigs() {
        promptConfig()
    }

    private func promptConfig() {
        let ac = UIAlertController(title: "加载配置", message: "输入 TVBox 配置地址或直接 JSON", preferredStyle: .alert)
        ac.addTextField { $0.placeholder = "https://... 或 JSON"; $0.keyboardType = .URL }
        ac.addAction(UIAlertAction(title: "加载", style: .default, handler: { [weak self, weak ac] _ in
            let url = ac?.textFields?.first?.text ?? ""
            guard !url.isEmpty else { return }
            self?.loadConfig(url: url)
        }))
        ac.addAction(UIAlertAction(title: "取消", style: .cancel))
        present(ac, animated: true)
    }

    func loadConfig(url: String) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            let result = ConfigManager.shared.load(url: url)
            DispatchQueue.main.async {
                if result == nil { self.view.makeToast("配置加载失败"); return }
                self.reloadFromConfig()
            }
        }
    }
}

// MARK: - Data source & delegate

extension VodBrowserViewController: UICollectionViewDataSource, UICollectionViewDelegateFlowLayout {

    func numberOfSections(in collectionView: UICollectionView) -> Int { 1 }

    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        collectionView === categoryView ? classes.count : vods.count
    }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        if collectionView === categoryView {
            let cell = collectionView.dequeueReusableCell(withReuseIdentifier: CategoryChipCell.id, for: indexPath) as! CategoryChipCell
            cell.configure(classes[indexPath.item].typeName, selected: indexPath.item == selectedClass)
            return cell
        }
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: VodCell.id, for: indexPath) as! VodCell
        cell.configure(vods[indexPath.item])
        return cell
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        collectionView.deselectItem(at: indexPath, animated: true)
        if collectionView === categoryView {
            categoryView.scrollToItem(at: indexPath, at: .centeredHorizontally, animated: true)
            loadCategory(index: indexPath.item)
        } else {
            openVod(vods[indexPath.item])
        }
    }

    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
        if collectionView === categoryView {
            let text = classes[indexPath.item].typeName as NSString
            let w = text.size(withAttributes: [.font: UIFont.systemFont(ofSize: 14)]).width + 32
            return CGSize(width: w, height: 32)
        }
        let columns: CGFloat = UIDevice.current.userInterfaceIdiom == .pad ? 6 : 3
        let spacing: CGFloat = 8
        let inset: CGFloat = 16
        let width = (collectionView.bounds.width - inset - spacing * (columns - 1)) / columns
        return CGSize(width: width, height: width / 0.7 + 34)
    }

    func collectionView(_ collectionView: UICollectionView, willDisplay cell: UICollectionViewCell, forItemAt indexPath: IndexPath) {
        if collectionView === gridView, hasMore, indexPath.item >= vods.count - 6 {
            loadCategory(index: selectedClass, reset: false)
        }
    }
}

// MARK: - Cells

final class CategoryChipCell: UICollectionViewCell {
    static let id = "CategoryChipCell"
    private let label = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        contentView.backgroundColor = .secondarySystemBackground
        contentView.layer.cornerRadius = 14
        contentView.layer.masksToBounds = true
        label.textAlignment = .center
        label.font = .systemFont(ofSize: 14)
        label.textColor = .label
        label.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 8),
            label.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -8),
            label.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(_ text: String, selected: Bool) {
        label.text = text
        contentView.backgroundColor = selected ? .systemBlue : .secondarySystemBackground
        label.textColor = selected ? .white : .label
    }
}
