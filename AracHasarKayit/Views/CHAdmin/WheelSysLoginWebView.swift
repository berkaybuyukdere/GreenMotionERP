import SwiftUI
import WebKit

/// In-app WheelSys login — captures session cookies after successful sign-in.
struct WheelSysLoginWebView: UIViewRepresentable {
    static let loginURL = URL(string: "https://ch.wheelsys.greenmotion.com/ui/")!
    static let cookieDomain = "wheelsys.greenmotion.com"

    let onSessionCaptured: (String) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onSessionCaptured: onSessionCaptured)
    }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.customUserAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/15E148 VehicleSentinel"
        webView.load(URLRequest(url: Self.loginURL))
        context.coordinator.webView = webView
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    final class Coordinator: NSObject, WKNavigationDelegate {
        var webView: WKWebView?
        private let onSessionCaptured: (String) -> Void
        private var didCapture = false
        private var captureAttempts = 0

        init(onSessionCaptured: @escaping (String) -> Void) {
            self.onSessionCaptured = onSessionCaptured
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            guard let url = webView.url?.absoluteString else { return }
            guard url.contains("/ui/manage/") || url.contains("wheelsys.greenmotion.com/ui/") else { return }
            guard !url.contains("login") && !url.contains("signin") else { return }
            scheduleCapture(from: webView)
        }

        private func scheduleCapture(from webView: WKWebView) {
            guard !didCapture, captureAttempts < 8 else { return }
            captureAttempts += 1
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
                self?.tryCaptureCookies(from: webView)
            }
        }

        private func tryCaptureCookies(from webView: WKWebView) {
            guard !didCapture else { return }
            webView.configuration.websiteDataStore.httpCookieStore.getAllCookies { [weak self] cookies in
                guard let self else { return }
                let wheelsys = cookies.filter {
                    $0.domain.contains(WheelSysLoginWebView.cookieDomain)
                }
                let sid = wheelsys.first { $0.name == "__Secure-SID" }?.value ?? ""
                let ws = wheelsys.first { $0.name == ".wheelsys" }?.value ?? ""
                guard !sid.isEmpty, !ws.isEmpty else {
                    DispatchQueue.main.async {
                        self.scheduleCapture(from: webView)
                    }
                    return
                }

                let header = WheelSysCookieCache.buildAuthCookie(wheelsys: ws, secureSID: sid)
                WheelSysCookieCache.logPresence(header, label: "webview capture")

                self.didCapture = true
                DispatchQueue.main.async {
                    WheelSysCookieCache.set(header)
                    self.onSessionCaptured(header)
                }
            }
        }
    }
}

struct WheelSysLoginSheet: View {
    let isSaving: Bool
    let onSessionCaptured: (String) -> Void
    let onCancel: () -> Void

    var body: some View {
        NavigationStack {
            ZStack {
                WheelSysLoginWebView(onSessionCaptured: onSessionCaptured)
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
