import Foundation
import UIKit
import WebKit

// MARK: - Errors

enum WheelSysRentalFetchError: LocalizedError {
    case sessionExpired
    case httpError(Int, String)
    case parseFailure(String)

    var errorDescription: String? {
        switch self {
        case .sessionExpired:
            return "wheelsys_journal.session_expired".localized
        case .httpError(let code, let preview):
            return "Rental page HTTP \(code). \(String(preview.prefix(300)))"
        case .parseFailure(let detail):
            return "Rental page parse error: \(detail)"
        }
    }
}

// MARK: - Fetcher

/// Fetches rental.aspx HTML inside authenticated WKWebView context (not backend proxy).
@MainActor
final class WheelSysRentalWebViewFetcher: NSObject {

    enum Mode: String {
        case diagnostics
        case detail
    }

    private static let fleetReferrerPage = URL(
        string: "https://ch.wheelsys.greenmotion.com/ui/dashboards/fleetchart.aspx"
    )!
    private static let cookieDomain = "ch.wheelsys.greenmotion.com"
    private static let pageInitDelay: TimeInterval = 1.5
    private static let userAgent =
        "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 "
        + "(KHTML, like Gecko) Mobile/15E148 VehicleSentinel"

    private var webView: WKWebView?
    private var hostWindow: UIWindow?
    private var continuation: CheckedContinuation<String, Error>?
    private let entityId: Int
    private let mode: Mode
    private var fetchAttempt = 0
    private var isRunningFetch = false

    init(entityId: Int, mode: Mode) {
        self.entityId = entityId
        self.mode = mode
    }

    static func fetchDiagnostics(entityId: Int) async throws -> WheelSysRentalDiagnostics {
        let raw = try await WheelSysRentalWebViewFetcher(entityId: entityId, mode: .diagnostics).fetchRawJSON()
        return try parseDiagnosticsResponse(raw, entityId: entityId)
    }

    static func fetchRentalDetail(entityId: Int) async throws -> WheelSysRentalDetail {
        let raw = try await WheelSysRentalWebViewFetcher(entityId: entityId, mode: .detail).fetchRawJSON()
        return try parseDetailResponse(raw, entityId: entityId)
    }

    func fetchRawJSON() async throws -> String {
        guard WheelSysCookieCache.isValid else {
            throw WheelSysRentalFetchError.sessionExpired
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
                wv.load(URLRequest(url: Self.fleetReferrerPage))
                print("[Journal] rental WebView page load started entityId=\(self.entityId) mode=\(self.mode.rawValue)")
            }
        }
    }

    // MARK: Parsing

    static func parseDiagnosticsResponse(_ raw: String, entityId: Int) throws -> WheelSysRentalDiagnostics {
        let obj = try decodeWrapper(raw)
        let status = (obj["status"] as? NSNumber)?.intValue ?? 0
        let htmlLength = (obj["htmlLength"] as? NSNumber)?.intValue ?? 0
        let title = obj["title"] as? String ?? ""

        print("[Journal] rental detail status=\(status)")
        print("[Journal] rental detail htmlLength=\(htmlLength)")

        guard status == 200 else {
            let preview = obj["error"] as? String ?? obj["textPreview"] as? String ?? ""
            if status == 401 || preview.lowercased().contains("sign in") {
                throw WheelSysRentalFetchError.sessionExpired
            }
            throw WheelSysRentalFetchError.httpError(status, preview)
        }

        let inputs = (obj["inputs"] as? [[String: Any]] ?? []).map { row in
            WheelSysRentalFieldDiagnostic(
                idAttr: string(row["id"]),
                name: string(row["name"]),
                type: string(row["type"]),
                valuePreview: string(row["valuePreview"])
            )
        }
        let selects = (obj["selects"] as? [[String: Any]] ?? []).map { row in
            WheelSysRentalSelectDiagnostic(
                idAttr: string(row["id"]),
                name: string(row["name"]),
                selectedValue: string(row["selectedValue"]),
                selectedText: string(row["selectedText"])
            )
        }
        let textareas = (obj["textareas"] as? [[String: Any]] ?? []).map { row in
            WheelSysRentalTextareaDiagnostic(
                idAttr: string(row["id"]),
                name: string(row["name"]),
                valuePreview: string(row["valuePreview"])
            )
        }

        return WheelSysRentalDiagnostics(
            entityId: entityId,
            status: status,
            htmlLength: htmlLength,
            title: title,
            inputs: inputs,
            selects: selects,
            textareas: textareas,
            visibleTextPreview: string(obj["visibleTextPreview"])
        )
    }

    static func parseDetailResponse(_ raw: String, entityId: Int) throws -> WheelSysRentalDetail {
        let obj = try decodeWrapper(raw)
        let status = (obj["status"] as? NSNumber)?.intValue ?? 0
        let htmlLength = (obj["htmlLength"] as? NSNumber)?.intValue ?? 0

        print("[Journal] detail status=\(status)")
        print("[Journal] detail htmlLength=\(htmlLength)")

        guard status == 200 else {
            let preview = obj["error"] as? String ?? ""
            if status == 401 || preview.lowercased().contains("sign in") {
                throw WheelSysRentalFetchError.sessionExpired
            }
            throw WheelSysRentalFetchError.httpError(status, preview)
        }

        let parsed = obj["parsed"] as? [String: Any] ?? obj
        let snapshot = (parsed["rawFieldSnapshot"] as? [String: String])
            ?? (parsed["rawFieldSnapshot"] as? [String: Any])?.compactMapValues { $0 as? String }
            ?? [:]

        let title = optionalString(parsed["title"]) ?? optionalString(obj["title"])
        let customerName = optionalString(parsed["customerName"])
        let rentalNumber = optionalString(parsed["rentalNumber"])
            ?? WheelSysJournalService.parseRentalNumber(from: title)

        print("[Journal] detail title=\(title ?? "-")")
        print("[Journal] parsed customerName=\(customerName ?? "-")")
        print("[Journal] parsed rentalNumber=\(rentalNumber ?? "-")")

        if customerName == nil {
            print("[Journal] rental detail parse missing fields entityId=\(entityId)")
        }

        return WheelSysRentalDetail(
            rentalEntityId: entityId,
            status: status,
            htmlLength: htmlLength,
            title: title,
            rentalNumber: rentalNumber,
            customerName: customerName,
            driverId: optionalString(parsed["driverId"]),
            reservationDateText: optionalString(parsed["reservationDateText"]),
            driverInfoJson: optionalString(parsed["driverInfoJson"]),
            agentBooker: nil,
            checkoutLocation: nil,
            checkinLocation: nil,
            mileageOutText: optionalString(parsed["mileageOutText"]),
            mileageOutHidden: optionalString(parsed["mileageOutHidden"]),
            mileageInText: optionalString(parsed["mileageInText"]),
            mileageInHidden: optionalString(parsed["mileageInHidden"]),
            fuelOutText: optionalString(parsed["fuelOutText"]),
            fuelOutHidden: optionalString(parsed["fuelOutHidden"]),
            fuelInText: optionalString(parsed["fuelInText"]),
            fuelInHidden: optionalString(parsed["fuelInHidden"]),
            rawFieldSnapshot: snapshot
        )
    }

    private static func decodeWrapper(_ raw: String) throws -> [String: Any] {
        guard !raw.isEmpty,
              let data = raw.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            throw WheelSysRentalFetchError.parseFailure("wrapper JSON invalid")
        }
        return obj
    }

    private static func string(_ value: Any?) -> String {
        switch value {
        case let s as String: return s
        case let n as NSNumber: return n.stringValue
        case .none: return ""
        default: return String(describing: value!)
        }
    }

    private static func optionalString(_ value: Any?) -> String? {
        let s = string(value).trimmingCharacters(in: .whitespacesAndNewlines)
        return s.isEmpty ? nil : s
    }

    private static func int(_ value: Any?) -> Int? {
        if let n = value as? NSNumber { return n.intValue }
        if let s = value as? String {
            let digits = s.filter { $0.isNumber }
            return digits.isEmpty ? nil : Int(digits)
        }
        return nil
    }

    private static func parseRentalDateTime(_ text: String?) -> Date? {
        guard let text, !text.isEmpty else { return nil }
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = iso.date(from: text) { return d }
        iso.formatOptions = [.withInternetDateTime]
        if let d = iso.date(from: text) { return d }
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        for fmt in ["yyyy-MM-dd'T'HH:mm:ss", "dd/MM/yyyy HH:mm", "dd.MM.yyyy HH:mm"] {
            df.dateFormat = fmt
            if let d = df.date(from: text) { return d }
        }
        return nil
    }

    // MARK: Private WebView

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

    private static let rentalPageJS = """
        const rentalUrl = 'https://ch.wheelsys.greenmotion.com/ui/manage/master/rental.aspx?entityId=' + entityId;

        function cleanText(value) {
            return String(value || '').replace(/\\u00a0/g, ' ').replace(/\\s+/g, ' ').trim();
        }

        function fieldValue(el) {
            if (!el) return '';
            if (el.tagName === 'SELECT') {
                const opt = el.options[el.selectedIndex];
                return cleanText(opt ? (opt.text || opt.value || '') : (el.value || ''));
            }
            return cleanText(el.value || el.getAttribute('value') || el.textContent || '');
        }

        function getValueByName(doc, name) {
            const el = doc.querySelector('[name="' + CSS.escape(name) + '"]');
            return fieldValue(el);
        }

        function getValueById(doc, id) {
            const el = doc.getElementById(id);
            return fieldValue(el);
        }

        function collectSnapshot(doc) {
            const snap = {};
            doc.querySelectorAll('input, select, textarea').forEach(el => {
                const key = el.name || el.id;
                if (!key) return;
                const v = fieldValue(el);
                if (v) snap[key] = v;
            });
            return snap;
        }

        function parseRentalNumber(title) {
            const m = String(title || '').match(/RNT-\\d+/);
            return m ? m[0] : '';
        }

        function parseRentalDetail(doc) {
            const snap = collectSnapshot(doc);
            const title = doc.title || '';
            const customerName = getValueById(doc, 'rdDriver_text') || getValueByName(doc, 'rdDriver_text');
            const driverId = getValueById(doc, 'rdDriver_value') || getValueByName(doc, 'rdDriver_value');
            const reservationDateText = getValueById(doc, 'rdResDate_text') || getValueByName(doc, 'rdResDate_text');
            const driverInfoJson = getValueById(doc, 'driverInfoContainer') || getValueByName(doc, 'driverInfoContainer');
            const rentalNumber = parseRentalNumber(title);
            const mileageOutText = getValueById(doc, 'rdMileageFrom_text');
            const mileageOutHidden = getValueById(doc, 'rdMileageFrom_hidden');
            const mileageInText = getValueById(doc, 'rdMileageTo_text');
            const mileageInHidden = getValueById(doc, 'rdMileageTo_hidden');
            const fuelOutText = getValueById(doc, 'rdTankFrom_text');
            const fuelOutHidden = getValueById(doc, 'rdTankFrom_hidden');
            const fuelInText = getValueById(doc, 'rdTankTo_text');
            const fuelInHidden = getValueById(doc, 'rdTankTo_hidden');

            return {
                title,
                rentalNumber,
                customerName,
                driverId,
                reservationDateText,
                driverInfoJson,
                mileageOutText,
                mileageOutHidden,
                mileageInText,
                mileageInHidden,
                fuelOutText,
                fuelOutHidden,
                fuelInText,
                fuelInHidden,
                rawFieldSnapshot: snap
            };
        }

        function buildDiagnostics(doc, status, htmlLength) {
            const inputs = [];
            doc.querySelectorAll('input').forEach((el, idx) => {
                if (inputs.length >= 100) return;
                inputs.push({
                    id: el.id || '',
                    name: el.name || '',
                    type: el.type || el.tagName.toLowerCase(),
                    valuePreview: String(fieldValue(el)).slice(0, 120)
                });
            });
            const selects = [];
            doc.querySelectorAll('select').forEach(el => {
                if (selects.length >= 50) return;
                const opt = el.options[el.selectedIndex];
                selects.push({
                    id: el.id || '',
                    name: el.name || '',
                    selectedValue: cleanText(el.value || ''),
                    selectedText: cleanText(opt ? (opt.text || '') : '')
                });
            });
            const textareas = [];
            doc.querySelectorAll('textarea').forEach(el => {
                if (textareas.length >= 50) return;
                textareas.push({
                    id: el.id || '',
                    name: el.name || '',
                    valuePreview: String(fieldValue(el)).slice(0, 120)
                });
            });
            const bodyText = doc.body ? cleanText(doc.body.innerText || '') : '';
            return {
                ok: true,
                mode: 'diagnostics',
                status,
                htmlLength,
                title: doc.title || '',
                inputs,
                selects,
                textareas,
                visibleTextPreview: bodyText.slice(0, 2000)
            };
        }

        try {
            const response = await fetch(rentalUrl, {
                method: 'GET',
                mode: 'cors',
                credentials: 'include',
                referrer: 'https://ch.wheelsys.greenmotion.com/ui/dashboards/fleetchart.aspx',
                headers: {
                    'accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
                    'cache-control': 'no-cache',
                    'pragma': 'no-cache'
                }
            });

            const html = await response.text();
            const doc = new DOMParser().parseFromString(html, 'text/html');
            const htmlLength = html.length;
            const status = response.status;

            if (mode === 'diagnostics') {
                return JSON.stringify(buildDiagnostics(doc, status, htmlLength));
            }

            const parsed = parseRentalDetail(doc);
            return JSON.stringify({
                ok: true,
                mode: 'detail',
                status,
                htmlLength,
                title: doc.title || '',
                parsed
            });
        } catch (e) {
            return JSON.stringify({
                ok: false,
                mode: mode,
                status: 0,
                htmlLength: 0,
                error: String(e),
                title: ''
            });
        }
        """

    private func runFetch() {
        guard let wv = webView, !isRunningFetch else { return }
        guard fetchAttempt < 3 else { return }

        let pageURL = wv.url?.absoluteString ?? ""
        if Self.isSignInURL(pageURL) {
            fail(WheelSysRentalFetchError.sessionExpired)
            return
        }

        isRunningFetch = true
        fetchAttempt += 1
        print("[Journal] enriching rental detail entityId=\(entityId)")

        wv.callAsyncJavaScript(
            Self.rentalPageJS,
            arguments: ["entityId": entityId, "mode": mode.rawValue],
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
                    self.retryOrFail(parseFailure: error.localizedDescription)
                }
            }
        }
    }

    private func handleJSString(_ raw: String) {
        guard !raw.isEmpty else {
            retryOrFail(parseFailure: "empty JS result")
            return
        }
        continuation?.resume(returning: raw)
        continuation = nil
        cleanup()
    }

    private func retryOrFail(parseFailure message: String) {
        if fetchAttempt < 3 {
            scheduleFetch(after: 1.0)
            return
        }
        fail(WheelSysRentalFetchError.parseFailure(message))
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

extension WheelSysRentalWebViewFetcher: WKNavigationDelegate {
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        let url = webView.url?.absoluteString ?? ""
        if Self.isSignInURL(url) {
            fail(WheelSysRentalFetchError.sessionExpired)
            return
        }
        guard url.lowercased().contains("fleetchart") else { return }
        fetchAttempt = 0
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
