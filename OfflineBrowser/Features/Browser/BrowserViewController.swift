import UIKit
import WebKit
import Combine

class BrowserViewController: UIViewController {

    // MARK: - Properties

    private var webView: WKWebView!
    private var navigationBar: BrowserNavigationBar!
    private var floatingPill: FloatingPillView!

    private let streamDetector = StreamDetector.shared
    private let injectionManager = InjectionManager()
    private var cancellables = Set<AnyCancellable>()

    private var currentPageTitle: String?
    private var currentPageURL: URL?
    private var currentPageImageURL: String?

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        setupWebView()
        setupNavigationBar()
        setupFloatingPill()
        setupBindings()
        loadHomePage()
    }

    // MARK: - Setup

    private func setupWebView() {
        let configuration = WKWebViewConfiguration()

        // Allow inline media playback
        configuration.allowsInlineMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = []

        // Use non-persistent data store for privacy, or persistent for login persistence
        configuration.websiteDataStore = .default()

        // Setup content controller for JavaScript injection
        let contentController = WKUserContentController()
        injectionManager.configure(contentController: contentController, delegate: self)
        configuration.userContentController = contentController

        // Apply CSP bypass rules (simplified for now)
        ContentRuleListManager.shared.applyRules(to: configuration, completion: nil)

        webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.allowsBackForwardNavigationGestures = true
        webView.scrollView.contentInsetAdjustmentBehavior = .automatic

        view.addSubview(webView)
        webView.translatesAutoresizingMaskIntoConstraints = false
    }

    private func setupNavigationBar() {
        navigationBar = BrowserNavigationBar()
        navigationBar.delegate = self
        view.addSubview(navigationBar)
        navigationBar.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            navigationBar.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            navigationBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            navigationBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            navigationBar.heightAnchor.constraint(equalToConstant: 50),

            webView.topAnchor.constraint(equalTo: navigationBar.bottomAnchor),
            webView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            webView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor)
        ])
    }

    private func setupFloatingPill() {
        floatingPill = FloatingPillView()
        floatingPill.delegate = self
        floatingPill.isHidden = true
        view.addSubview(floatingPill)
        floatingPill.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            floatingPill.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            floatingPill.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -16)
        ])
    }

    private func setupBindings() {
        // Observe detected streams
        streamDetector.$detectedStreams
            .receive(on: DispatchQueue.main)
            .sink { [weak self] streams in
                // Apply same filtering as DownloadOptionsSheet: prefer HLS over direct
                let hlsStreams = streams.filter { $0.type == .hls }
                let filteredCount = hlsStreams.isEmpty ? min(streams.count, 5) : hlsStreams.count
                self?.updateFloatingPill(streamCount: filteredCount)
            }
            .store(in: &cancellables)

        // Observe web view navigation state
        webView.publisher(for: \.canGoBack)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] canGoBack in
                self?.navigationBar.updateBackButton(enabled: canGoBack)
            }
            .store(in: &cancellables)

        webView.publisher(for: \.canGoForward)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] canGoForward in
                self?.navigationBar.updateForwardButton(enabled: canGoForward)
            }
            .store(in: &cancellables)

        webView.publisher(for: \.url)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] url in
                self?.navigationBar.updateURL(url)
                self?.currentPageURL = url
            }
            .store(in: &cancellables)

        webView.publisher(for: \.isLoading)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isLoading in
                self?.navigationBar.updateLoadingState(isLoading)
            }
            .store(in: &cancellables)

        webView.publisher(for: \.title)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] title in
                self?.currentPageTitle = title
            }
            .store(in: &cancellables)
    }

    // MARK: - Navigation

    private func loadHomePage() {
        // Load a default search engine or blank page
        if let url = URL(string: "https://www.google.com") {
            webView.load(URLRequest(url: url))
        }
    }

    private func navigate(to urlString: String) {
        var urlString = urlString.trimmingCharacters(in: .whitespacesAndNewlines)

        // Add https:// if no scheme provided
        if !urlString.contains("://") {
            // Check if it looks like a URL or a search query
            if urlString.contains(".") && !urlString.contains(" ") {
                urlString = "https://" + urlString
            } else {
                // Treat as search query
                urlString = "https://www.google.com/search?q=" + (urlString.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? urlString)
            }
        }

        guard let url = URL(string: urlString) else { return }

        // Clear detected streams for new page
        streamDetector.clearStreams()

        webView.load(URLRequest(url: url))
    }

    // MARK: - Floating Pill

    private func updateFloatingPill(streamCount: Int) {
        if streamCount > 0 {
            floatingPill.updateCount(streamCount)
            if floatingPill.isHidden {
                floatingPill.show()
                showDownloadPillHintIfNeeded()
            }
        } else {
            floatingPill.hide()
        }
    }

    private func showDownloadPillHintIfNeeded() {
        guard !PreferenceRepository.shared.hasSeenDownloadPillHint else { return }
        PreferenceRepository.shared.hasSeenDownloadPillHint = true
        // Show hint tooltip
        HintManager.shared.showHint(
            message: "Tap to download detected videos",
            from: floatingPill,
            in: view
        )
    }

    // MARK: - Download Sheet

    private func showDownloadOptions() {
        let streams = streamDetector.detectedStreams

        let sheet = DownloadOptionsSheet(streams: streams, pageTitle: currentPageTitle, pageURL: currentPageURL)
        sheet.delegate = self

        if let presentationController = sheet.presentationController as? UISheetPresentationController {
            presentationController.detents = [.medium(), .large()]
            presentationController.prefersGrabberVisible = true
        }

        present(sheet, animated: true)
    }
}

// MARK: - BrowserNavigationBarDelegate

extension BrowserViewController: BrowserNavigationBarDelegate {
    func navigationBarDidTapBack(_ navigationBar: BrowserNavigationBar) {
        webView.goBack()
    }

    func navigationBarDidTapForward(_ navigationBar: BrowserNavigationBar) {
        webView.goForward()
    }

    func navigationBarDidTapRefresh(_ navigationBar: BrowserNavigationBar) {
        // Clear detected streams before reloading
        streamDetector.clearStreams()
        // Also clear the JavaScript-side tracking
        webView.evaluateJavaScript("if(window.__offlineBrowserClearDetected) window.__offlineBrowserClearDetected();", completionHandler: nil)
        webView.reload()
    }

    func navigationBar(_ navigationBar: BrowserNavigationBar, didSubmitURL urlString: String) {
        navigate(to: urlString)
    }
}

// MARK: - FloatingPillDelegate

extension BrowserViewController: FloatingPillDelegate {
    func floatingPillDidTap(_ pill: FloatingPillView) {
        showDownloadOptions()
    }
}

// MARK: - DownloadOptionsSheetDelegate

extension BrowserViewController: DownloadOptionsSheetDelegate {
    func downloadOptionsSheet(_ sheet: DownloadOptionsSheet, didSelectStream stream: DetectedStream) {
        // Start download
        DownloadManager.shared.startDownload(
            stream: stream,
            pageTitle: currentPageTitle,
            pageURL: currentPageURL,
            thumbnailURL: currentPageImageURL,
            webView: webView
        )
        dismiss(animated: true)
    }
}

// MARK: - StreamDetectionDelegate

extension BrowserViewController: StreamDetectionDelegate {
    func didDetectStream(url: String, type: StreamType) {
        streamDetector.addStream(url: url, type: type)
    }
}

// MARK: - WKNavigationDelegate

extension BrowserViewController: WKNavigationDelegate {
    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        streamDetector.clearStreams()
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        // Extract metadata
        extractPageMetadata()
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        decisionHandler(.allow)
    }

    private func extractPageMetadata() {
        // Extract OG tags and other metadata
        let script = """
            (function() {
                var title = document.querySelector('meta[property="og:title"]')?.content || document.title;
                var image = document.querySelector('meta[property="og:image"]')?.content;
                return { title: title, image: image };
            })();
        """

        webView.evaluateJavaScript(script) { [weak self] result, error in
            if let dict = result as? [String: Any] {
                if let title = dict["title"] as? String {
                    self?.currentPageTitle = title
                }
                if let image = dict["image"] as? String {
                    self?.currentPageImageURL = image
                }
            }
        }
    }
}

// MARK: - WKUIDelegate

extension BrowserViewController: WKUIDelegate {
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        // Handle target="_blank" links by loading in the same webview
        if navigationAction.targetFrame == nil {
            webView.load(navigationAction.request)
        }
        return nil
    }
}
