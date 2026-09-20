import UIKit

/// Native search over a single site, mirroring Android `SearchFragment`.
final class SearchViewController: UIViewController, UISearchBarDelegate {

    private let site: Site
    private var results: [Vod] = []
    private var engine: SiteEngine?

    private let searchBar = UISearchBar()
    private let gridView = UICollectionView(frame: .zero, collectionViewLayout: UICollectionViewFlowLayout())

    init(site: Site, keyword: String) {
        self.site = site
        super.init(nibName: nil, bundle: nil)
        title = "搜索"
        searchBar.text = keyword
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        engine = VodService.shared.engine(for: site)
        configureGrid()
        if let kw = searchBar.text, !kw.isEmpty { performSearch(kw) }
    }

    private func configureGrid() {
        searchBar.delegate = self
        searchBar.placeholder = "输入关键词搜索"
        searchBar.showsCancelButton = true
        searchBar.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(searchBar)

        let layout = UICollectionViewFlowLayout()
        layout.minimumInteritemSpacing = 8
        layout.minimumLineSpacing = 12
        layout.sectionInset = UIEdgeInsets(top: 8, left: 8, bottom: 8, right: 8)
        gridView.collectionViewLayout = layout
        gridView.backgroundColor = .clear
        gridView.delegate = self
        gridView.dataSource = self
        gridView.register(VodCell.self, forCellWithReuseIdentifier: VodCell.id)
        gridView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(gridView)

        NSLayoutConstraint.activate([
            searchBar.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            searchBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            searchBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            gridView.topAnchor.constraint(equalTo: searchBar.bottomAnchor),
            gridView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            gridView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            gridView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }

    private func performSearch(_ key: String) {
        guard let engine else { return }
        results = []
        gridView.reloadData()
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let r = engine.search(key: key, quick: false, pg: "1")
            DispatchQueue.main.async {
                self?.results = r.list
                self?.gridView.reloadData()
            }
        }
    }

    func searchBarSearchButtonClicked(_ searchBar: UISearchBar) {
        searchBar.resignFirstResponder()
        if let kw = searchBar.text, !kw.isEmpty { performSearch(kw) }
    }
    func openVod(_ vod: Vod) {
        AppScreens.openVod(from: self, site: site, vod: vod)
    }

    func searchBarCancelButtonClicked(_ searchBar: UISearchBar) {
        searchBar.resignFirstResponder()
        navigationController?.popViewController(animated: true)
    }
}

extension SearchViewController: UICollectionViewDataSource, UICollectionViewDelegateFlowLayout {
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int { results.count }
    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: VodCell.id, for: indexPath) as! VodCell
        cell.configure(results[indexPath.item])
        return cell
    }
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        collectionView.deselectItem(at: indexPath, animated: true)
        openVod(results[indexPath.item])
    }
    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
        let columns: CGFloat = UIDevice.current.userInterfaceIdiom == .pad ? 6 : 3
        let width = (collectionView.bounds.width - 16 - 8 * (columns - 1)) / columns
        return CGSize(width: width, height: width / 0.7 + 34)
    }
}
