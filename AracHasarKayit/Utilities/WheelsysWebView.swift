import SwiftUI
import WebKit

/// SwiftUI wrapper for WKWebView with session management
struct WheelsysWebView: UIViewRepresentable {
    let url: URL
    @Binding var isLoading: Bool
    @Binding var canGoBack: Bool
    @Binding var canGoForward: Bool
    
    // Session manager for cookie persistence
    let sessionManager: WheelsysSessionManager
    
    func makeUIView(context: Context) -> WKWebView {
        // Configure web view with persistent data store
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = WKWebsiteDataStore.default()
        
        // Enable data persistence
        let dataStore = configuration.websiteDataStore
        if !dataStore.isPersistent {
            configuration.websiteDataStore = WKWebsiteDataStore.default()
        }
        
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true
        webView.allowsLinkPreview = false
        
        // Store web view reference in coordinator
        context.coordinator.webView = webView
        context.coordinator.targetURL = url
        
        // Restore cookies before loading
        sessionManager.restoreCookies()
        
        // Load URL immediately
        let request = URLRequest(url: url)
        webView.load(request)
        
        return webView
    }
    
    func updateUIView(_ webView: WKWebView, context: Context) {
        // Update coordinator reference
        context.coordinator.webView = webView
        
        // Update navigation state
        canGoBack = webView.canGoBack
        canGoForward = webView.canGoForward
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self, sessionManager: sessionManager)
    }
    
    // MARK: - Coordinator
    class Coordinator: NSObject, WKNavigationDelegate {
        var parent: WheelsysWebView
        let sessionManager: WheelsysSessionManager
        weak var webView: WKWebView?
        var targetURL: URL?
        var loadingTimer: Timer?
        
        init(_ parent: WheelsysWebView, sessionManager: WheelsysSessionManager) {
            self.parent = parent
            self.sessionManager = sessionManager
        }
        
        deinit {
            loadingTimer?.invalidate()
        }
        
        func goBack() {
            guard let webView = webView, webView.canGoBack else { return }
            webView.goBack()
        }
        
        func goForward() {
            guard let webView = webView, webView.canGoForward else { return }
            webView.goForward()
        }
        
        func reload() {
            webView?.reload()
        }
        
        private func startLoadingTimeout() {
            loadingTimer?.invalidate()
            loadingTimer = Timer.scheduledTimer(withTimeInterval: 30.0, repeats: false) { [weak self] _ in
                DispatchQueue.main.async {
                    if let self = self, self.parent.isLoading {
                        print("⚠️ WebView loading timeout - hiding loading indicator")
                        self.parent.isLoading = false
                    }
                }
            }
        }
        
        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            DispatchQueue.main.async {
                self.parent.isLoading = true
                self.startLoadingTimeout()
                print("🔄 WebView started loading: \(webView.url?.absoluteString ?? "unknown")")
            }
        }
        
        func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
            DispatchQueue.main.async {
                print("✅ WebView committed navigation: \(webView.url?.absoluteString ?? "unknown")")
                // Save cookies on navigation commit to catch any new cookies
                self.sessionManager.saveCookies()
            }
        }
        
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            DispatchQueue.main.async {
                self.loadingTimer?.invalidate()
                
                // Small delay to ensure page is fully rendered
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    self.parent.isLoading = false
                    self.parent.canGoBack = webView.canGoBack
                    self.parent.canGoForward = webView.canGoForward
                    
                    print("✅ WebView finished loading: \(webView.url?.absoluteString ?? "unknown")")
                    
                    // Save cookies after page load - this ensures session is persisted
                    self.sessionManager.saveCookies()
                }
            }
        }
        
        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            DispatchQueue.main.async {
                self.loadingTimer?.invalidate()
                self.parent.isLoading = false
                print("❌ WebView navigation error: \(error.localizedDescription)")
            }
        }
        
        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            DispatchQueue.main.async {
                self.loadingTimer?.invalidate()
                self.parent.isLoading = false
                print("❌ WebView provisional navigation error: \(error.localizedDescription)")
            }
        }
        
        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            // Allow all navigation within the app
            decisionHandler(.allow)
        }
    }
}

