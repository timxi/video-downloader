import UIKit

protocol FloatingPillDelegate: AnyObject {
    func floatingPillDidTap(_ pill: FloatingPillView)
}

class FloatingPillView: UIView {

    // MARK: - Properties

    weak var delegate: FloatingPillDelegate?

    private let containerView = UIView()
    private let iconImageView = UIImageView()
    private let countLabel = UILabel()
    private let badgeView = UIView()

    private var count: Int = 0

    // MARK: - Initialization

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupUI()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupUI()
    }

    // MARK: - Setup

    private func setupUI() {
        // Container
        containerView.backgroundColor = .systemBlue
        containerView.layer.cornerRadius = 28
        containerView.layer.shadowColor = UIColor.black.cgColor
        containerView.layer.shadowOffset = CGSize(width: 0, height: 4)
        containerView.layer.shadowRadius = 8
        containerView.layer.shadowOpacity = 0.3

        addSubview(containerView)
        containerView.translatesAutoresizingMaskIntoConstraints = false

        // Icon
        iconImageView.image = UIImage(systemName: "arrow.down.circle.fill")
        iconImageView.tintColor = .white
        iconImageView.contentMode = .scaleAspectFit

        containerView.addSubview(iconImageView)
        iconImageView.translatesAutoresizingMaskIntoConstraints = false

        // Badge
        badgeView.backgroundColor = .systemRed
        badgeView.layer.cornerRadius = 10

        addSubview(badgeView)
        badgeView.translatesAutoresizingMaskIntoConstraints = false

        // Count label
        countLabel.font = .systemFont(ofSize: 12, weight: .bold)
        countLabel.textColor = .white
        countLabel.textAlignment = .center

        badgeView.addSubview(countLabel)
        countLabel.translatesAutoresizingMaskIntoConstraints = false

        // Constraints
        NSLayoutConstraint.activate([
            containerView.widthAnchor.constraint(equalToConstant: 56),
            containerView.heightAnchor.constraint(equalToConstant: 56),
            containerView.centerXAnchor.constraint(equalTo: centerXAnchor),
            containerView.centerYAnchor.constraint(equalTo: centerYAnchor),

            iconImageView.centerXAnchor.constraint(equalTo: containerView.centerXAnchor),
            iconImageView.centerYAnchor.constraint(equalTo: containerView.centerYAnchor),
            iconImageView.widthAnchor.constraint(equalToConstant: 28),
            iconImageView.heightAnchor.constraint(equalToConstant: 28),

            badgeView.topAnchor.constraint(equalTo: containerView.topAnchor, constant: -4),
            badgeView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: 4),
            badgeView.widthAnchor.constraint(greaterThanOrEqualToConstant: 20),
            badgeView.heightAnchor.constraint(equalToConstant: 20),

            countLabel.centerXAnchor.constraint(equalTo: badgeView.centerXAnchor),
            countLabel.centerYAnchor.constraint(equalTo: badgeView.centerYAnchor),
            countLabel.leadingAnchor.constraint(greaterThanOrEqualTo: badgeView.leadingAnchor, constant: 4),
            countLabel.trailingAnchor.constraint(lessThanOrEqualTo: badgeView.trailingAnchor, constant: -4),

            widthAnchor.constraint(equalToConstant: 64),
            heightAnchor.constraint(equalToConstant: 64)
        ])

        // Tap gesture
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(handleTap))
        containerView.addGestureRecognizer(tapGesture)
        containerView.isUserInteractionEnabled = true

        // Accessibility
        isAccessibilityElement = true
        accessibilityTraits = .button
        accessibilityLabel = "Download options"
        accessibilityHint = "Shows available video qualities"
    }

    // MARK: - Actions

    @objc private func handleTap() {
        // Haptic feedback
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.impactOccurred()

        // Scale animation
        UIView.animate(withDuration: 0.1, animations: {
            self.containerView.transform = CGAffineTransform(scaleX: 0.9, y: 0.9)
        }) { _ in
            UIView.animate(withDuration: 0.1) {
                self.containerView.transform = .identity
            }
        }

        delegate?.floatingPillDidTap(self)
    }

    // MARK: - Public Methods

    func updateCount(_ count: Int) {
        self.count = count
        countLabel.text = count > 99 ? "99+" : "\(count)"
        badgeView.isHidden = count == 0

        // Update accessibility label
        if count == 0 {
            accessibilityLabel = "No videos detected"
        } else if count == 1 {
            accessibilityLabel = "1 video detected"
        } else {
            accessibilityLabel = "\(count) videos detected"
        }

        // Bounce animation on count increase
        bounceAnimation()
    }

    func show() {
        isHidden = false
        containerView.transform = CGAffineTransform(scaleX: 0.1, y: 0.1)
        containerView.alpha = 0

        UIView.animate(withDuration: 0.4, delay: 0, usingSpringWithDamping: 0.6, initialSpringVelocity: 0.5) {
            self.containerView.transform = .identity
            self.containerView.alpha = 1
        }
    }

    func hide() {
        UIView.animate(withDuration: 0.2, animations: {
            self.containerView.transform = CGAffineTransform(scaleX: 0.1, y: 0.1)
            self.containerView.alpha = 0
        }) { _ in
            self.isHidden = true
            self.containerView.transform = .identity
        }
    }

    private func bounceAnimation() {
        UIView.animate(withDuration: 0.15, animations: {
            self.containerView.transform = CGAffineTransform(scaleX: 1.2, y: 1.2)
        }) { _ in
            UIView.animate(withDuration: 0.15) {
                self.containerView.transform = .identity
            }
        }
    }
}
