import Foundation
import WebKit

final class CookieManager {
    static let shared = CookieManager()

    private init() {}

    // MARK: - Cookie Sync

    /// Syncs cookies from WKWebView to URLSession for background downloads
    func syncCookies(from webView: WKWebView, for domain: String, completion: @escaping ([HTTPCookie]) -> Void) {
        webView.configuration.websiteDataStore.httpCookieStore.getAllCookies { cookies in
            print("[CookieManager] Total cookies found: \(cookies.count)")

            // Extract base domain (e.g., "iyf.tv" from "www.iyf.tv")
            let baseDomain = domain.split(separator: ".").suffix(2).joined(separator: ".")

            let domainCookies = cookies.filter { cookie in
                let cookieDomain = cookie.domain.hasPrefix(".") ? String(cookie.domain.dropFirst()) : cookie.domain
                let matches = domain.hasSuffix(cookieDomain) ||
                              cookieDomain.hasSuffix(domain) ||
                              baseDomain == cookieDomain ||
                              cookieDomain.hasSuffix(baseDomain)
                if matches {
                    print("[CookieManager] Matched cookie: \(cookie.name) for domain \(cookie.domain)")
                }
                return matches
            }

            print("[CookieManager] Matched \(domainCookies.count) cookies for domain: \(domain)")

            // Also store in shared HTTPCookieStorage for URLSession
            for cookie in domainCookies {
                HTTPCookieStorage.shared.setCookie(cookie)
            }

            completion(domainCookies)
        }
    }

    /// Gets all cookies for a specific URL
    func getCookies(for url: URL, from webView: WKWebView, completion: @escaping ([HTTPCookie]) -> Void) {
        guard let host = url.host else {
            completion([])
            return
        }

        webView.configuration.websiteDataStore.httpCookieStore.getAllCookies { cookies in
            let relevantCookies = cookies.filter { cookie in
                host.hasSuffix(cookie.domain) || cookie.domain.hasSuffix(host)
            }
            completion(relevantCookies)
        }
    }

    /// Applies cookies to a URLRequest
    func applyCookies(_ cookies: [HTTPCookie], to request: inout URLRequest) {
        let headers = HTTPCookie.requestHeaderFields(with: cookies)
        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }
    }

    // MARK: - Cookie Management

    /// Clear all cookies from WKWebView
    func clearAllCookies(from webView: WKWebView, completion: @escaping () -> Void) {
        let dataStore = webView.configuration.websiteDataStore
        dataStore.fetchDataRecords(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes()) { records in
            let cookieRecords = records.filter { $0.dataTypes.contains(WKWebsiteDataTypeCookies) }
            dataStore.removeData(ofTypes: [WKWebsiteDataTypeCookies], for: cookieRecords) {
                // Also clear from HTTPCookieStorage
                if let cookies = HTTPCookieStorage.shared.cookies {
                    for cookie in cookies {
                        HTTPCookieStorage.shared.deleteCookie(cookie)
                    }
                }
                completion()
            }
        }
    }

    /// Clear all browsing data from WKWebView
    func clearAllBrowsingData(from webView: WKWebView, completion: @escaping () -> Void) {
        let dataStore = webView.configuration.websiteDataStore
        let allTypes = WKWebsiteDataStore.allWebsiteDataTypes()

        dataStore.fetchDataRecords(ofTypes: allTypes) { records in
            dataStore.removeData(ofTypes: allTypes, for: records) {
                completion()
            }
        }
    }

    // MARK: - Cookie Headers

    /// Creates cookie header string from cookies array
    func cookieHeaderString(from cookies: [HTTPCookie]) -> String {
        cookies.map { "\($0.name)=\($0.value)" }.joined(separator: "; ")
    }
}
