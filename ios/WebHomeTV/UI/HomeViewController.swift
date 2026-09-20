import UIKit

final class HomeViewController: UIViewController {

    private let label = UILabel()
    private let stack = UIStackView()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        configureStack()
    }

    private func configureStack() {
        label.text = "WebHomeTV · iOS 深度移植"
        label.textColor = .white
        label.font = .systemFont(ofSize: 22, weight: .bold)
        label.textAlignment = .center

        let subtitle = UILabel()
        subtitle.numberOfLines = 0
        subtitle.textAlignment = .center
        subtitle.textColor = .secondaryLabel
        subtitle.font = .systemFont(ofSize: 15)
        subtitle.text = "阶段一骨架已就绪\nWebHomeTV iOS IPA 由 GitHub Actions 自动构建（未签名）"

        stack.axis = .vertical
        stack.spacing = 12
        stack.alignment = .fill
        stack.addArrangedSubview(label)
        stack.addArrangedSubview(subtitle)
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            stack.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -24),
        ])
    }
}
