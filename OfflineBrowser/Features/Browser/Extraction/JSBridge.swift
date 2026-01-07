import Foundation
import WebKit
import os.log

/// Result of a YouTube extraction
struct YouTubeExtractionResult {
    let hlsURL: String
    let title: String?
    let duration: TimeInterval?
    let thumbnailURL: String?
}

/// Errors that can occur during YouTube extraction
enum YouTubeExtractionError: LocalizedError {
    case invalidVideoId
    case extractionFailed(String)
    case timeout
    case webViewNotReady

    var errorDescription: String? {
        switch self {
        case .invalidVideoId:
            return "Invalid YouTube video ID"
        case .extractionFailed(let message):
            return "Extraction failed: \(message)"
        case .timeout:
            return "Extraction timed out"
        case .webViewNotReady:
            return "WebView not initialized"
        }
    }
}

/// Delegate protocol for JSBridge extraction results
protocol JSBridgeDelegate: AnyObject {
    func jsBridge(_ bridge: JSBridge, didExtractResult result: YouTubeExtractionResult)
    func jsBridge(_ bridge: JSBridge, didFailWithError error: YouTubeExtractionError)
}

/// Bridge for running JavaScript extraction code in a hidden WKWebView
final class JSBridge: NSObject {

    // MARK: - Properties

    weak var delegate: JSBridgeDelegate?

    private var webView: WKWebView?
    private var isReady = false
    private var pendingExtraction: ((Result<YouTubeExtractionResult, YouTubeExtractionError>) -> Void)?
    private var extractionTimer: Timer?

    private let logger = Logger(subsystem: "com.offlinebrowser.app", category: "JSBridge")

    // Timeout for extraction (15 seconds)
    private let extractionTimeout: TimeInterval = 15

    // MARK: - Initialization

    override init() {
        super.init()
    }

    // MARK: - Setup

    /// Initialize the hidden WebView and load the extraction script
    func setup() {
        let config = WKWebViewConfiguration()
        let contentController = WKUserContentController()

        // Register message handlers
        contentController.add(self, name: "streamExtracted")
        contentController.add(self, name: "extractionError")
        contentController.add(self, name: "extractionReady")

        config.userContentController = contentController

        // Create hidden WebView
        webView = WKWebView(frame: .zero, configuration: config)
        webView?.navigationDelegate = self

        // Load a blank HTML page first (required for fetch() to work)
        let blankHTML = """
        <!DOCTYPE html>
        <html>
        <head><title>YouTube Extractor</title></head>
        <body></body>
        </html>
        """
        webView?.loadHTMLString(blankHTML, baseURL: URL(string: "https://www.youtube.com"))
    }

    /// Clean up resources
    func teardown() {
        extractionTimer?.invalidate()
        extractionTimer = nil

        webView?.configuration.userContentController.removeScriptMessageHandler(forName: "streamExtracted")
        webView?.configuration.userContentController.removeScriptMessageHandler(forName: "extractionError")
        webView?.configuration.userContentController.removeScriptMessageHandler(forName: "extractionReady")

        webView = nil
        isReady = false
    }

    // MARK: - Extraction

    /// Extract YouTube video info using the video ID
    func extractYouTube(videoId: String, cookies: [HTTPCookie] = [], completion: @escaping (Result<YouTubeExtractionResult, YouTubeExtractionError>) -> Void) {
        guard let webView = webView, isReady else {
            logger.error("JSBridge not ready for extraction")
            completion(.failure(.webViewNotReady))
            return
        }

        // Store completion handler
        pendingExtraction = completion

        // Start timeout timer
        extractionTimer?.invalidate()
        extractionTimer = Timer.scheduledTimer(withTimeInterval: extractionTimeout, repeats: false) { [weak self] _ in
            self?.handleTimeout()
        }

        // Convert cookies to JSON
        let cookieArray = cookies.map { cookie -> [String: String] in
            return [
                "name": cookie.name,
                "value": cookie.value,
                "domain": cookie.domain,
                "path": cookie.path
            ]
        }

        let cookieJSON: String
        if let data = try? JSONSerialization.data(withJSONObject: cookieArray),
           let jsonString = String(data: data, encoding: .utf8) {
            cookieJSON = jsonString
        } else {
            cookieJSON = "[]"
        }

        // Call the extraction function
        let script = "extractYouTube('\(videoId)', \(cookieJSON))"
        logger.info("Starting YouTube extraction for video: \(videoId)")

        webView.evaluateJavaScript(script) { [weak self] _, error in
            if let error = error {
                self?.logger.error("JavaScript evaluation error: \(error.localizedDescription)")
                // Don't fail yet - wait for message handler response
            }
        }
    }

    // MARK: - Private Methods

    private func loadExtractionScript() {
        // Load bundled JavaScript file
        guard let jsURL = Bundle.main.url(forResource: "youtube-extract", withExtension: "js"),
              let jsCode = try? String(contentsOf: jsURL, encoding: .utf8) else {
            logger.error("Failed to load youtube-extract.js from bundle")
            // Load minimal fallback that signals ready
            let fallback = """
            window.extractYouTube = function(videoId, cookies) {
                window.webkit.messageHandlers.extractionError.postMessage({
                    message: 'Extraction script not loaded'
                });
            };
            window.webkit.messageHandlers.extractionReady.postMessage({});
            """
            webView?.evaluateJavaScript(fallback, completionHandler: nil)
            return
        }

        // Evaluate the script
        webView?.evaluateJavaScript(jsCode) { [weak self] _, error in
            if let error = error {
                self?.logger.error("Failed to load extraction script: \(error.localizedDescription)")
            } else {
                self?.logger.info("Extraction script loaded successfully")
            }
        }

        // Signal ready after script loads
        let readyScript = "window.webkit.messageHandlers.extractionReady.postMessage({});"
        webView?.evaluateJavaScript(readyScript, completionHandler: nil)
    }

    private func handleTimeout() {
        logger.warning("YouTube extraction timed out")
        extractionTimer?.invalidate()
        extractionTimer = nil

        let completion = pendingExtraction
        pendingExtraction = nil
        completion?(.failure(.timeout))
        delegate?.jsBridge(self, didFailWithError: .timeout)
    }

    private func handleExtractionSuccess(_ data: [String: Any]) {
        extractionTimer?.invalidate()
        extractionTimer = nil

        guard let hlsURL = data["url"] as? String else {
            logger.error("Missing HLS URL in extraction result")
            handleExtractionError("Missing HLS URL")
            return
        }

        let result = YouTubeExtractionResult(
            hlsURL: hlsURL,
            title: data["title"] as? String,
            duration: data["duration"] as? TimeInterval,
            thumbnailURL: data["thumbnail"] as? String
        )

        logger.info("YouTube extraction successful: \(hlsURL)")

        let completion = pendingExtraction
        pendingExtraction = nil
        completion?(.success(result))
        delegate?.jsBridge(self, didExtractResult: result)
    }

    private func handleExtractionError(_ message: String) {
        extractionTimer?.invalidate()
        extractionTimer = nil

        logger.error("YouTube extraction error: \(message)")

        let error = YouTubeExtractionError.extractionFailed(message)
        let completion = pendingExtraction
        pendingExtraction = nil
        completion?(.failure(error))
        delegate?.jsBridge(self, didFailWithError: error)
    }
}

// MARK: - WKScriptMessageHandler

extension JSBridge: WKScriptMessageHandler {
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        switch message.name {
        case "streamExtracted":
            if let data = message.body as? [String: Any] {
                handleExtractionSuccess(data)
            } else {
                handleExtractionError("Invalid extraction result format")
            }

        case "extractionError":
            if let data = message.body as? [String: Any],
               let errorMessage = data["message"] as? String {
                handleExtractionError(errorMessage)
            } else {
                handleExtractionError("Unknown error")
            }

        case "extractionReady":
            isReady = true
            logger.info("JSBridge ready for extraction")

        default:
            logger.warning("Unknown message received: \(message.name)")
        }
    }
}

// MARK: - WKNavigationDelegate

extension JSBridge: WKNavigationDelegate {
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        // Load the extraction script after the blank page loads
        loadExtractionScript()
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        logger.error("WebView navigation failed: \(error.localizedDescription)")
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        logger.error("WebView provisional navigation failed: \(error.localizedDescription)")
    }
}
