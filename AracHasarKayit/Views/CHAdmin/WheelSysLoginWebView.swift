import SwiftUI
import WebKit

/// In-app WheelSys login — captures session cookies after successful sign-in.
struct WheelSysLoginWebView: UIViewRepresentable {
    static let loginURL = URL(string: "https://ch.wheelsys.greenmotion.com/ui/")!
    static let cookieDomain = "wheelsys.greenmotion.com"

    /// When true, wipe WK cookies and only capture after the user visits the sign-in page.
    var requireFreshLogin: Bool = false
    let onSessionCaptured: (String) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(requireFreshLogin: requireFreshLogin, onSessionCaptured: onSessionCaptured)
    }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.customUserAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/15E148 VehicleSentinel"
        context.coordinator.attach(to: webView)
        if requireFreshLogin {
            context.coordinator.prepareFreshLogin(in: webView)
        } else {
            webView.load(URLRequest(url: Self.loginURL))
        }
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {
        if requireFreshLogin != context.coordinator.requireFreshLogin {
            context.coordinator.requireFreshLogin = requireFreshLogin
            if requireFreshLogin {
                context.coordinator.didCapture = false
                context.coordinator.captureAttempts = 0
                context.coordinator.sawLoginPage = false
                context.coordinator.prepareFreshLogin(in: uiView)
            }
        }
    }

    /// Remove persisted WheelSys website data so sign-out shows the real login form.
    static func clearWebsiteData(completion: (() -> Void)? = nil) {
        let store = WKWebsiteDataStore.default()
        let types = WKWebsiteDataStore.allWebsiteDataTypes()
        store.fetchDataRecords(ofTypes: types) { records in
            let wheelsysRecords = records.filter {
                $0.displayName.contains(cookieDomain) ||
                $0.displayName.contains("greenmotion.com")
            }
            store.removeData(ofTypes: types, for: wheelsysRecords) {
                DispatchQueue.main.async { completion?() }
            }
        }
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKHTTPCookieStoreObserver {
        var webView: WKWebView?
        var requireFreshLogin: Bool
        private let onSessionCaptured: (String) -> Void
        var didCapture = false
        var captureAttempts = 0
        var sawLoginPage = false
        private var isObservingCookies = false

        init(requireFreshLogin: Bool, onSessionCaptured: @escaping (String) -> Void) {
            self.requireFreshLogin = requireFreshLogin
            self.onSessionCaptured = onSessionCaptured
        }

        deinit {
            stopObservingCookies()
        }

        func attach(to webView: WKWebView) {
            self.webView = webView
            startObservingCookies(in: webView)
        }

        private func startObservingCookies(in webView: WKWebView) {
            guard !isObservingCookies else { return }
            webView.configuration.websiteDataStore.httpCookieStore.add(self)
            isObservingCookies = true
        }

        private func stopObservingCookies() {
            guard isObservingCookies, let webView else { return }
            webView.configuration.websiteDataStore.httpCookieStore.remove(self)
            isObservingCookies = false
        }

        func prepareFreshLogin(in webView: WKWebView) {
            didCapture = false
            captureAttempts = 0
            sawLoginPage = false
            WheelSysLoginWebView.clearWebsiteData { [weak self, weak webView] in
                guard let self, let webView else { return }
                webView.load(URLRequest(url: WheelSysLoginWebView.loginURL))
            }
        }

        func cookiesDidChange(in cookieStore: WKHTTPCookieStore) {
            guard !didCapture, let webView else { return }
            cookieStore.getAllCookies { [weak self] cookies in
                guard let self, !self.didCapture else { return }
                guard Self.extractAuthHeader(from: cookies) != nil else { return }
                if self.requireFreshLogin {
                    self.sawLoginPage = true
                }
                DispatchQueue.main.async {
                    self.scheduleCapture(from: webView)
                }
            }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            guard let url = webView.url?.absoluteString else { return }
            let lower = url.lowercased()
            if Self.isLoginURL(lower) {
                sawLoginPage = true
            }

            guard Self.isCaptureEligibleURL(url, lower: lower) else { return }

            if requireFreshLogin && !sawLoginPage {
                if Self.isAuthenticatedAppURL(url, lower: lower) {
                    // Cookies were cleared before fresh login — app pages imply sign-in completed.
                    sawLoginPage = true
                } else {
                    WheelSysDebug.logCH(
                        franchiseId: FirebaseService.shared.currentFranchiseId,
                        "Session",
                        "login webview waiting for auth navigation url=\(url)"
                    )
                    return
                }
            }
            scheduleCapture(from: webView)
        }

        private func scheduleCapture(from webView: WKWebView) {
            guard !didCapture, captureAttempts < 24 else { return }
            captureAttempts += 1
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
                self?.tryCaptureCookies(from: webView)
            }
        }

        private func tryCaptureCookies(from webView: WKWebView) {
            guard !didCapture else { return }
            webView.configuration.websiteDataStore.httpCookieStore.getAllCookies { [weak self] cookies in
                guard let self else { return }
                guard let header = Self.extractAuthHeader(from: cookies) else {
                    DispatchQueue.main.async {
                        self.scheduleCapture(from: webView)
                    }
                    return
                }

                WheelSysCookieCache.logPresence(header, label: "webview capture")

                Task { @MainActor in
                    if let user = await WheelSysLoggedInUserDetection.detect(in: webView) {
                        WheelSysCookieCache.setWheelSysOperator(
                            id: user.id,
                            franchiseId: FirebaseService.shared.currentFranchiseId
                        )
                        WheelSysDebug.logCH(
                            franchiseId: FirebaseService.shared.currentFranchiseId,
                            "Session",
                            "login detected wheelsys user id=\(user.id)"
                        )
                    }
                    self.finishSessionCapture(header: header)
                }
            }
        }

        @MainActor
        private func finishSessionCapture(header: String) {
            guard !didCapture else { return }
            didCapture = true
            WheelSysCookieCache.set(
                header,
                franchiseId: FirebaseService.shared.currentFranchiseId
            )
            onSessionCaptured(header)
        }

        private static func isLoginURL(_ lower: String) -> Bool {
            lower.contains("login")
                || lower.contains("signin")
                || lower.contains("sign-in")
                || lower.contains("account/login")
                || lower.contains("/auth")
        }

        private static func isAuthenticatedAppURL(_ url: String, lower: String) -> Bool {
            url.contains("/ui/manage/")
                || lower.contains("dashboard")
                || lower.contains("fleetchart")
                || lower.contains("rentals.aspx")
        }

        private static func isCaptureEligibleURL(_ url: String, lower: String) -> Bool {
            url.contains("/ui/manage/")
                || url.contains("wheelsys.greenmotion.com/ui/")
        }

        private static func extractAuthHeader(from cookies: [HTTPCookie]) -> String? {
            let wheelsys = cookies.filter { $0.domain.contains(WheelSysLoginWebView.cookieDomain) }
            let sid = wheelsys.first { $0.name == "__Secure-SID" }?.value ?? ""
            let ws = wheelsys.first { $0.name == ".wheelsys" }?.value ?? ""
            guard !sid.isEmpty, !ws.isEmpty else { return nil }
            return WheelSysCookieCache.buildAuthCookie(wheelsys: ws, secureSID: sid)
        }
    }
}

struct WheelSysLoginSheet: View {
    let isSaving: Bool
    var requireFreshLogin: Bool = false
    let onSessionCaptured: (String) -> Void
    let onCancel: () -> Void

    var body: some View {
        NavigationStack {
            ZStack {
                WheelSysLoginWebView(
                    requireFreshLogin: requireFreshLogin,
                    onSessionCaptured: onSessionCaptured
                )
                .ignoresSafeArea(edges: .bottom)

                if isSaving {
                    Color.black.opacity(0.35).ignoresSafeArea()
                    VStack(spacing: 12) {
                        ProgressView()
                            .tint(.white)
                        Text("wheelsys_checkin.session_saving".localized)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.white)
                    }
                    .padding(24)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                }
            }
            .navigationTitle("wheelsys_checkin.login_title".localized)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel".localized) { onCancel() }
                        .disabled(isSaving)
                }
            }
            .interactiveDismissDisabled(isSaving)
        }
    }
}
