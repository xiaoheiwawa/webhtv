import UIKit

/// Grid cell showing a video poster with name + remarks, mirroring Android `adapter_vod`.
final class VodCell: UICollectionViewCell {
    static let id = "VodCell"

    private let imageView = UIImageView()
    private let titleLabel = UILabel()
    private let remarkLabel = UILabel()
    private let placeholder = UIColor.secondarySystemBackground

    override init(frame: CGRect) {
        super.init(frame: frame)
        imageView.contentMode = .scaleAspectFill
        imageView.backgroundColor = placeholder
        imageView.layer.cornerRadius = 8
        imageView.clipsToBounds = true
        imageView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(imageView)

        titleLabel.font = .systemFont(ofSize: 13)
        titleLabel.textColor = .label
        titleLabel.numberOfLines = 1
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(titleLabel)

        remarkLabel.font = .systemFont(ofSize: 11)
        remarkLabel.textColor = .secondaryLabel
        remarkLabel.numberOfLines = 1
        remarkLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(remarkLabel)

        NSLayoutConstraint.activate([
            imageView.topAnchor.constraint(equalTo: contentView.topAnchor),
            imageView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            imageView.heightAnchor.constraint(equalTo: imageView.widthAnchor, multiplier: 1.4),

            titleLabel.topAnchor.constraint(equalTo: imageView.bottomAnchor, constant: 4),
            titleLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 2),
            titleLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -2),

            remarkLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 1),
            remarkLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 2),
            remarkLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -2),
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(_ vod: Vod) {
        titleLabel.text = vod.vodName
        remarkLabel.text = vod.vodRemarks
        remarkLabel.isHidden = vod.vodRemarks.isEmpty
        imageView.image = nil
        guard let url = URL(string: vod.vodPic), !vod.vodPic.isEmpty else {
            imageView.image = nil
            return
        }
        ImageLoader.shared.load(url: url) { [weak self] image in
            self?.imageView.image = image
        }
    }
}

/// Simple shared async image cache.
enum ImageLoader {
    private static let cache = NSCache<NSString, UIImage>()
    private static let session: URLSession = {
        let c = URLSessionConfiguration.ephemeral
        c.timeoutIntervalForRequest = 15
        return URLSession(configuration: c)
    }()

    static func load(url: URL, completion: @escaping (UIImage?) -> Void) {
        let key = url.absoluteString as NSString
        if let img = cache.object(forKey: key) {
            completion(img)
            return
        }
        session.dataTask(with: url) { data, _, _ in
            guard let data, let img = UIImage(data: data) else {
                DispatchQueue.main.async { completion(nil) }
                return
            }
            cache.setObject(img, forKey: key)
            DispatchQueue.main.async { completion(img) }
        }.resume()
    }
}

/// Infinite-scroll footer ("加载中…").
final class LoadingFooter: UICollectionReusableView {
    static let id = "LoadingFooter"
    private let indicator = UIActivityIndicatorView(style: .medium)

    override init(frame: CGRect) {
        super.init(frame: frame)
        indicator.startAnimating()
        indicator.translatesAutoresizingMaskIntoConstraints = false
        addSubview(indicator)
        NSLayoutConstraint.activate([
            indicator.centerXAnchor.constraint(equalTo: centerXAnchor),
            indicator.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}
