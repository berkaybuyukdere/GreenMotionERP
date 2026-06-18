import Foundation
import UIKit
import WebKit

// MARK: - Errors

enum WheelSysAvailabilityFetchError: LocalizedError {
    case sessionExpired
    case notReady(String)
    case stepFailed(String, Int, String)
    case parseFailure(String)

    var errorDescription: String? {
        switch self {
        case .sessionExpired:
            return "wheelsys_availability.session_expired".localized
        case .notReady(let detail):
            return "Availability page not ready: \(detail)"
        case .stepFailed(let step, let status, let preview):
            return "Availability \(step) failed (HTTP \(status)). \(String(preview.prefix(300)))"
        case .parseFailure(let detail):
            return "Availability parse error: \(detail)"
        }
    }
}

// MARK: - Fetcher

@MainActor
final class WheelSysAvailabilityWebViewFetcher: NSObject {

    static let defaultGroups =
        "UP,T,Y,DS,A,C,J,HC,I,U,R,W,H,N,GG,Q,Z,X,DD,BB,AA,F,MC,V,E,G,O,EE,CC,S,D,K,L,M,FF,B,MB,MV,P"

    private static let pageURL = URL(
        string: "https://ch.wheelsys.greenmotion.com/ui/dashboards/availability.aspx"
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
    private let dateFrom: String
    private let dateTo: String
    private let groups: String
    private var fetchAttempt = 0
    private var readyWaitRetries = 0
    private var isRunningFetch = false

    init(
        station: String = "ZRH",
        dateFrom: String = "2026-06-11T00:00:00.000Z",
        dateTo: String = "2026-07-19T23:59:59.000Z",
        groups: String = WheelSysAvailabilityWebViewFetcher.defaultGroups
    ) {
        self.station = station
        self.dateFrom = dateFrom
        self.dateTo = dateTo
        self.groups = groups
    }

    static func fetch(
        station: String = "ZRH",
        dateFrom: String = "2026-06-11T00:00:00.000Z",
        dateTo: String = "2026-07-19T23:59:59.000Z",
        groups: String = defaultGroups
    ) async throws -> String {
        try await WheelSysAvailabilityWebViewFetcher(
            station: station,
            dateFrom: dateFrom,
            dateTo: dateTo,
            groups: groups
        ).fetchRawJSON()
    }

    func fetchRawJSON() async throws -> String {
        guard WheelSysCookieCache.isValid else {
            throw WheelSysAvailabilityFetchError.sessionExpired
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
                wv.load(URLRequest(url: Self.pageURL))
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
        return lower.contains("sign-in") || lower.contains("signin") || lower.contains("/login")
    }

    private func scheduleFetch(after delay: TimeInterval) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            self?.runFetch()
        }
    }

    private static let availabilityJS = """
        const sleep = ms => new Promise(resolve => setTimeout(resolve, ms));

        const diagnostics = {
            href: location.href,
            readyState: document.readyState,
            title: document.title,
            cookieLength: document.cookie ? document.cookie.length : 0,
            bodyHasSignIn: document.body && document.body.innerText
                ? document.body.innerText.includes('Sign In') : false,
            bodyHasAvailability: document.body && document.body.innerText
                ? document.body.innerText.toLowerCase().includes('availability') : false
        };

        if (diagnostics.bodyHasSignIn || location.href.indexOf('/sign-in/') >= 0) {
            return JSON.stringify({
                ok: false,
                step: 'LoginRequired',
                diagnostics: diagnostics
            });
        }

        if (document.readyState !== 'complete') {
            return JSON.stringify({
                ok: false,
                step: 'NotReady',
                diagnostics: diagnostics
            });
        }

        const paramsObject = {
            cacheKey: crypto.randomUUID ? crypto.randomUUID() : 'availability-' + Date.now(),
            dateFormat: 'dd/MM/yyyy',
            dateFrom: dateFrom,
            dateTo: dateTo,
            stations: stations,
            groups: groups,
            hourIntervals: 1,
            uninsured: true,
            forecast: true,
            grace: true,
            showAllMetrics: true,
            useClass: false
        };

        const headers = {
            'accept': 'application/json, text/javascript, */*; q=0.01',
            'accept-language': 'tr-TR,tr;q=0.9,en-US;q=0.8,en;q=0.7,de;q=0.6',
            'cache-control': 'no-cache',
            'content-type': 'application/json; charset=UTF-8',
            'pragma': 'no-cache',
            'x-requested-with': 'XMLHttpRequest'
        };

        try {
            const getDataBody = JSON.stringify({
                Params: JSON.stringify(paramsObject)
            });

            const getDataResponse = await fetch(
                'https://ch.wheelsys.greenmotion.com/ui/dashboards/availability.aspx/GetData',
                {
                    method: 'POST',
                    mode: 'cors',
                    credentials: 'include',
                    referrer: 'https://ch.wheelsys.greenmotion.com/ui/dashboards/availability.aspx',
                    headers: headers,
                    body: getDataBody
                }
            );

            const getDataText = await getDataResponse.text();

            let getDataOuter = null;
            let cacheKey = null;

            try {
                getDataOuter = JSON.parse(getDataText);
                cacheKey = getDataOuter && getDataOuter.d ? getDataOuter.d : null;
            } catch (parseError) {
                return JSON.stringify({
                    ok: false,
                    step: 'GetDataParseFailed',
                    getDataStatus: getDataResponse.status,
                    getDataTextPreview: getDataText.slice(0, 1000),
                    diagnostics: diagnostics,
                    error: String(parseError)
                });
            }

            if (!getDataResponse.ok || !cacheKey) {
                return JSON.stringify({
                    ok: false,
                    step: 'GetDataFailed',
                    getDataStatus: getDataResponse.status,
                    getDataTextPreview: getDataText.slice(0, 1000),
                    cacheKey: cacheKey,
                    diagnostics: diagnostics
                });
            }

            const cacheBody = JSON.stringify({
                cacheKey: cacheKey,
                metric: 'available'
            });

            let finalRows = null;
            let finalCacheText = null;
            let finalCacheStatus = null;
            let readyAttempt = null;

            for (let attempt = 1; attempt <= 10; attempt++) {
                await sleep(1000);

                const cacheResponse = await fetch(
                    'https://ch.wheelsys.greenmotion.com/ui/dashboards/availability.aspx/GetDataFromCacheKey',
                    {
                        method: 'POST',
                        mode: 'cors',
                        credentials: 'include',
                        referrer: 'https://ch.wheelsys.greenmotion.com/ui/dashboards/availability.aspx',
                        headers: headers,
                        body: cacheBody
                    }
                );

                const cacheText = await cacheResponse.text();
                finalCacheText = cacheText;
                finalCacheStatus = cacheResponse.status;

                let cacheOuter = null;
                try {
                    cacheOuter = JSON.parse(cacheText);
                } catch (parseError) {
                    return JSON.stringify({
                        ok: false,
                        step: 'CacheOuterParseFailed',
                        getDataStatus: getDataResponse.status,
                        cacheStatus: cacheResponse.status,
                        cacheTextPreview: cacheText.slice(0, 1000),
                        cacheKey: cacheKey,
                        diagnostics: diagnostics,
                        error: String(parseError)
                    });
                }

                if (cacheOuter && cacheOuter.d) {
                    try {
                        finalRows = JSON.parse(cacheOuter.d);
                        readyAttempt = attempt;
                        break;
                    } catch (parseError) {
                        return JSON.stringify({
                            ok: false,
                            step: 'RowsParseFailed',
                            getDataStatus: getDataResponse.status,
                            cacheStatus: cacheResponse.status,
                            cacheTextPreview: cacheText.slice(0, 1000),
                            cacheKey: cacheKey,
                            diagnostics: diagnostics,
                            error: String(parseError)
                        });
                    }
                }
            }

            if (!finalRows) {
                return JSON.stringify({
                    ok: false,
                    step: 'RowsStillNullAfterPolling',
                    getDataStatus: getDataResponse.status,
                    cacheStatus: finalCacheStatus,
                    cacheTextPreview: finalCacheText ? finalCacheText.slice(0, 1000) : null,
                    cacheKey: cacheKey,
                    diagnostics: diagnostics
                });
            }

            return JSON.stringify({
                ok: true,
                step: 'Success',
                getDataStatus: getDataResponse.status,
                cacheStatus: finalCacheStatus,
                cacheKey: cacheKey,
                readyAttempt: readyAttempt,
                rowsCount: finalRows.length,
                rows: finalRows,
                diagnostics: diagnostics
            });
        } catch (error) {
            return JSON.stringify({
                ok: false,
                step: 'Exception',
                error: String(error),
                diagnostics: diagnostics
            });
        }
        """

    private func runFetch() {
        guard let wv = webView, !isRunningFetch else { return }
        guard fetchAttempt < 3 else { return }

        let pageURL = wv.url?.absoluteString ?? ""
        if Self.isSignInURL(pageURL) {
            fail(WheelSysAvailabilityFetchError.sessionExpired)
            return
        }

        isRunningFetch = true
        fetchAttempt += 1
        print("[WheelSysAvailabilityWebView] JS started")

        wv.callAsyncJavaScript(
            Self.availabilityJS,
            arguments: [
                "dateFrom": dateFrom,
                "dateTo": dateTo,
                "stations": station,
                "groups": groups,
            ],
            in: nil,
            in: .page
        ) { [weak self] result in
            Task { @MainActor in
                guard let self else { return }
                self.isRunningFetch = false
                switch result {
                case .success(let value):
                    if let jsonString = value as? String {
                        self.handleJSString(jsonString)
                    } else {
                        print("[WheelSysAvailabilityWebView] unexpected JS result type: \(type(of: value))")
                        self.retryOrFail(parseFailure: "unexpected JS result type")
                    }
                case .failure(let error):
                    print("[WheelSysAvailabilityWebView] JS error: \(error.localizedDescription)")
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

        logDiagnostics(obj["diagnostics"] as? [String: Any])

        let step = obj["step"] as? String ?? ""
        if step == "LoginRequired" {
            fail(WheelSysAvailabilityFetchError.sessionExpired)
            return
        }
        if step == "NotReady" {
            if readyWaitRetries < 12 {
                readyWaitRetries += 1
                fetchAttempt -= 1
                scheduleFetch(after: 1.0)
                return
            }
            fail(WheelSysAvailabilityFetchError.notReady("page not ready after retries"))
            return
        }

        let getDataStatus = (obj["getDataStatus"] as? NSNumber)?.intValue ?? 0
        let cacheStatus = (obj["cacheStatus"] as? NSNumber)?.intValue ?? 0
        let cacheKey = obj["cacheKey"] as? String ?? ""
        let rowsCount = (obj["rowsCount"] as? NSNumber)?.intValue ?? 0
        let readyAttempt = (obj["readyAttempt"] as? NSNumber)?.intValue
        let ok = obj["ok"] as? Bool ?? false

        print("[WheelSysAvailabilityWebView] GetData status=\(getDataStatus)")
        if !cacheKey.isEmpty {
            print("[WheelSysAvailabilityWebView] cacheKey=\(cacheKey)")
        }
        if cacheStatus > 0 {
            print("[WheelSysAvailabilityWebView] GetDataFromCacheKey status=\(cacheStatus)")
        }
        if let readyAttempt {
            print("[WheelSysAvailabilityWebView] readyAttempt=\(readyAttempt)")
        }
        print("[WheelSysAvailabilityWebView] rowsCount=\(rowsCount)")

        if let rows = obj["rows"] as? [[String: Any]], let first = rows.first {
            let cls = first["VehicleClass"] as? String ?? "?"
            let grp = first["CarGroup"] as? String ?? "?"
            let hourKeys = first.keys.filter { $0.count == 10 && $0.allSatisfy(\.isNumber) }
            print("[WheelSysAvailabilityWebView] firstRowClass=\(cls)")
            print("[WheelSysAvailabilityWebView] firstRowGroup=\(grp)")
            print("[WheelSysAvailabilityWebView] firstRowHourKeysCount=\(hourKeys.count)")
        }

        guard ok, getDataStatus == 200, rowsCount > 0 else {
            let preview = (obj["cacheTextPreview"] as? String)
                ?? (obj["getDataTextPreview"] as? String)
                ?? (obj["error"] as? String)
                ?? step
            print("[WheelSysAvailabilityWebView] preview=\(String(preview.prefix(500)))")
            let status = cacheStatus > 0 ? cacheStatus : getDataStatus
            if status == 401 {
                fail(WheelSysAvailabilityFetchError.sessionExpired)
                return
            }
            fail(WheelSysAvailabilityFetchError.stepFailed(step, status, preview))
            return
        }

        continuation?.resume(returning: raw)
        continuation = nil
        cleanup()
    }

    private func logDiagnostics(_ diag: [String: Any]?) {
        guard let diag else { return }
        print("[WheelSysAvailabilityWebView] diagnostics href=\(diag["href"] ?? "?")")
        print("[WheelSysAvailabilityWebView] diagnostics readyState=\(diag["readyState"] ?? "?")")
        print("[WheelSysAvailabilityWebView] diagnostics cookieLength=\(diag["cookieLength"] ?? "?")")
        print("[WheelSysAvailabilityWebView] diagnostics bodyHasSignIn=\(diag["bodyHasSignIn"] ?? "?")")
        print("[WheelSysAvailabilityWebView] diagnostics bodyHasAvailability=\(diag["bodyHasAvailability"] ?? "?")")
    }

    private func handleCallError(_ error: Error) {
        retryOrFail(parseFailure: error.localizedDescription)
    }

    private func retryOrFail(parseFailure message: String) {
        if fetchAttempt < 3 {
            scheduleFetch(after: 1.5)
            return
        }
        fail(WheelSysAvailabilityFetchError.parseFailure(message))
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

extension WheelSysAvailabilityWebViewFetcher: WKNavigationDelegate {
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        let url = webView.url?.absoluteString ?? ""
        print("[WheelSysAvailabilityWebView] page loaded url=\(url)")

        if Self.isSignInURL(url) {
            fail(WheelSysAvailabilityFetchError.sessionExpired)
            return
        }

        let onAvailabilityPage = url.lowercased().contains("availability.aspx")
        let onWheelSysUI = url.contains("wheelsys.greenmotion.com/ui")
        guard onAvailabilityPage || onWheelSysUI else { return }

        fetchAttempt = 0
        readyWaitRetries = 0
        scheduleFetch(after: Self.pageInitDelay)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        fail(error)
    }

    func webView(
        _ webView: WKWebView,
        didFailProvisionalNavigation navigation: WKNavigation!,
        withError error: Error
    ) {
        fail(error)
    }
}
