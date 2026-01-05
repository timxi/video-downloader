import UIKit

final class HintManager {
    static let shared = HintManager()

    private var currentHintView: UIView?

    private init() {}

    // MARK: - Public Methods

    func showHint(message: String, from anchorView: UIView, in containerView: UIView) {
        // Dismiss any existing hint
        dismissCurrentHint()

        let hintView = createHintView(message: message)
        containerView.addSubview(hintView)

        // Position above the anchor view
        hintView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            hintView.centerXAnchor.constraint(equalTo: anchorView.centerXAnchor),
            hintView.bottomAnchor.constraint(equalTo: anchorView.topAnchor, constant: -12)
        ])

        currentHintView = hintView

        // Animate in
        hintView.alpha = 0
        hintView.transform = CGAffineTransform(translationX: 0, y: 10)

        UIView.animate(withDuration: 0.3) {
            hintView.alpha = 1
            hintView.transform = .identity
        }

        // Auto-dismiss after 4 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) { [weak self] in
            self?.dismissCurrentHint()
        }
    }

    func dismissCurrentHint() {
        guard let hintView = currentHintView else { return }

        UIView.animate(withDuration: 0.2, animations: {
            hintView.alpha = 0
        }) { _ in
            hintView.removeFromSuperview()
        }

        currentHintView = nil
    }

    // MARK: - Private Methods

    private func createHintView(message: String) -> UIView {
        let container = UIView()
        container.backgroundColor = UIColor.systemBlue
        container.layer.cornerRadius = 8
        container.layer.shadowColor = UIColor.black.cgColor
        container.layer.shadowOffset = CGSize(width: 0, height: 2)
        container.layer.shadowRadius = 4
        container.layer.shadowOpacity = 0.2

        let label = UILabel()
        label.text = message
        label.textColor = .white
        label.font = .systemFont(ofSize: 14, weight: .medium)
        label.numberOfLines = 0

        container.addSubview(label)
        label.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            label.topAnchor.constraint(equalTo: container.topAnchor, constant: 8),
            label.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -8),
            label.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 12),
            label.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -12)
        ])

        // Add arrow pointing down
        let arrow = UIView()
        arrow.backgroundColor = UIColor.systemBlue
        arrow.transform = CGAffineTransform(rotationAngle: .pi / 4)

        container.addSubview(arrow)
        arrow.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            arrow.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            arrow.topAnchor.constraint(equalTo: container.bottomAnchor, constant: -6),
            arrow.widthAnchor.constraint(equalToConstant: 12),
            arrow.heightAnchor.constraint(equalToConstant: 12)
        ])

        // Tap to dismiss
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(hintTapped))
        container.addGestureRecognizer(tapGesture)

        return container
    }

    @objc private func hintTapped() {
        dismissCurrentHint()
    }
}
