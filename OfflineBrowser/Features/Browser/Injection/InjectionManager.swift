import Foundation
import WebKit

protocol StreamDetectionDelegate: AnyObject {
    func didDetectStream(url: String, type: StreamType)
}

final class InjectionManager: NSObject {

    weak var delegate: StreamDetectionDelegate?
    private let messageHandlerName = "streamDetector"

    // MARK: - Configuration

    func configure(contentController: WKUserContentController, delegate: StreamDetectionDelegate) {
        self.delegate = delegate

        // Add message handler
        contentController.add(self, name: messageHandlerName)

        // Inject the network interceptor script
        if let script = loadInterceptorScript() {
            let userScript = WKUserScript(
                source: script,
                injectionTime: .atDocumentStart,
                forMainFrameOnly: false
            )
            contentController.addUserScript(userScript)
        }
    }

    // MARK: - Script Loading

    private func loadInterceptorScript() -> String? {
        // Try to load from bundle first
        if let path = Bundle.main.path(forResource: "NetworkInterceptor", ofType: "js"),
           let script = try? String(contentsOfFile: path) {
            print("[InjectionManager] Loaded NetworkInterceptor.js from bundle (\(script.count) chars)")
            return script
        }

        // Fallback to embedded script
        print("[InjectionManager] Using fallback embedded script")
        return embeddedInterceptorScript
    }

    private var embeddedInterceptorScript: String {
        """
        (function() {
            'use strict';

            // Track detected URLs to avoid duplicates
            const detectedURLs = new Set();

            function checkForStream(url) {
                if (!url || typeof url !== 'string') return;

                // Skip data URLs and blob URLs
                if (url.startsWith('data:') || url.startsWith('blob:')) return;

                // Skip if already detected
                if (detectedURLs.has(url)) return;

                let type = null;

                // Check for HLS
                if (url.includes('.m3u8') || url.includes('/manifest/') && url.includes('hls')) {
                    type = 'hls';
                }
                // Check for DASH
                else if (url.includes('.mpd')) {
                    type = 'dash';
                }
                // Check for direct video files
                else if (url.match(/\\.(mp4|webm|m4v)(\\?|$)/i)) {
                    type = 'direct';
                }

                if (type) {
                    detectedURLs.add(url);
                    try {
                        window.webkit.messageHandlers.streamDetector.postMessage({
                            type: 'streamDetected',
                            url: url,
                            streamType: type,
                            timestamp: Date.now()
                        });
                    } catch (e) {
                        // Message handler not available
                    }
                }
            }

            // Intercept XMLHttpRequest
            const originalXHROpen = XMLHttpRequest.prototype.open;
            XMLHttpRequest.prototype.open = function(method, url) {
                checkForStream(url);
                return originalXHROpen.apply(this, arguments);
            };

            // Intercept fetch
            const originalFetch = window.fetch;
            window.fetch = function(input, init) {
                const url = typeof input === 'string' ? input : input.url;
                checkForStream(url);
                return originalFetch.apply(this, arguments);
            };

            // Intercept video/source elements
            const observer = new MutationObserver(function(mutations) {
                mutations.forEach(function(mutation) {
                    mutation.addedNodes.forEach(function(node) {
                        if (node.nodeType === 1) {
                            // Check video elements
                            if (node.tagName === 'VIDEO') {
                                checkForStream(node.src);
                                node.querySelectorAll('source').forEach(function(source) {
                                    checkForStream(source.src);
                                });
                            }
                            // Check source elements
                            else if (node.tagName === 'SOURCE') {
                                checkForStream(node.src);
                            }
                            // Check nested videos
                            node.querySelectorAll && node.querySelectorAll('video, source').forEach(function(el) {
                                checkForStream(el.src);
                            });
                        }
                    });
                });
            });

            observer.observe(document.documentElement, {
                childList: true,
                subtree: true
            });

            // Check existing video elements
            document.querySelectorAll('video').forEach(function(video) {
                checkForStream(video.src);
                video.querySelectorAll('source').forEach(function(source) {
                    checkForStream(source.src);
                });
            });

            // Intercept src attribute changes
            const originalSetAttribute = Element.prototype.setAttribute;
            Element.prototype.setAttribute = function(name, value) {
                if (name === 'src' && (this.tagName === 'VIDEO' || this.tagName === 'SOURCE')) {
                    checkForStream(value);
                }
                return originalSetAttribute.apply(this, arguments);
            };

            console.log('[OfflineBrowser] Stream interceptor initialized');
        })();
        """
    }
}

// MARK: - WKScriptMessageHandler

extension InjectionManager: WKScriptMessageHandler {
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.name == messageHandlerName,
              let body = message.body as? [String: Any],
              let messageType = body["type"] as? String,
              messageType == "streamDetected",
              let url = body["url"] as? String,
              let streamTypeString = body["streamType"] as? String else {
            return
        }

        let streamType: StreamType
        switch streamTypeString {
        case "hls":
            streamType = .hls
        case "dash":
            streamType = .dash
        case "direct":
            streamType = .direct
        default:
            streamType = .unknown
        }

        print("[InjectionManager] Stream detected: \(streamType) - \(url)")
        DispatchQueue.main.async { [weak self] in
            self?.delegate?.didDetectStream(url: url, type: streamType)
        }
    }
}
