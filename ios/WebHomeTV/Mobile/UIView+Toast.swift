import UIKit

extension UIView {
    /// Minimal toast overlay, shown centered with an auto-dismiss.
    func makeToast(_ text: String) {
        DispatchQueue.main.async {
            let label = UILabel()
            label.text = text
            label.textColor = .white
            label.backgroundColor = UIColor.black.withAlphaComponent(0.75)
            label.textAlignment = .center
            label.numberOfLines = 0
            label.font = .systemFont(ofSize: 14)
            label.layer.cornerRadius = 8
            label.clipsToBounds = true
            label.alpha = 0
            label.translatesAutoresizingMaskIntoConstraints = false
            let container = UIButton(type: .custom)
            container.backgroundColor = .clear
            container.frame = self.bounds
            container.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            container.addSubview(label)
            label.centerXAnchor.constraint(equalTo: container.centerXAnchor).isActive = true
            label.centerYAnchor.constraint(equalTo: container.centerYAnchor).isActive = true
            label.widthAnchor.constraint(lessThanOrEqualToConstant: self.bounds.width - 60).isActive = true
            let padding: CGFloat = 16
            label.layoutMargins = UIEdgeInsets(top: padding, left: padding, bottom: padding, right: padding)
            self.addSubview(container)
            UIView.animate(withDuration: 0.2, animations: { label.alpha = 1 }) { _ in
                UIView.animate(withDuration: 0.3, delay: 1.5, options: [], animations: { label.alpha = 0 }) { _ in
                    container.removeFromSuperview()
                }
            }
        }
    }
}
