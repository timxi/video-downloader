import UIKit

protocol BrowserNavigationBarDelegate: AnyObject {
    func navigationBarDidTapBack(_ navigationBar: BrowserNavigationBar)
    func navigationBarDidTapForward(_ navigationBar: BrowserNavigationBar)
    func navigationBarDidTapRefresh(_ navigationBar: BrowserNavigationBar)
    func navigationBar(_ navigationBar: BrowserNavigationBar, didSubmitURL urlString: String)
}

class BrowserNavigationBar: UIView {

    // MARK: - Properties

    weak var delegate: BrowserNavigationBarDelegate?

    private let backButton = UIButton(type: .system)
    private let forwardButton = UIButton(type: .system)
    private let refreshButton = UIButton(type: .system)
    private let urlTextField = UITextField()
    private let progressView = UIProgressView(progressViewStyle: .bar)

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
        backgroundColor = .systemBackground

        // Back button
        backButton.setImage(UIImage(systemName: "chevron.left"), for: .normal)
        backButton.addTarget(self, action: #selector(backTapped), for: .touchUpInside)
        backButton.isEnabled = false
        backButton.accessibilityLabel = "Go back"
        backButton.accessibilityHint = "Navigate to previous page"

        // Forward button
        forwardButton.setImage(UIImage(systemName: "chevron.right"), for: .normal)
        forwardButton.addTarget(self, action: #selector(forwardTapped), for: .touchUpInside)
        forwardButton.isEnabled = false
        forwardButton.accessibilityLabel = "Go forward"
        forwardButton.accessibilityHint = "Navigate to next page"

        // Refresh button
        refreshButton.setImage(UIImage(systemName: "arrow.clockwise"), for: .normal)
        refreshButton.addTarget(self, action: #selector(refreshTapped), for: .touchUpInside)
        refreshButton.accessibilityLabel = "Refresh"
        refreshButton.accessibilityHint = "Reload current page"

        // URL text field
        urlTextField.placeholder = "Search or enter URL"
        urlTextField.accessibilityLabel = "URL address bar"
        urlTextField.accessibilityHint = "Enter a website address"
        urlTextField.borderStyle = .roundedRect
        urlTextField.autocapitalizationType = .none
        urlTextField.autocorrectionType = .no
        urlTextField.keyboardType = .webSearch
        urlTextField.returnKeyType = .go
        urlTextField.clearButtonMode = .whileEditing
        urlTextField.delegate = self
        urlTextField.font = .systemFont(ofSize: 14)

        // Progress view
        progressView.trackTintColor = .clear
        progressView.progressTintColor = .systemBlue
        progressView.isHidden = true

        // Stack view for buttons
        let buttonStack = UIStackView(arrangedSubviews: [backButton, forwardButton])
        buttonStack.axis = .horizontal
        buttonStack.spacing = 8
        buttonStack.distribution = .fillEqually

        // Main stack
        let mainStack = UIStackView(arrangedSubviews: [buttonStack, urlTextField, refreshButton])
        mainStack.axis = .horizontal
        mainStack.spacing = 8
        mainStack.alignment = .center

        addSubview(mainStack)
        addSubview(progressView)

        mainStack.translatesAutoresizingMaskIntoConstraints = false
        progressView.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            mainStack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            mainStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            mainStack.centerYAnchor.constraint(equalTo: centerYAnchor),

            backButton.widthAnchor.constraint(equalToConstant: 30),
            forwardButton.widthAnchor.constraint(equalToConstant: 30),
            refreshButton.widthAnchor.constraint(equalToConstant: 30),

            progressView.leadingAnchor.constraint(equalTo: leadingAnchor),
            progressView.trailingAnchor.constraint(equalTo: trailingAnchor),
            progressView.bottomAnchor.constraint(equalTo: bottomAnchor),
            progressView.heightAnchor.constraint(equalToConstant: 2)
        ])

        // Bottom border
        let border = UIView()
        border.backgroundColor = .separator
        addSubview(border)
        border.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            border.leadingAnchor.constraint(equalTo: leadingAnchor),
            border.trailingAnchor.constraint(equalTo: trailingAnchor),
            border.bottomAnchor.constraint(equalTo: bottomAnchor),
            border.heightAnchor.constraint(equalToConstant: 0.5)
        ])
    }

    // MARK: - Actions

    @objc private func backTapped() {
        delegate?.navigationBarDidTapBack(self)
    }

    @objc private func forwardTapped() {
        delegate?.navigationBarDidTapForward(self)
    }

    @objc private func refreshTapped() {
        delegate?.navigationBarDidTapRefresh(self)
    }

    // MARK: - Public Methods

    func updateBackButton(enabled: Bool) {
        backButton.isEnabled = enabled
    }

    func updateForwardButton(enabled: Bool) {
        forwardButton.isEnabled = enabled
    }

    func updateURL(_ url: URL?) {
        urlTextField.text = url?.absoluteString
    }

    func updateLoadingState(_ isLoading: Bool) {
        if isLoading {
            refreshButton.setImage(UIImage(systemName: "xmark"), for: .normal)
            progressView.isHidden = false
            progressView.setProgress(0.1, animated: false)
            simulateProgress()
        } else {
            refreshButton.setImage(UIImage(systemName: "arrow.clockwise"), for: .normal)
            progressView.setProgress(1.0, animated: true)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                self?.progressView.isHidden = true
                self?.progressView.setProgress(0, animated: false)
            }
        }
    }

    private func simulateProgress() {
        // Simulate loading progress
        let currentProgress = progressView.progress
        if currentProgress < 0.9 && !progressView.isHidden {
            let increment = Float.random(in: 0.05...0.15)
            progressView.setProgress(min(currentProgress + increment, 0.9), animated: true)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                self?.simulateProgress()
            }
        }
    }
}

// MARK: - UITextFieldDelegate

extension BrowserNavigationBar: UITextFieldDelegate {
    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        if let text = textField.text, !text.isEmpty {
            delegate?.navigationBar(self, didSubmitURL: text)
        }
        textField.resignFirstResponder()
        return true
    }

    func textFieldDidBeginEditing(_ textField: UITextField) {
        textField.selectAll(nil)
    }
}
