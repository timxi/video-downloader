import Foundation
import WebKit

final class ContentRuleListManager {
    static let shared = ContentRuleListManager()

    private var compiledRuleList: WKContentRuleList?
    private var isCompiling = false

    private init() {}

    // MARK: - Public Methods

    /// Apply content blocking rules to the configuration
    /// Note: Full CSP header modification requires iOS 15+ and may not work in all cases
    /// For now, we skip the complex header modification and rely on our injected scripts
    func applyRules(to configuration: WKWebViewConfiguration, completion: (() -> Void)? = nil) {
        // For initial version, we'll skip complex CSP bypass
        // The JavaScript injection should still work for most sites
        // CSP bypass can be enhanced in future versions
        completion?()
    }

    func removeRules(from configuration: WKWebViewConfiguration) {
        configuration.userContentController.removeAllContentRuleLists()
    }

    // MARK: - Cache Management

    func clearCompiledRules() {
        compiledRuleList = nil
    }
}
