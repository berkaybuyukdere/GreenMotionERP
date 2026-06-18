import Foundation
import UIKit
import WebKit

// MARK: - Errors

enum WheelSysFleetFetchError: LocalizedError {
    case sessionExpired
    case jsTypeError
    case httpError(Int, String)
    case parseFailure(String)

    var errorDescription: String? {
        switch self {
        case .sessionExpired:
            return "wheelsys_fleet.session_expired".localized
        case .jsTypeError:
            return "Fleet Chart JS returned unexpected type."
        case .httpError(let code, let preview):
            return "Fleet Chart HTTP \(code). \(String(preview.prefix(300)))"
        case .parseFailure(let detail):
            return "Fleet Chart parse error: \(detail)"
        }
    }
}

// MARK: - Fetcher

/// Runs the Fleet Chart POST request inside the authenticated WKWebView session context.
@MainActor
final class WheelSysFleetWebViewFetcher: NSObject {

    private static let fleetPageURL = URL(
        string: "https://ch.wheelsys.greenmotion.com/ui/dashboards/fleetchart.aspx"
    )!
    private static let cookieDomain = "ch.wheelsys.greenmotion.com"
    private static let pageInitDelay: TimeInterval = 2.5
    private static let userAgent =
        "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 "
        + "(KHTML, like Gecko) Mobile/15E148 VehicleSentinel"

    private var webView: WKWebView?
    private var hostWindow: UIWindow?
    private var continuation: CheckedContinuation<String, Error>?
    private let station: String
    private let startMs: Int64
    private let endMs: Int64
    private var fetchAttempt = 0
    private var isRunningFetch = false

    init(station: String = "ZRH", windowDays: Int = 20) {
        self.station = station
        let (start, end) = Self.dateWindowMs(windowDays: windowDays)
        self.startMs = start
        self.endMs = end
    }

    static func fetch(station: String = "ZRH", windowDays: Int = 20) async throws -> String {
        try await WheelSysFleetWebViewFetcher(station: station, windowDays: windowDays).fetchRawJSON()
    }

    /// Dynamic fleet window: today 00:00 -> +windowDays 23:59:59 (Europe/Zurich).
    /// Replaces the previously hardcoded `/Date(...)/` body so today's events are always visible.
    private static func dateWindowMs(windowDays: Int) -> (Int64, Int64) {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Europe/Zurich") ?? .current
        let startOfToday = cal.startOfDay(for: Date())
        let endDay = cal.date(byAdding: .day, value: max(1, windowDays), to: startOfToday) ?? startOfToday
        // 23:59:59 of the end day
        let endOfWindow = (cal.date(bySettingHour: 23, minute: 59, second: 59, of: endDay)) ?? endDay
        let startMs = Int64(startOfToday.timeIntervalSince1970 * 1000)
        let endMs = Int64(endOfWindow.timeIntervalSince1970 * 1000)
        return (startMs, endMs)
    }

    /// Build the Fleet Chart POST body JSON dynamically for the given station + window.
    private func makeBodyBase64() -> String {
        // Match Chrome DevTools payload exactly, including escaped forward slashes in /Date(...)/.
        let json = "{\"startDate\":\"\\/Date(\(startMs))\\/\",\"endDate\":\"\\/Date(\(endMs))\\/\","
            + "\"selectedStations\":\",\(station),\",\"expandedResources\":null,\"expandAll\":true}"
        return Data(json.utf8).base64EncodedString()
    }

    func fetchRawJSON() async throws -> String {
        guard WheelSysCookieCache.isValid else {
            throw WheelSysFleetFetchError.sessionExpired
        }

        return try await withCheckedThrowingContinuation { cont in
            self.continuation = cont

            let config = WKWebViewConfiguration()
            config.websiteDataStore = .default()
            config.defaultWebpagePreferences.allowsContentJavaScript = true

            let wv = WKWebView(
                frame: CGRect(x: 0, y: 0, width: 375, height: 812),
                configuration: config
            )
            wv.customUserAgent = Self.userAgent
            wv.navigationDelegate = self
            attachToHiddenWindow(wv)
            self.webView = wv

            injectCachedCookies(into: config.websiteDataStore.httpCookieStore) {
                wv.load(URLRequest(url: Self.fleetPageURL))
                print("[WheelSysFleetWebView] page load started")
            }
        }
    }

    // MARK: Private

    private func injectCachedCookies(into store: WKHTTPCookieStore, completion: @escaping () -> Void) {
        guard let header = WheelSysCookieCache.lastCookie else {
            completion()
            return
        }

        var cookies: [HTTPCookie] = []
        for part in header.split(separator: ";") {
            let piece = part.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let eq = piece.firstIndex(of: "=") else { continue }
            let name = String(piece[..<eq]).trimmingCharacters(in: .whitespacesAndNewlines)
            let value = String(piece[piece.index(after: eq)...])
            guard !name.isEmpty, !value.isEmpty else { continue }

            var properties: [HTTPCookiePropertyKey: Any] = [
                .name: name,
                .value: value,
                .domain: Self.cookieDomain,
                .path: "/",
            ]
            if name.hasPrefix("__Secure-") {
                properties[.secure] = "TRUE"
            }
            if let cookie = HTTPCookie(properties: properties) {
                cookies.append(cookie)
            }
        }

        guard !cookies.isEmpty else {
            completion()
            return
        }

        let group = DispatchGroup()
        for cookie in cookies {
            group.enter()
            store.setCookie(cookie) { group.leave() }
        }
        group.notify(queue: .main, execute: completion)
    }

    private func attachToHiddenWindow(_ webView: WKWebView) {
        guard let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive || $0.activationState == .foregroundInactive })
            ?? UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first
        else { return }

        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: -2000, y: -2000, width: 375, height: 812)
        window.windowLevel = .normal - 1
        window.isHidden = false
        let host = UIViewController()
        host.view.addSubview(webView)
        webView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            webView.topAnchor.constraint(equalTo: host.view.topAnchor),
            webView.leadingAnchor.constraint(equalTo: host.view.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: host.view.trailingAnchor),
            webView.bottomAnchor.constraint(equalTo: host.view.bottomAnchor),
        ])
        window.rootViewController = host
        hostWindow = window
    }

    private static func isSignInURL(_ url: String) -> Bool {
        let lower = url.lowercased()
        return lower.contains("sign-in")
            || lower.contains("signin")
            || lower.contains("/login")
    }

    private func scheduleFetch(after delay: TimeInterval) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            self?.runFetch()
        }
    }

    private func makeFleetChartJS() -> String {
        """
        const bodyBase64 = '\(makeBodyBase64())';
        const rawBody = atob(bodyBase64);
        console.log('[WheelSysFleetWebView JS] rawBody=' + rawBody);

        try {
            const diagnostics = {
                href: location.href,
                readyState: document.readyState,
                title: document.title,
                cookieLength: document.cookie ? document.cookie.length : 0,
                hasJQuery: typeof window.jQuery !== 'undefined',
                hasDollar: typeof window.$ !== 'undefined',
                bodyHasSignIn: document.body && document.body.innerText
                    ? document.body.innerText.indexOf('Sign In') >= 0 : false,
                bodyHasFleet: document.body && document.body.innerText
                    ? document.body.innerText.toLowerCase().indexOf('fleet') >= 0 : false,
                rawBody: rawBody,
                rawBodyLength: rawBody.length
            };

            const response = await fetch('https://ch.wheelsys.greenmotion.com/ui/dashboards/fleetchart.aspx/GetFleetchartData', {
                method: 'POST',
                mode: 'cors',
                credentials: 'include',
                referrer: 'https://ch.wheelsys.greenmotion.com/ui/dashboards/fleetchart.aspx',
                headers: {
                    'accept': '*/*',
                    'accept-language': 'tr-TR,tr;q=0.9,en-US;q=0.8,en;q=0.7,de;q=0.6',
                    'cache-control': 'no-cache',
                    'content-type': 'application/json; charset=UTF-8',
                    'pragma': 'no-cache',
                    'x-requested-with': 'XMLHttpRequest'
                },
                body: rawBody
            });

            const text = await response.text();

            return JSON.stringify({
                ok: response.ok,
                status: response.status,
                responseText: text,
                responseLength: text.length,
                diagnostics: diagnostics
            });
        } catch (e) {
            return JSON.stringify({
                ok: false,
                status: 0,
                error: String(e),
                responseText: '',
                responseLength: 0,
                diagnostics: {
                    href: location.href,
                    readyState: document.readyState,
                    title: document.title,
                    cookieLength: document.cookie ? document.cookie.length : 0,
                    rawBody: rawBody,
                    rawBodyLength: rawBody.length
                }
            });
        }
        """
    }

    private func runFetch() {
        guard let wv = webView, !isRunningFetch else { return }
        guard fetchAttempt < 3 else { return }

        let pageURL = wv.url?.absoluteString ?? ""
        if Self.isSignInURL(pageURL) {
            print("[WheelSysFleetWebView] on sign-in page — session required")
            fail(WheelSysFleetFetchError.sessionExpired)
            return
        }

        isRunningFetch = true
        fetchAttempt += 1
        WheelSysDebug.log("Fleet", "window start=\(startMs) end=\(endMs) station=\(station)")
        print("[WheelSysFleetWebView] using base64 raw body via atob")
        print("[WheelSysFleetWebView] JS fetch started")

        wv.callAsyncJavaScript(
            makeFleetChartJS(),
            arguments: [:],
            in: nil,
            in: .page
        ) { [weak self] result in
            Task { @MainActor in
                guard let self else { return }
                self.isRunningFetch = false
                switch result {
                case .success(let value):
                    self.handleJSString(value as? String ?? "")
                case .failure(let error):
                    self.handleCallError(error)
                }
            }
        }
    }

    private func handleJSString(_ raw: String) {
        guard !raw.isEmpty,
              let data = raw.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            retryOrFail(parseFailure: "JS wrapper JSON invalid")
            return
        }

        if let diag = obj["diagnostics"] as? [String: Any] {
            logDiagnostics(diag)
        }

        let status = (obj["status"] as? NSNumber)?.intValue ?? 0
        let responseText = obj["responseText"] as? String ?? ""
        let responseLength = (obj["responseLength"] as? NSNumber)?.intValue ?? responseText.count
        let jsError = obj["error"] as? String

        print("[WheelSysFleetWebView] HTTP status=\(status)")
        print("[WheelSysFleetWebView] responseLength=\(responseLength)")

        if status != 200 {
            let preview = responseText.isEmpty ? (jsError ?? "empty") : String(responseText.prefix(500))
            print("[WheelSysFleetWebView] preview=\(preview)")
            fail(WheelSysFleetFetchError.httpError(status, preview))
            return
        }

        print("[WheelSysFleetWebView] JS result status=\(status)")

        guard !responseText.isEmpty else {
            print("[WheelSysFleetWebView] preview=empty")
            fail(WheelSysFleetFetchError.parseFailure("empty responseText on HTTP 200"))
            return
        }

        // Normalize for parseFleetWebViewResponse
        let normalized: [String: Any] = ["status": status, "body": responseText]
        guard let normData = try? JSONSerialization.data(withJSONObject: normalized),
              let normStr = String(data: normData, encoding: .utf8)
        else {
            fail(WheelSysFleetFetchError.parseFailure("normalize failed"))
            return
        }

        continuation?.resume(returning: normStr)
        continuation = nil
        cleanup()
    }

    private func logDiagnostics(_ diag: [String: Any]) {
        print("[WheelSysFleetWebView] diagnostics href=\(diag["href"] ?? "?")")
        print("[WheelSysFleetWebView] diagnostics readyState=\(diag["readyState"] ?? "?")")
        print("[WheelSysFleetWebView] diagnostics title=\(diag["title"] ?? "?")")
        print("[WheelSysFleetWebView] diagnostics cookieLength=\(diag["cookieLength"] ?? "?")")
        print("[WheelSysFleetWebView] diagnostics hasJQuery=\(diag["hasJQuery"] ?? "?")")
        print("[WheelSysFleetWebView] diagnostics bodyHasSignIn=\(diag["bodyHasSignIn"] ?? "?")")
        print("[WheelSysFleetWebView] diagnostics bodyHasFleet=\(diag["bodyHasFleet"] ?? "?")")
        print("[WheelSysFleetWebView] diagnostics rawBody=\(diag["rawBody"] ?? "?")")
        print("[WheelSysFleetWebView] diagnostics rawBodyLength=\(diag["rawBodyLength"] ?? "?")")
    }

    private func handleCallError(_ error: Error) {
        print("[WheelSysFleetWebView] callAsyncJavaScript error: \(error.localizedDescription)")
        retryOrFail(parseFailure: error.localizedDescription)
    }

    private func retryOrFail(parseFailure message: String) {
        if fetchAttempt < 3 {
            print("[WheelSysFleetWebView] retrying fetch after error: \(message)")
            scheduleFetch(after: 1.5)
            return
        }
        fail(WheelSysFleetFetchError.parseFailure(message))
    }

    private func fail(_ error: Error) {
        guard continuation != nil else { return }
        continuation?.resume(throwing: error)
        continuation = nil
        cleanup()
    }

    private func cleanup() {
        webView?.navigationDelegate = nil
        webView?.removeFromSuperview()
        webView = nil
        hostWindow?.isHidden = true
        hostWindow?.rootViewController = nil
        hostWindow = nil
    }
}

// MARK: - WKNavigationDelegate

extension WheelSysFleetWebViewFetcher: WKNavigationDelegate {
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        let url = webView.url?.absoluteString ?? ""
        print("[WheelSysFleetWebView] page loaded url=\(url)")

        if Self.isSignInURL(url) {
            fail(WheelSysFleetFetchError.sessionExpired)
            return
        }
        guard url.lowercased().contains("fleetchart") else { return }

        fetchAttempt = 0
        print("[WheelSysFleetWebView] waiting \(Self.pageInitDelay)s for page init before Fleet Chart request")
        scheduleFetch(after: Self.pageInitDelay)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        print("[WheelSysFleetWebView] nav failed: \(error.localizedDescription)")
        fail(error)
    }

    func webView(
        _ webView: WKWebView,
        didFailProvisionalNavigation navigation: WKNavigation!,
        withError error: Error
    ) {
        print("[WheelSysFleetWebView] provisional nav failed: \(error.localizedDescription)")
        fail(error)
    }
}
