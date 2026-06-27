import Foundation
import UIKit
import WebKit

// MARK: - Models

/// DOM snapshot read from live rental.aspx after JS initialization.
struct WheelSysPrecheckinWebViewSnapshot: Codable {
    let pk: String?
    let target: String?
    let precheckinCommand: String?
    let saveCommand: String?
    let rdDispDocno_text: String?
    let rdDriver_value: String?
    let rdDriver_text: String?
    let rdPlateNo_value: String?
    let rdPlateNo_text: String?
    let rdDateFrom_text: String?
    let rdTimeFrom_text: String?
    let rdDateTo_text: String?
    let rdTimeTo_text: String?
    let rdStationFrom_combo: String?
    let rdStationTo_combo: String?
    let rdGroup_combo: String?
    let rdGroupInv_combo: String?
    let rdModel_value: String?
    let rdModel_text: String?
    let rdMileageFrom_hidden: String?
    let rdTankFrom_hidden: String?
}

/// Rental page status snapshot before PRECHECKIN.
struct WheelSysPrecheckinRentalStatusSnapshot: Codable {
    let title: String?
    let dbgInitialStatus: String?
    let rdStatus: String?
    let rdUsageType: String?
    let rdDispDocno_text: String?
    let rdRaDocNo_text: String?
    let rdResDocNo_text: String?
    let rdDateTo_text: String?
    let rdTimeTo_text: String?
}

struct WheelSysPrecheckinAfterSavePayload: Codable {
    let success: Bool?
    let message: String?
    let Message: String?

    var resolvedMessage: String? {
        let m = message ?? Message
        guard let m else { return nil }
        let t = m.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }
}

struct WheelSysPrecheckinWebViewJSError: Codable {
    let message: String?
    let filename: String?
    let lineno: Int?
    let colno: Int?
}

/// Result of `wheels.postBack(..., rentalcommands.precheckin, wheels.PK)` inside WKWebView.
struct WheelSysPrecheckinWebViewResult: Codable {
    let success: Bool
    let stage: String?
    let message: String?
    let reason: String?
    let rentalId: Int?
    let httpStatus: Int?
    let responseLength: Int?
    let containsAfterSave: Bool?
    let containsPrecheckin: Bool?
    let afterSaveSuccess: Bool?
    let afterSaveMessage: String?
    let afterSaveSnippet: String?
    let afterSave: WheelSysPrecheckinAfterSavePayload?
    let afterSaveFullJson: String?
    let responsePreview: String?
    let bodyTextSample: String?
    let htmlSample: String?
    let pageTitle: String?
    let pageUrl: String?
    let snapshot: WheelSysPrecheckinWebViewSnapshot?
    let rentalStatus: WheelSysPrecheckinRentalStatusSnapshot?
    let errors: [WheelSysPrecheckinWebViewJSError]?
    let wheelsReady: Bool?
    let error: String?
    let stack: String?
}

// MARK: - Errors

enum WheelSysPrecheckinWebViewError: LocalizedError {
    case sessionExpired
    case pageNotReady(String)
    case missingDisplayDocNo
    case javaScriptError(String)
    case pageLoadFailed(String)
    case submitFailed(String)

    var errorDescription: String? {
        switch self {
        case .sessionExpired:
            return "wheelsys_fleet.session_expired".localized
        case .pageNotReady(let detail):
            return "wheelsys.precheckin.page_not_ready".localized + " \(detail)"
        case .missingDisplayDocNo:
            return "wheelsys.precheckin.missing_disp_docno".localized
        case .javaScriptError(let msg):
            return "wheelsys.precheckin.webview_js_error".localized + " \(msg)"
        case .pageLoadFailed(let msg):
            return "wheelsys.precheckin.webview_load_failed".localized + " \(msg)"
        case .submitFailed(let msg):
            return msg
        }
    }
}

// MARK: - Fetcher

/// Submits WheelSys PRECHECKIN from authenticated WKWebView using the real
/// `wheels.postBack` path — preserves browser-generated ASP.NET WebForms state.
@MainActor
final class WheelSysPrecheckinWebViewFetcher: NSObject {

    private static let baseURL = "https://ch.wheelsys.greenmotion.com"
    private static let cookieDomain = "ch.wheelsys.greenmotion.com"
    private static let userAgent =
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 "
        + "(KHTML, like Gecko) Chrome/125.0.0.0 Safari/537.36"

    let rentalId: Int
    let checkInMileage: Int?
    let checkInFuel: Int?
    let checkInUserId: String?
    let checkInDate: String?
    let checkInTime: String?

    private var webView: WKWebView?
    private var hostWindow: UIWindow?
    private var navContinuation: CheckedContinuation<Void, Error>?

    init(
        rentalId: Int,
        checkInMileage: Int?,
        checkInFuel: Int?,
        checkInUserId: String? = nil,
        checkInDate: String? = nil,
        checkInTime: String? = nil
    ) {
        self.rentalId = rentalId
        self.checkInMileage = checkInMileage
        self.checkInFuel = checkInFuel
        self.checkInUserId = checkInUserId
        self.checkInDate = checkInDate
        self.checkInTime = checkInTime
        super.init()
    }

    /// Load rental.aspx, wait for `wheels` + `rentalcommands`, then call `wheels.postBack`.
    static func submit(
        rentalId: Int,
        checkInMileage: Int? = nil,
        checkInFuel: Int? = nil,
        checkInUserId: String? = nil,
        checkInDate: String? = nil,
        checkInTime: String? = nil
    ) async throws -> WheelSysPrecheckinWebViewResult {
        let fetcher = WheelSysPrecheckinWebViewFetcher(
            rentalId: rentalId,
            checkInMileage: checkInMileage,
            checkInFuel: checkInFuel,
            checkInUserId: checkInUserId,
            checkInDate: checkInDate,
            checkInTime: checkInTime
        )
        defer { fetcher.cleanup() }
        return try await fetcher.run()
    }

    // MARK: - Flow

    private func run() async throws -> WheelSysPrecheckinWebViewResult {
        guard WheelSysCookieCache.isValid else {
            throw WheelSysPrecheckinWebViewError.sessionExpired
        }

        print("[PrecheckinWebView] page loaded rentalId=\(rentalId) km=\(checkInMileage.map(String.init) ?? "nil") fuel=\(checkInFuel.map(String.init) ?? "nil")")

        let url = URL(
            string: "\(Self.baseURL)/ui/manage/master/rental.aspx?entityId=\(rentalId)"
        )!
        let wv = makeWebView()
        webView = wv
        attachToHiddenWindow(wv)

        try await injectCachedCookies(into: wv.configuration.websiteDataStore.httpCookieStore)
        try await loadPage(wv, url: url)

        let js = Self.makePrecheckinSubmitJS(
            rentalId: rentalId,
            checkInMileage: checkInMileage,
            checkInFuel: checkInFuel,
            checkInUserId: checkInUserId,
            checkInDate: checkInDate,
            checkInTime: checkInTime
        )
        return try await executeSubmitJS(js, on: wv)
    }

    private func executeSubmitJS(
        _ js: String,
        on wv: WKWebView
    ) async throws -> WheelSysPrecheckinWebViewResult {
        try await withCheckedThrowingContinuation { cont in
            wv.callAsyncJavaScript(js, arguments: [:], in: nil, in: .page) { result in
                Task { @MainActor in
                    switch result {
                    case .success(let value):
                        do {
                            let parsed = try Self.decodeResult(from: value, rentalId: self.rentalId)
                            Self.logResult(parsed)
                            cont.resume(returning: parsed)
                        } catch {
                            cont.resume(throwing: error)
                        }
                    case .failure(let error):
                        cont.resume(throwing: WheelSysPrecheckinWebViewError.javaScriptError(
                            error.localizedDescription
                        ))
                    }
                }
            }
        }
    }

    private static func logResult(_ result: WheelSysPrecheckinWebViewResult) {
        let snap = result.snapshot
        print("[PrecheckinWebView] wheels ready \(result.wheelsReady == true)")
        print("[PrecheckinWebView] saveCommand \(snap?.saveCommand ?? snap?.precheckinCommand ?? "nil")")
        print("[PrecheckinWebView] target \(snap?.target ?? "nil")")
        print("[PrecheckinWebView] rdDispDocno_text \(snap?.rdDispDocno_text ?? "nil")")
        print("[PrecheckinWebView] rdDriver_value \(snap?.rdDriver_value ?? "nil")")
        print("[PrecheckinWebView] rdPlateNo_value \(snap?.rdPlateNo_value ?? "nil")")
        if let status = result.rentalStatus {
            print("[PrecheckinWebView] pageTitle \(status.title ?? "nil") rdStatus=\(status.rdStatus ?? "nil")")
        }
        if let target = snap?.target,
           let cmd = snap?.saveCommand ?? snap?.precheckinCommand,
           let pk = snap?.pk,
           result.stage == "precheckin_postback" {
            print("[PrecheckinWebView] calling wheels.postBack(\(target), \(cmd), \(pk))")
        }
        if let stage = result.stage {
            print("[PrecheckinWebView] stage=\(stage)")
        }
        if let msg = result.message, !msg.isEmpty, result.success == false {
            print("[PrecheckinWebView] message \(msg)")
        }
        if let full = result.afterSaveFullJson, !full.isEmpty {
            print("[PrecheckinWebView] afterSave full=\(full)")
        } else if let afterSave = result.afterSave,
                  let data = try? JSONEncoder().encode(afterSave),
                  let json = String(data: data, encoding: .utf8) {
            print("[PrecheckinWebView] afterSave full=\(json)")
        }
        if result.afterSaveSuccess == true {
            print("[PrecheckinWebView] afterSave success=true msg=\(result.afterSaveMessage ?? result.message ?? "nil")")
        } else {
            print("[PrecheckinWebView] afterSave success=false msg=\(result.afterSaveMessage ?? result.message ?? "nil")")
        }
        if let reason = result.reason, !reason.isEmpty {
            print("[PrecheckinWebView] reason \(reason)")
        }
    }

    private static func decodeResult(
        from value: Any?,
        rentalId: Int
    ) throws -> WheelSysPrecheckinWebViewResult {
        let jsonStr: String
        if let s = value as? String {
            jsonStr = s
        } else if let dict = value as? [String: Any],
                  let data = try? JSONSerialization.data(withJSONObject: dict),
                  let s = String(data: data, encoding: .utf8) {
            jsonStr = s
        } else {
            throw WheelSysPrecheckinWebViewError.javaScriptError(
                "Submit JS returned \(type(of: value)) instead of String"
            )
        }

        guard !jsonStr.isEmpty,
              let data = jsonStr.data(using: .utf8)
        else {
            throw WheelSysPrecheckinWebViewError.javaScriptError("Submit JS returned empty result")
        }

        let decoder = JSONDecoder()
        var result = try decoder.decode(WheelSysPrecheckinWebViewResult.self, from: data)
        if result.rentalId == nil {
            result = WheelSysPrecheckinWebViewResult(
                success: result.success,
                stage: result.stage,
                message: result.message,
                reason: result.reason,
                rentalId: rentalId,
                httpStatus: result.httpStatus,
                responseLength: result.responseLength,
                containsAfterSave: result.containsAfterSave,
                containsPrecheckin: result.containsPrecheckin,
                afterSaveSuccess: result.afterSaveSuccess,
                afterSaveMessage: result.afterSaveMessage,
                afterSaveSnippet: result.afterSaveSnippet,
                afterSave: result.afterSave,
                afterSaveFullJson: result.afterSaveFullJson,
                responsePreview: result.responsePreview,
                bodyTextSample: result.bodyTextSample,
                htmlSample: result.htmlSample,
                pageTitle: result.pageTitle,
                pageUrl: result.pageUrl,
                snapshot: result.snapshot,
                rentalStatus: result.rentalStatus,
                errors: result.errors,
                wheelsReady: result.wheelsReady,
                error: result.error,
                stack: result.stack
            )
        }

        if result.stage == "session" {
            throw WheelSysPrecheckinWebViewError.sessionExpired
        }
        if result.stage == "not_ready" {
            throw WheelSysPrecheckinWebViewError.pageNotReady(result.error ?? "timeout")
        }
        if result.stage == "missing_disp_docno" {
            throw WheelSysPrecheckinWebViewError.missingDisplayDocNo
        }
        if result.stage == "exception" {
            throw WheelSysPrecheckinWebViewError.javaScriptError(result.error ?? "unknown")
        }

        return result
    }

    func cleanup() {
        navContinuation?.resume(throwing: WheelSysPrecheckinWebViewError.pageLoadFailed("cleanup"))
        navContinuation = nil
        webView?.navigationDelegate = nil
        webView = nil
        hostWindow?.isHidden = true
        hostWindow = nil
    }

    // MARK: - WebView setup

    private func makeWebView() -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        config.defaultWebpagePreferences.allowsContentJavaScript = true
        let wv = WKWebView(frame: CGRect(x: 0, y: 0, width: 375, height: 812), configuration: config)
        wv.customUserAgent = Self.userAgent
        wv.navigationDelegate = self
        return wv
    }

    private func attachToHiddenWindow(_ webView: WKWebView) {
        guard let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: {
                $0.activationState == .foregroundActive || $0.activationState == .foregroundInactive
            }) ?? UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene }).first
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

    private func injectCachedCookies(into store: WKHTTPCookieStore) async throws {
        guard let header = WheelSysCookieCache.lastCookie else { return }

        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
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
                cont.resume()
                return
            }

            let group = DispatchGroup()
            for cookie in cookies {
                group.enter()
                store.setCookie(cookie) { group.leave() }
            }
            group.notify(queue: .main) { cont.resume() }
        }
    }

    private func loadPage(_ wv: WKWebView, url: URL) async throws {
        let request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 45)
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            navContinuation = cont
            wv.load(request)
        }
    }

    // MARK: - JavaScript

    private static func makePrecheckinSubmitJS(
        rentalId: Int,
        checkInMileage: Int?,
        checkInFuel: Int?,
        checkInUserId: String?,
        checkInDate: String?,
        checkInTime: String?
    ) -> String {
        let kmLiteral = checkInMileage.map(String.init) ?? "null"
        let fuelLiteral = checkInFuel.map(String.init) ?? "null"
        let userLiteral = checkInUserId.map { "\"\( $0.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") )\"" } ?? "null"
        let dateLiteral = checkInDate.map { "\"\( $0.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") )\"" } ?? "null"
        let timeLiteral = checkInTime.map { "\"\( $0.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") )\"" } ?? "null"

        return """
try {
  const rentalId = \(rentalId);
  const checkInMileage = \(kmLiteral);
  const checkInFuel = \(fuelLiteral);
  const checkInUserId = \(userLiteral);
  const checkInDate = \(dateLiteral);
  const checkInTime = \(timeLiteral);

  function sleep(ms) {
    return new Promise(function(resolve) { setTimeout(resolve, ms); });
  }

  function fieldValue(id) {
    var el = document.getElementById(id);
    if (!el) return null;
    var v = el.value;
    if (v != null && String(v).trim() !== "") return String(v).trim();
    var pre = el.getAttribute("data-prevalue");
    if (pre && String(pre).trim()) return String(pre).trim();
    return null;
  }

  function setInput(id, value) {
    var el = document.getElementById(id);
    if (!el || value == null) return;
    setNativeValue(el, value);
  }

  function setComboValue(id, value) {
    if (value == null) return;
    var el = document.getElementById(id);
    if (!el) return;
    var v = String(value);
    if (window.jQuery) {
      var $el = window.jQuery(el);
      $el.val(v).trigger("change");
    } else {
      el.value = v;
      el.dispatchEvent(new Event("change", { bubbles: true }));
    }
  }

  function setNumericPair(textId, hiddenId, numValue, displaySuffix) {
    var textEl = document.getElementById(textId);
    var hiddenEl = document.getElementById(hiddenId);
    if (!textEl || !hiddenEl) return;
    var n = Number(numValue);
    if (isNaN(n)) return;
    hiddenEl.value = String(n);
    hiddenEl.setAttribute("data-prevalue", String(n));
    textEl.value = displaySuffix ? (n + displaySuffix) : String(n);
    if (window.jQuery) {
      window.jQuery(textEl).val(textEl.value).trigger("input").trigger("change").trigger("blur");
    }
    textEl.dispatchEvent(new Event("input", { bubbles: true }));
    textEl.dispatchEvent(new Event("change", { bubbles: true }));
    textEl.dispatchEvent(new Event("blur", { bubbles: true }));
    hiddenEl.dispatchEvent(new Event("change", { bubbles: true }));
  }

  function formatMileageText(n) {
    var num = Number(n);
    if (isNaN(num)) return "";
    try {
      return num.toLocaleString("de-CH").replace(/'/g, ".") + " km";
    } catch (e) {
      return String(num) + " km";
    }
  }

  function formatTankText(f) {
    return String(Number(f)) + "/8";
  }

  function setNativeValue(el, value) {
    if (!el) return;
    var str = String(value);
    try {
      var valueSetter = Object.getOwnPropertyDescriptor(el, "value");
      valueSetter = valueSetter && valueSetter.set;
      var prototype = Object.getPrototypeOf(el);
      var prototypeValueSetter = Object.getOwnPropertyDescriptor(prototype, "value");
      prototypeValueSetter = prototypeValueSetter && prototypeValueSetter.set;
      if (prototypeValueSetter && valueSetter !== prototypeValueSetter) {
        prototypeValueSetter.call(el, str);
      } else if (valueSetter) {
        valueSetter.call(el, str);
      } else {
        el.value = str;
      }
    } catch (e) {
      el.value = str;
    }
    el.dispatchEvent(new Event("input", { bubbles: true }));
    el.dispatchEvent(new Event("change", { bubbles: true }));
    el.dispatchEvent(new Event("blur", { bubbles: true }));
  }

  function setById(id, value) {
    var el = document.getElementById(id);
    if (!el) {
      console.log("[PrecheckinWebView] set missing " + id);
      return false;
    }
    setNativeValue(el, value);
    console.log("[PrecheckinWebView] set " + id + "=" + value);
    return true;
  }

  function scanPrecheckinDomFields() {
    var rows = Array.from(document.querySelectorAll("input, select, textarea")).map(function(el) {
      return {
        id: el.id || "",
        name: el.name || "",
        value: el.value || "",
        type: el.type || "",
        tag: el.tagName
      };
    }).filter(function(x) {
      var s = (x.id + " " + x.name).toLowerCase();
      return s.indexOf("mile") >= 0 || s.indexOf("kilom") >= 0 || s.indexOf("km") >= 0
        || s.indexOf("tank") >= 0 || s.indexOf("fuel") >= 0 || s.indexOf("user") >= 0
        || s.indexOf("stationto") >= 0 || s.indexOf("dateto") >= 0 || s.indexOf("timeto") >= 0;
    });
    console.log("[PrecheckinWebView] dom fields", JSON.stringify(rows));
    return rows;
  }

  function parseMileageNumber(raw) {
    if (raw == null) return null;
    var s = String(raw).trim();
    if (!s) return null;
    var digits = s.replace(/[^0-9]/g, "");
    if (!digits) return null;
    var n = Number(digits);
    return isNaN(n) ? null : n;
  }

  function resolvedMileageFieldIds() {
    return {
      toText: findFieldId([
        "rdMileageTo_text", "rdKilomTo_text", "rdKMTo_text",
        "rdMileageEnd_text", "rdOdometerTo_text"
      ]),
      toHidden: findFieldId([
        "rdMileageTo_hidden", "rdKilomTo_hidden", "rdKMTo_hidden",
        "rdMileageEnd_hidden", "rdOdometerTo_hidden"
      ]),
      drivenText: findFieldId([
        "rdMilesDriven_text", "rdKilomDriven_text", "rdKMDriven_text"
      ]),
      drivenHidden: findFieldId([
        "rdMilesDriven_hidden", "rdKilomDriven_hidden", "rdKMDriven_hidden"
      ]),
      tankText: findFieldId(["rdTankTo_text", "rdFuelTo_text"]),
      tankHidden: findFieldId(["rdTankTo_hidden", "rdFuelTo_hidden"])
    };
  }

  function readNumericField(textId, hiddenId, ignoreZero) {
    var hiddenRaw = fieldValue(hiddenId);
    var hiddenNum = hiddenRaw != null && String(hiddenRaw).trim() !== "" ? Number(hiddenRaw) : null;
    if (hiddenNum != null && !isNaN(hiddenNum)) {
      if (!(ignoreZero && hiddenNum === 0)) return hiddenNum;
    }
    if (window.wheels && typeof window.wheels.getNumericTextBoxValue === "function") {
      try {
        var wv = window.wheels.getNumericTextBoxValue(textId);
        if (wv != null && String(wv).trim() !== "") {
          var n = Number(wv);
          if (!isNaN(n) && !(ignoreZero && n === 0)) return n;
        }
      } catch (e) {}
    }
    var textRaw = fieldValue(textId);
    var parsedText = parseMileageNumber(textRaw);
    if (parsedText != null && !(ignoreZero && parsedText === 0)) return parsedText;
    return null;
  }

  function isUnsetMileage(value, mileageFrom) {
    if (value == null || isNaN(value)) return true;
    if (value <= 0) return true;
    if (mileageFrom > 0 && value <= mileageFrom) return true;
    return false;
  }

  function resolveEffectiveMileage(kmParam, mileageFrom) {
    var ids = resolvedMileageFieldIds();
    var dom = readNumericField(ids.toText, ids.toHidden, true);
    var kp = kmParam != null && !isNaN(Number(kmParam)) ? Number(kmParam) : null;
    if (!isUnsetMileage(dom, mileageFrom)) return dom;
    if (kp != null && kp > mileageFrom) return kp;
    return dom;
  }

  function resolveEffectiveFuel(fuelParam) {
    var ids = resolvedMileageFieldIds();
    var dom = readNumericField(ids.tankText, ids.tankHidden, false);
    if (dom != null && !isNaN(dom) && dom >= 0) return dom;
    if (fuelParam != null && !isNaN(Number(fuelParam))) return Number(fuelParam);
    return dom;
  }

  function setWheelsCombo(comboId, value) {
    if (value == null || String(value).trim() === "") return false;
    var v = String(value).trim();
    var el = document.getElementById(comboId);
    if (!el) {
      console.log("[PrecheckinWebView] set missing " + comboId);
      return false;
    }
    var applied = false;
    if (el.tagName === "SELECT") {
      for (var i = 0; i < el.options.length; i++) {
        if (String(el.options[i].value) === v) {
          el.selectedIndex = i;
          applied = true;
          break;
        }
      }
      if (!applied) {
        el.value = v;
        applied = true;
      }
    } else {
      el.value = v;
      applied = true;
    }
    if (window.jQuery) {
      var $el = window.jQuery("#" + comboId);
      $el.val(v);
      try {
        if (typeof $el.wheelscombobox === "function") {
          $el.wheelscombobox("setValue", v);
        }
      } catch (e1) {}
      $el.trigger("change");
      $el.trigger("blur");
    }
    el.dispatchEvent(new Event("change", { bubbles: true }));
    console.log("[PrecheckinWebView] set " + comboId + "=" + v + " readback=" + (fieldValue(comboId) || ""));
    return fieldValue(comboId) === v;
  }

  function setWheelsNumeric(textId, hiddenId, numValue, displayText) {
    var n = Number(numValue);
    if (isNaN(n)) return false;
    var textEl = document.getElementById(textId);
    var hiddenEl = hiddenId ? document.getElementById(hiddenId) : null;
    var textVal = displayText != null ? String(displayText) : String(n);
    var ok = false;
    if (window.wheels && typeof window.wheels.getNumericTextBox === "function") {
      try {
        var box = window.wheels.getNumericTextBox(textId);
        if (box && typeof box.set === "function") {
          box.set(n);
          ok = true;
        }
      } catch (e) {}
    }
    if (hiddenEl) {
      setNativeValue(hiddenEl, String(n));
      hiddenEl.setAttribute("data-prevalue", String(n));
    }
    if (textEl) setNativeValue(textEl, textVal);
    if (window.jQuery && textEl) {
      window.jQuery(textEl).val(textVal).trigger("input").trigger("change").trigger("blur");
    }
    if (window.wheels && typeof window.wheels.getNumericTextBox === "function") {
      try {
        var box2 = window.wheels.getNumericTextBox(textId);
        if (box2 && typeof box2.set === "function") {
          box2.set(n);
          ok = true;
        }
      } catch (e2) {}
    }
    var hiddenOk = hiddenEl && Number(fieldValue(hiddenId) || 0) === n;
    var widgetOk = false;
    if (window.wheels && typeof window.wheels.getNumericTextBoxValue === "function") {
      try {
        widgetOk = Number(window.wheels.getNumericTextBoxValue(textId)) === n;
      } catch (e3) {}
    }
    return ok || hiddenOk || widgetOk;
  }

  function triggerChangeHandler(name) {
    try {
      if (typeof window[name] === "function") window[name]();
    } catch (e) {}
  }

  function revealCheckinPanel() {
    var panel = document.getElementById("checkincar");
    if (panel) {
      panel.style.display = "block";
      panel.style.visibility = "visible";
    }
    var fields = document.getElementById("checkincarfields");
    if (fields) fields.disabled = false;
  }

  function buildPrecheckinPostPatch(km, fuel, userOverride, dateOverride, timeOverride) {
    var patch = {};
    var kmFrom = Number(fieldValue("rdMileageFrom_hidden") || 0);
    if (km != null && !isNaN(km)) {
      var kmNum = Number(km);
      if (kmNum > kmFrom) {
        var driven = kmNum - kmFrom;
        patch.rdMileageTo_hidden = String(kmNum);
        patch.rdMileageTo_text = formatMileageText(kmNum);
        patch.rdMilesDriven_hidden = String(driven);
        patch.rdMilesDriven_text = formatMileageText(driven);
      }
    }
    if (fuel != null && !isNaN(fuel)) {
      var f = Number(fuel);
      if (f >= 0 && f <= 8) {
        patch.rdTankTo_hidden = String(f);
        patch.rdTankTo_text = formatTankText(f);
      }
    }
    var userId = resolveCheckInUserId(userOverride);
    if (userId) patch.rdUserTo_combo = userId;
    var dateTo = dateOverride || fieldValue("rdDateTo_text");
    var timeTo = timeOverride || fieldValue("rdTimeTo_text");
    var now = zurichNowParts();
    if (!dateTo && now) dateTo = now.date;
    if (!timeTo && now) timeTo = now.time;
    if (dateTo) patch.rdDateTo_text = dateTo;
    if (timeTo) patch.rdTimeTo_text = timeTo;
    var stationTo = fieldValue("rdStationTo_combo") || fieldValue("rdStationFrom_combo") || "ZRH";
    if (stationTo) patch.rdStationTo_combo = stationTo;
    return patch;
  }

  function mergeCheckinFieldsIntoBody(bodyStr, patch) {
    if (!bodyStr || typeof bodyStr !== "string" || !patch) return bodyStr;
    try {
      var params = new URLSearchParams(bodyStr);
      Object.keys(patch).forEach(function(key) {
        var val = patch[key];
        if (val != null && String(val).trim() !== "") params.set(key, String(val));
      });
      return params.toString();
    } catch (e) {
      return bodyStr;
    }
  }

  function isPrecheckinPostBody(bodyStr) {
    if (!bodyStr) return false;
    var s = String(bodyStr);
    return /BTSAVE/i.test(s) || /"action"\\s*:\\s*"BTSAVE"/i.test(s);
  }

  function resolvePrecheckinCommand(snapshot) {
    if (snapshot && snapshot.precheckinCommand) return snapshot.precheckinCommand;
    if (window.rentalcommands && window.rentalcommands.precheckin != null) {
      return window.rentalcommands.precheckin;
    }
    return null;
  }

  // HAR flow: CalcRates (PRECHECKIN→FuelPolicy→KMDriven) then wheels.postBack(..., BTSAVE, ...).
  function resolvePrecheckinSaveCommand(snapshot) {
    if (snapshot && snapshot.saveCommand) return snapshot.saveCommand;
    return resolveSaveCommand();
  }

  function resolveSaveCommand() {
    if (window.wheels && window.wheels.COMMAND_SAVE != null) {
      return window.wheels.COMMAND_SAVE;
    }
    return "BTSAVE";
  }

  function resolveCheckInUserId(userOverride) {
    if (userOverride != null && String(userOverride).trim() !== "") {
      return String(userOverride).trim();
    }
    if (checkInUserId != null && String(checkInUserId).trim() !== "") {
      return String(checkInUserId).trim();
    }
    if (window.wheels && window.wheels.userID != null) {
      return String(window.wheels.userID);
    }
    var sel = document.getElementById("rdUserTo_combo") || document.querySelector('[name="rdUserTo_combo"]');
    if (!sel) return null;
    if (sel.value) return String(sel.value).trim();
    for (var i = 0; i < sel.options.length; i++) {
      if (sel.options[i].value) return String(sel.options[i].value).trim();
    }
    return null;
  }

  function findFieldId(candidates) {
    for (var i = 0; i < candidates.length; i++) {
      if (document.getElementById(candidates[i])) return candidates[i];
    }
    return candidates[0];
  }

  function applyReturnKm(kmNum, ids) {
    if (ids == null) ids = resolvedMileageFieldIds();
    var kmText = formatMileageText(kmNum);
    setWheelsNumeric(ids.toText, ids.toHidden, kmNum, kmText);
    setById(ids.toHidden, kmNum);
    setById(ids.toText, kmText);
    triggerChangeHandler("handleMilesToChanged");
    return { kmTo: kmNum };
  }

  function syncMilesDrivenField(kmNum, ids) {
    if (ids == null) ids = resolvedMileageFieldIds();
    var kmFrom = Number(fieldValue("rdMileageFrom_hidden") || 0);
    var driven = Math.max(0, kmNum - kmFrom);
    var drivenText = formatMileageText(driven);
    var hiddenEl = document.getElementById(ids.drivenHidden);
    if (hiddenEl) {
      setNativeValue(hiddenEl, String(driven));
      hiddenEl.setAttribute("data-prevalue", String(driven));
    }
    var textEl = document.getElementById(ids.drivenText);
    if (textEl) setNativeValue(textEl, drivenText);
    console.log("[PrecheckinWebView] mileage apply from=" + kmFrom + " to=" + kmNum + " driven=" + driven);
    return { kmFrom: kmFrom, kmTo: kmNum, milesDriven: driven };
  }

  async function applyReturnKmAndDriven(kmNum, ids) {
    applyReturnKm(kmNum, ids);
    await sleep(150);
    return syncMilesDrivenField(kmNum, ids);
  }

  function evaluateDomReadback(snap, targetKm, targetFuel) {
    var mileageFrom = Number(snap.rdMileageFrom_hidden || fieldValue("rdMileageFrom_hidden") || 0);
    var domKm = Number(snap.rdMileageTo_hidden || 0);
    if (!(domKm > mileageFrom) && snap.widgetMileageTo != null) {
      domKm = Number(snap.widgetMileageTo);
    }
    if (!(domKm > mileageFrom)) {
      domKm = parseMileageNumber(snap.rdMileageTo_text) || 0;
    }
    var domFuel = snap.rdTankTo_hidden != null ? Number(snap.rdTankTo_hidden) : -1;
    if (domFuel < 0 && snap.widgetFuelTo != null) domFuel = Number(snap.widgetFuelTo);
    var domDriven = Number(snap.rdMilesDriven_hidden || 0);
    if (domDriven <= 0 && snap.widgetMilesDriven != null) domDriven = Number(snap.widgetMilesDriven);
    if (domDriven <= 0) domDriven = parseMileageNumber(snap.rdMilesDriven_text) || 0;
    var expectedDriven = targetKm != null ? Math.max(0, targetKm - mileageFrom) : null;
    var issues = [];
    var kmOk = targetKm == null || (domKm > mileageFrom && domKm === targetKm);
    if (!kmOk) {
      issues.push("mileageTo need " + targetKm + " got hidden=" + (snap.rdMileageTo_hidden || "0")
        + " checkout=" + mileageFrom);
    }
    var fuelOk = targetFuel == null || domFuel === targetFuel;
    if (!fuelOk) issues.push("fuelTo need " + targetFuel + " got " + domFuel);
    if (targetKm != null && expectedDriven != null && domDriven !== expectedDriven) {
      console.log("[PrecheckinWebView] driven mismatch (non-blocking) need=" + expectedDriven + " got=" + domDriven);
    }
    if (!snap.rdUserTo_combo) issues.push("rdUserTo_combo missing");
    if (!snap.rdStationTo_combo) issues.push("rdStationTo_combo missing");
    if (!snap.rdDateTo_text) issues.push("rdDateTo_text missing");
    if (!snap.rdTimeTo_text) issues.push("rdTimeTo_text missing");
    return {
      ok: issues.length === 0,
      issues: issues,
      mileageFrom: mileageFrom,
      domKm: domKm,
      domFuel: domFuel,
      domDriven: domDriven,
      expectedDriven: expectedDriven
    };
  }

  function populateAllPrecheckinFields(km, fuel, userOverride, dateOverride, timeOverride) {
    revealCheckinPanel();
    var applied = { sets: [] };
    var ids = resolvedMileageFieldIds();

    if (km != null && !isNaN(km)) {
      applyReturnKm(Number(km), ids);
      applied.kmTo = Number(km);
      applied.sets.push(ids.toHidden + "=" + km);
    }

    if (fuel != null && !isNaN(fuel)) {
      var f = Number(fuel);
      if (f >= 0 && f <= 8) {
        var tankText = formatTankText(f);
        setWheelsNumeric(ids.tankText, ids.tankHidden, f, tankText);
        setById(ids.tankHidden, f);
        setById(ids.tankText, tankText);
        triggerChangeHandler("handleFuelToChanged");
        applied.sets.push(ids.tankHidden + "=" + f);
        applied.fuelTo = f;
      }
    }

    var userId = resolveCheckInUserId(userOverride);
    if (userId) {
      setWheelsCombo("rdUserTo_combo", userId);
      applied.sets.push("rdUserTo_combo=" + userId);
      applied.userTo = userId;
    }

    var dateTo = dateOverride || fieldValue("rdDateTo_text");
    var timeTo = timeOverride || fieldValue("rdTimeTo_text");
    var now = zurichNowParts();
    if (!dateTo && now) dateTo = now.date;
    if (!timeTo && now) timeTo = now.time;
    if (dateTo) {
      setInput("rdDateTo_text", dateTo);
      applied.sets.push("rdDateTo_text=" + dateTo);
    }
    if (timeTo) {
      setInput("rdTimeTo_text", timeTo);
      applied.sets.push("rdTimeTo_text=" + timeTo);
    }

    var stationTo = fieldValue("rdStationTo_combo") || fieldValue("rdStationFrom_combo") || "ZRH";
    setWheelsCombo("rdStationTo_combo", stationTo);
    applied.sets.push("rdStationTo_combo=" + stationTo);

    applied.readback = readRequiredCheckinFields();
    console.log("[PrecheckinWebView] populate applied", JSON.stringify(applied.sets));
    return applied;
  }

  function readRequiredCheckinFields() {
    var ids = resolvedMileageFieldIds();
    return {
      rdMileageFrom_hidden: fieldValue("rdMileageFrom_hidden"),
      rdMileageTo_hidden: fieldValue(ids.toHidden),
      rdMileageTo_text: fieldValue(ids.toText),
      rdTankTo_hidden: fieldValue(ids.tankHidden),
      rdTankTo_text: fieldValue(ids.tankText),
      rdMilesDriven_hidden: fieldValue(ids.drivenHidden),
      rdMilesDriven_text: fieldValue(ids.drivenText),
      rdUserTo_combo: fieldValue("rdUserTo_combo"),
      rdStationTo_combo: fieldValue("rdStationTo_combo"),
      rdDateTo_text: fieldValue("rdDateTo_text"),
      rdTimeTo_text: fieldValue("rdTimeTo_text"),
      widgetMileageTo: readNumericField(ids.toText, ids.toHidden, true),
      widgetFuelTo: readNumericField(ids.tankText, ids.tankHidden, false),
      widgetMilesDriven: readNumericField(ids.drivenText, ids.drivenHidden, true)
    };
  }

  function verifyRequiredCheckinFields(kmParam, fuelParam) {
    var ids = resolvedMileageFieldIds();
    var mileageFrom = Number(fieldValue("rdMileageFrom_hidden") || 0);
    var mileageTo = resolveEffectiveMileage(kmParam, mileageFrom);
    var fuelTo = resolveEffectiveFuel(fuelParam);
    var milesDriven = readNumericField(ids.drivenText, ids.drivenHidden, true);
    if ((milesDriven == null || milesDriven < 0) && mileageTo != null && mileageTo > mileageFrom) {
      milesDriven = mileageTo - mileageFrom;
    }
    var userId = fieldValue("rdUserTo_combo") || resolveCheckInUserId(null);
    if (!fieldValue("rdUserTo_combo") && userId) {
      setWheelsCombo("rdUserTo_combo", userId);
      userId = fieldValue("rdUserTo_combo") || userId;
    }
    var stationTo = fieldValue("rdStationTo_combo");
    var dateTo = fieldValue("rdDateTo_text");
    var timeTo = fieldValue("rdTimeTo_text");
    var missing = [];
    if (!userId) missing.push("rdUserTo_combo");
    if (mileageTo == null || mileageTo <= mileageFrom) missing.push("rdMileageTo_hidden");
    if (fuelTo == null || isNaN(fuelTo) || fuelTo < 0) missing.push("rdTankTo_hidden");
    if (!stationTo) missing.push("rdStationTo_combo");
    if (!dateTo) missing.push("rdDateTo_text");
    if (!timeTo) missing.push("rdTimeTo_text");
    var required = readRequiredCheckinFields();
    console.log("[PrecheckinWebView] required check", JSON.stringify(required));
    console.log("[PrecheckinWebView] required missing", JSON.stringify(missing));
    return {
      ok: missing.length === 0,
      missing: missing,
      required: required,
      mileageFrom: mileageFrom,
      mileageTo: mileageTo,
      fuelTo: fuelTo,
      milesDriven: milesDriven,
      userId: userId
    };
  }

  async function ensureDomReadbackMatches(km, fuel, userOverride, dateOverride, timeOverride) {
    scanPrecheckinDomFields();
    var targetKm = km != null ? Number(km) : null;
    var targetFuel = fuel != null ? Number(fuel) : null;
    var ids = resolvedMileageFieldIds();
    var lastEval = null;
    for (var attempt = 0; attempt < 4; attempt++) {
      populateAllPrecheckinFields(km, fuel, userOverride, dateOverride, timeOverride);
      await sleep(attempt === 0 ? 100 : 140);
      if (targetKm != null) {
        await applyReturnKmAndDriven(targetKm, ids);
      }
      var snap = readRequiredCheckinFields();
      lastEval = evaluateDomReadback(snap, targetKm, targetFuel);
      console.log("[PrecheckinWebView] before submit snapshot", JSON.stringify(snap));
      console.log("[PrecheckinWebView] before submit eval", JSON.stringify(lastEval));
      if (lastEval.ok) {
        return { ok: true, snapshot: snap, attempt: attempt + 1, eval: lastEval };
      }
    }
    return { ok: false, snapshot: readRequiredCheckinFields(), attempt: 4, eval: lastEval };
  }

  function validatePrecheckinFields(kmParam, fuelParam) {
    var v = verifyRequiredCheckinFields(kmParam, fuelParam);
    var msgs = [];
    if (v.missing.indexOf("rdUserTo_combo") >= 0) {
      msgs.push("Check-in user (rdUserTo) is required.");
    }
    if (v.missing.indexOf("rdMileageTo_hidden") >= 0) {
      msgs.push("Return mileage must be greater than checkout mileage (" + v.mileageFrom + " km).");
    }
    if (v.missing.indexOf("rdTankTo_hidden") >= 0) {
      msgs.push("Return fuel level is required.");
    }
    if (v.missing.indexOf("rdMilesDriven_hidden") >= 0) {
      msgs.push("Miles driven is required.");
    }
    if (v.missing.indexOf("rdStationTo_combo") >= 0) {
      msgs.push("Return station is required.");
    }
    if (v.missing.indexOf("rdDateTo_text") >= 0 || v.missing.indexOf("rdTimeTo_text") >= 0) {
      msgs.push("Return date/time is required.");
    }
    return {
      ok: v.ok,
      messages: msgs,
      missing: v.missing,
      mileageTo: v.mileageTo,
      mileageFrom: v.mileageFrom,
      required: v.required
    };
  }

  function zurichNowParts() {
    try {
      var fmt = new Intl.DateTimeFormat("en-GB", {
        timeZone: "Europe/Zurich",
        day: "2-digit", month: "2-digit", year: "numeric",
        hour: "2-digit", minute: "2-digit", hour12: false
      });
      var parts = fmt.formatToParts(new Date());
      var bag = {};
      parts.forEach(function(p) { if (p.type !== "literal") bag[p.type] = p.value; });
      return {
        date: (bag.day || "") + "/" + (bag.month || "") + "/" + (bag.year || ""),
        time: (bag.hour || "00") + ":" + (bag.minute || "00")
      };
    } catch (e) {
      return null;
    }
  }

  function readCacheKey() {
    var el = document.querySelector('[name="cachekey"], #cachekey');
    if (el && el.value) return String(el.value).trim();
    var html = document.documentElement ? document.documentElement.innerHTML : "";
    var m = html.match(/cachekey["'\\s:=]+["']([^"']{8,})["']/i);
    return m ? m[1] : null;
  }

  function combineDateTimeLocal(dateStr, timeStr) {
    var d = String(dateStr || "").trim();
    if (!d) return "";
    var t = String(timeStr || "00:00").trim();
    var dm = d.match(/^(\\d{2})\\/(\\d{2})\\/(\\d{4})$/);
    if (!dm) return d;
    var tm = t.match(/^(\\d{1,2}):(\\d{2})$/);
    var hh = tm ? tm[1] : "00";
    if (hh.length < 2) hh = "0" + hh;
    var mm = tm ? tm[2] : "00";
    return dm[3] + "-" + dm[2] + "-" + dm[1] + "T" + hh + ":" + mm + ":00";
  }

  function buildCalcRatesPayloadFromForm(km, fuel) {
    return {
      UsageType: fieldValue("rdUsageType") || "1",
      Status: fieldValue("rdStatus") || "1",
      Agent: fieldValue("rdAgent_value") || "",
      Driver: fieldValue("rdDriver_value") || "",
      StationFrom: fieldValue("rdStationFrom_combo") || "ZRH",
      StationTo: fieldValue("rdStationTo_combo") || "ZRH",
      DateFrom: combineDateTimeLocal(fieldValue("rdDateFrom_text"), fieldValue("rdTimeFrom_text")),
      DateTo: combineDateTimeLocal(fieldValue("rdDateTo_text"), fieldValue("rdTimeTo_text")),
      CarId: fieldValue("rdPlateNo_value") || "",
      CarGroup: fieldValue("rdGroup_combo") || "",
      GroupInv: fieldValue("rdGroupInv_combo") || fieldValue("rdGroup_combo") || "",
      RateCode: fieldValue("rdRateCode_combo") || "GMI",
      ResModeId: "6",
      ExtraDay: true,
      KilomTo: km != null ? Number(km) : 0,
      FuelTo: fuel != null ? Number(fuel) : 0,
      RentalType: "R",
      DelCharge: 0,
      ColCharge: 0,
      Excess: 0,
      MilesDriven: (function() {
        var from = Number(fieldValue("rdMileageFrom_hidden") || 0);
        var to = km != null ? Number(km) : (readNumericField("rdMileageTo_text", "rdMileageTo_hidden") || 0);
        return Math.max(0, to - from);
      })(),
      AllowedMiles: 0,
      MileRate: 0,
      TotalCharge: Number(fieldValue("rdChargeTotal_hidden") || 0) || 0
    };
  }

  async function runCalcRatesOperation(operation, km, fuel) {
    var cacheKey = readCacheKey();
    var dataPayload = buildCalcRatesPayloadFromForm(km, fuel);
    if (operation === "PRECHECKIN") {
      dataPayload.KilomTo = 0;
      dataPayload.FuelTo = 0;
      dataPayload.MilesDriven = 0;
    } else if (operation === "FuelPolicy") {
      dataPayload.KilomTo = 0;
      if (fuel != null) dataPayload.FuelTo = Number(fuel);
    }
    var requestBody = {
      cacheKey: cacheKey,
      operation: operation,
      data: JSON.stringify(dataPayload)
    };
    if (!cacheKey) {
      return {
        ok: false,
        skipped: false,
        reason: "missing cacheKey",
        message: "missing cacheKey",
        cacheKey: null,
        operation: operation,
        request: requestBody,
        httpStatus: null,
        rawResponse: null,
        parsed: null
      };
    }
    try {
      console.log("[PrecheckinWebView] CalcRates " + operation + " request", JSON.stringify(requestBody));
      var res = await fetch("/ui/manage/master/rental.aspx/CalcRates", {
        method: "POST",
        headers: {
          "Content-Type": "application/json; charset=UTF-8",
          "X-Requested-With": "XMLHttpRequest"
        },
        body: JSON.stringify(requestBody)
      });
      var rawText = await res.text();
      console.log("[PrecheckinWebView] CalcRates " + operation + " HTTP", res.status, rawText.slice(0, 1200));
      var outer = null;
      try { outer = JSON.parse(rawText); } catch (pe) { outer = null; }
      var innerRaw = outer && outer.d ? outer.d : outer;
      var calc = null;
      try {
        calc = typeof innerRaw === "string" ? JSON.parse(innerRaw) : innerRaw;
      } catch (pe2) { calc = null; }
      var msg = calc && (calc.Message || calc.message) || null;
      var extra = calc && (calc.ExtraData || calc.extraData) || null;
      var ok = !!(calc && calc.Success);
      return {
        ok: ok,
        skipped: false,
        reason: ok ? null : (msg || ("CalcRates " + operation + " failed")),
        message: msg || (ok ? null : ("CalcRates " + operation + " failed")),
        cacheKey: cacheKey,
        operation: operation,
        request: requestBody,
        httpStatus: res.status,
        rawResponse: rawText.slice(0, 4000),
        parsed: calc,
        extraData: extra,
        success: calc && calc.Success,
        eligibleForPrecheckin: ok
      };
    } catch (e) {
      return {
        ok: false,
        skipped: false,
        reason: String(e),
        message: String(e),
        cacheKey: cacheKey,
        operation: operation,
        request: requestBody,
        httpStatus: null,
        rawResponse: null,
        parsed: null
      };
    }
  }

  async function runPrecheckinCalcRatesSequence(km, fuel) {
    var steps = [];
    var r1 = await runCalcRatesOperation("PRECHECKIN", 0, 0);
    steps.push(r1);
    if (!r1.ok) {
      return {
        ok: false,
        steps: steps,
        operation: "precheckin_sequence",
        reason: r1.reason,
        message: r1.message,
        cacheKey: r1.cacheKey,
        httpStatus: r1.httpStatus,
        rawResponse: r1.rawResponse,
        parsed: r1.parsed
      };
    }
    if (km != null) {
      var r2 = await runCalcRatesOperation("FuelPolicy", km, fuel);
      steps.push(r2);
      if (!r2.ok) {
        return {
          ok: false,
          steps: steps,
          operation: "precheckin_sequence",
          reason: r2.reason,
          message: r2.message,
          cacheKey: r2.cacheKey,
          httpStatus: r2.httpStatus,
          rawResponse: r2.rawResponse,
          parsed: r2.parsed
        };
      }
    }
    if (km != null) {
      var r3 = await runCalcRatesOperation("KMDriven", km, fuel);
      steps.push(r3);
      if (!r3.ok) {
        return {
          ok: false,
          steps: steps,
          operation: "precheckin_sequence",
          reason: r3.reason,
          message: r3.message,
          cacheKey: r3.cacheKey,
          httpStatus: r3.httpStatus,
          rawResponse: r3.rawResponse,
          parsed: r3.parsed
        };
      }
    } else if (fuel != null) {
      var rFuelOnly = await runCalcRatesOperation("FuelPolicy", null, fuel);
      steps.push(rFuelOnly);
      if (!rFuelOnly.ok) {
        return {
          ok: false,
          steps: steps,
          operation: "precheckin_sequence",
          reason: rFuelOnly.reason,
          message: rFuelOnly.message,
          cacheKey: rFuelOnly.cacheKey,
          httpStatus: rFuelOnly.httpStatus,
          rawResponse: rFuelOnly.rawResponse,
          parsed: rFuelOnly.parsed
        };
      }
    }
    return {
      ok: true,
      steps: steps,
      operation: "precheckin_sequence",
      message: null,
      reason: null,
      cacheKey: steps.length ? steps[0].cacheKey : null,
      eligibleForPrecheckin: true
    };
  }

  function extractFailureMessage(text, diagnostics, hookMessage) {
    if (hookMessage && String(hookMessage).trim()) {
      var hm = String(hookMessage).trim();
      if (hm.indexOf("RequiredError") >= 0) {
        var panel = document.getElementById("checkincar");
        if (panel) {
          var parts = [];
          if (!fieldValue("rdUserTo_combo")) parts.push("check-in user");
          var mf = Number(fieldValue("rdMileageFrom_hidden") || 0);
          var mt = Number(fieldValue("rdMileageTo_hidden") || 0);
          if (!mt || mt <= mf) parts.push("return mileage");
          if (fieldValue("rdTankTo_hidden") == null) parts.push("return fuel");
          if (parts.length) return "Missing required fields: " + parts.join(", ") + ".";
        }
      }
      return hm.replace(/RequiredError[^\\n]*/gi, "Required field missing").trim();
    }
    var blob = String(text || "") + String(diagnostics.bodyTextSample || "");
    if (/MILES_REQUIRED/i.test(blob)) return "Return mileage is required.";
    var req = blob.match(/RequiredError[^\\n<]{0,240}/i);
    if (req) return "Required check-in fields missing (mileage, fuel, or user).";
    var msgMatch = blob.match(/"message"\\s*:\\s*"([^"]{1,300})"/i);
    if (msgMatch && msgMatch[1]) return msgMatch[1];
    if (/Record was changed by/i.test(blob)) {
      var who = blob.match(/Record was changed by ([^\\n"<]{1,80})/i);
      if (who) return who[0];
    }
    return null;
  }

  function readSnapshot() {
    return {
      pk: window.wheels && window.wheels.PK != null ? String(window.wheels.PK) : null,
      target: window.wheels && typeof window.wheels.getPostBackTarget === "function"
        ? window.wheels.getPostBackTarget() : null,
      precheckinCommand: window.rentalcommands ? window.rentalcommands.precheckin : null,
      saveCommand: resolveSaveCommand(),
      rdDispDocno_text: fieldValue("rdDispDocno_text"),
      rdDriver_value: fieldValue("rdDriver_value"),
      rdDriver_text: fieldValue("rdDriver_text"),
      rdPlateNo_value: fieldValue("rdPlateNo_value"),
      rdPlateNo_text: fieldValue("rdPlateNo_text"),
      rdDateFrom_text: fieldValue("rdDateFrom_text"),
      rdTimeFrom_text: fieldValue("rdTimeFrom_text"),
      rdDateTo_text: fieldValue("rdDateTo_text"),
      rdTimeTo_text: fieldValue("rdTimeTo_text"),
      rdStationFrom_combo: fieldValue("rdStationFrom_combo"),
      rdStationTo_combo: fieldValue("rdStationTo_combo"),
      rdGroup_combo: fieldValue("rdGroup_combo"),
      rdGroupInv_combo: fieldValue("rdGroupInv_combo"),
      rdModel_value: fieldValue("rdModel_value"),
      rdModel_text: fieldValue("rdModel_text"),
      rdMileageFrom_hidden: fieldValue("rdMileageFrom_hidden"),
      rdTankFrom_hidden: fieldValue("rdTankFrom_hidden"),
      rdMileageTo_hidden: fieldValue("rdMileageTo_hidden"),
      rdTankTo_hidden: fieldValue("rdTankTo_hidden"),
      rdMilesDriven_hidden: fieldValue("rdMilesDriven_hidden"),
      rdUserTo_combo: fieldValue("rdUserTo_combo")
    };
  }

  async function waitReady(maxMs) {
    var start = Date.now();
    while (Date.now() - start < maxMs) {
      var bodyText = document.body ? document.body.innerText : "";
      if (bodyText.indexOf("Sign in") >= 0 || bodyText.indexOf("Sign In") >= 0) {
        return { ready: false, session: true };
      }
      var disp = fieldValue("rdDispDocno_text");
      if (document.readyState === "complete"
          && window.wheels
          && typeof window.wheels.postBack === "function"
          && typeof window.rentalcommands !== "undefined"
          && document.getElementById("rdDispDocno_text")
          && disp) {
        return { ready: true, session: false };
      }
      await sleep(50);
    }
    return { ready: false, session: false };
  }

  function installNetworkCapture(postPatch) {
    var state = { text: null, status: null, done: false, postPatchApplied: false, postBodySample: null };
    var origOpen = XMLHttpRequest.prototype.open;
    var origSend = XMLHttpRequest.prototype.send;
    XMLHttpRequest.prototype.open = function(method, url) {
      this.__wsUrl = String(url || "");
      this.__wsMethod = String(method || "GET");
      return origOpen.apply(this, arguments);
    };
    XMLHttpRequest.prototype.send = function(body) {
      var xhr = this;
      var url = String(xhr.__wsUrl || "");
      var payload = body != null ? String(body) : "";
      if (postPatch && url.indexOf("rental.aspx") >= 0 && isPrecheckinPostBody(payload)) {
        payload = mergeCheckinFieldsIntoBody(payload, postPatch);
        state.postPatchApplied = true;
        state.postBodySample = payload.slice(0, 3000);
        console.log("[PrecheckinWebView] POST patch applied", JSON.stringify(postPatch));
      }
      xhr.addEventListener("loadend", function() {
        if (url.indexOf("rental.aspx") >= 0) {
          state.text = xhr.responseText;
          state.status = xhr.status;
          state.done = true;
        }
      });
      return origSend.call(this, payload);
    };
    var origFetch = window.fetch;
    window.fetch = async function(input, init) {
      var url = typeof input === "string" ? input : (input && input.url) || "";
      var nextInit = init;
      if (postPatch && String(url).indexOf("rental.aspx") >= 0 && init && init.body) {
        var bodyStr = typeof init.body === "string" ? init.body : null;
        if (bodyStr && isPrecheckinPostBody(bodyStr)) {
          nextInit = Object.assign({}, init, {
            body: mergeCheckinFieldsIntoBody(bodyStr, postPatch)
          });
          state.postPatchApplied = true;
          state.postBodySample = String(nextInit.body).slice(0, 3000);
          console.log("[PrecheckinWebView] fetch POST patch applied", JSON.stringify(postPatch));
        }
      }
      var res = await origFetch.call(this, input, nextInit);
      if (String(url).indexOf("rental.aspx") >= 0) {
        try {
          var clone = res.clone();
          state.text = await clone.text();
          state.status = res.status;
          state.done = true;
        } catch (e) {}
      }
      return res;
    };
    state.restore = function() {
      XMLHttpRequest.prototype.open = origOpen;
      XMLHttpRequest.prototype.send = origSend;
      window.fetch = origFetch;
    };
    return state;
  }

  function installAfterSaveHook() {
    window.__precheckinResult = null;
    window.__precheckinAfterSaveRaw = null;
    window.__precheckinErrors = [];
    if (!window.wheels || typeof window.wheels.afterSave !== "function") return;
    if (window.__precheckinAfterSaveHookInstalled) return;
    window.__precheckinAfterSaveHookInstalled = true;
    var originalAfterSave = window.wheels.afterSave;
    window.wheels.afterSave = function(result, closeWindow) {
      window.__precheckinResult = result;
      window.__precheckinAfterSaveRaw = {
        result: result,
        closeWindow: closeWindow,
        resultJson: JSON.stringify(result)
      };
      console.log("[PRECHECKIN_AFTERSAVE_FULL]", JSON.stringify(result));
      return originalAfterSave.apply(this, arguments);
    };
    window.addEventListener("error", function(e) {
      window.__precheckinErrors.push({
        message: e.message,
        filename: e.filename,
        lineno: e.lineno,
        colno: e.colno
      });
    });
  }

  function readRentalStatus() {
    return {
      title: document.title,
      dbgInitialStatus: window.dbgInitialStatus != null ? String(window.dbgInitialStatus) : null,
      rdStatus: fieldValue("rdStatus"),
      rdUsageType: fieldValue("rdUsageType"),
      rdDispDocno_text: fieldValue("rdDispDocno_text"),
      rdRaDocNo_text: fieldValue("rdRaDocNo_text"),
      rdResDocNo_text: fieldValue("rdResDocNo_text"),
      rdDateTo_text: fieldValue("rdDateTo_text"),
      rdTimeTo_text: fieldValue("rdTimeTo_text"),
      rdMileageTo_hidden: fieldValue("rdMileageTo_hidden"),
      rdTankTo_hidden: fieldValue("rdTankTo_hidden")
    };
  }

  function assessPrecheckinEligibility(status) {
    var title = String(status.title || "");
    var titleLower = title.toLowerCase();
    var rdStatus = String(status.rdStatus || "");
    var rdUsageType = String(status.rdUsageType || "");
    var pageTitle = title;

    if (rdStatus === "3" && rdUsageType === "2") {
      return {
        eligible: false,
        eligibleForPrecheckin: false,
        reasonCode: "already_in_checkin_review",
        reason: "Pre-check-in cannot be completed because this rental is already in review/check-in status in Wheelsys.",
        blocker: "Pre-check-in cannot be completed because this rental is already in review/check-in status in Wheelsys.",
        pageTitle: pageTitle,
        rdStatus: rdStatus
      };
    }
    if (rdStatus === "4" || rdStatus === "5") {
      return {
        eligible: false,
        eligibleForPrecheckin: false,
        reasonCode: "closed_status",
        reason: "This rental is closed in WheelSys.",
        blocker: "This rental is closed in WheelSys.",
        pageTitle: pageTitle,
        rdStatus: rdStatus
      };
    }
    if (/closed|checked.?in|finaliz/i.test(titleLower) && !/review\\s+rental/i.test(titleLower)) {
      return {
        eligible: false,
        eligibleForPrecheckin: false,
        reasonCode: "title_closed",
        reason: "This rental is not in a status where PRECHECKIN is available.",
        blocker: "This rental is not in a status where PRECHECKIN is available.",
        pageTitle: pageTitle,
        rdStatus: rdStatus
      };
    }
    return {
      eligible: true,
      eligibleForPrecheckin: true,
      reasonCode: null,
      reason: null,
      blocker: null,
      pageTitle: pageTitle,
      rdStatus: rdStatus
    };
  }

  function readPostbackDiagnostics() {
    return {
      afterSave: window.__precheckinResult || null,
      afterSaveRaw: window.__precheckinAfterSaveRaw || null,
      errors: window.__precheckinErrors || [],
      bodyTextSample: document.body ? document.body.innerText.slice(0, 4000) : "",
      htmlSample: document.documentElement ? document.documentElement.outerHTML.slice(0, 4000) : "",
      title: document.title,
      url: location.href
    };
  }

  function parseAfterSaveFromHook(hookResult) {
    if (!hookResult) return { success: null, message: null, fullJson: null, object: null };
    var fullJson = JSON.stringify(hookResult);
    var success = hookResult.success === true;
    var message = hookResult.message || hookResult.Message || null;
    return { success: success, message: message, fullJson: fullJson, object: hookResult };
  }

  function parseAfterSave(text) {
    var out = { success: null, message: null, snippet: null };
    if (!text) return out;
    var idx = text.indexOf("wheels.afterSave");
    if (idx < 0) return out;
    out.snippet = text.slice(idx, Math.min(idx + 3000, text.length));
    try {
      var m = out.snippet.match(/wheels\\.afterSave\\(\\{([\\s\\S]*?)\\},\\s*false\\)/);
      if (m) {
        var parsed = JSON.parse("{" + m[1] + "}");
        out.success = parsed.success === true;
        out.message = parsed.message || parsed.Message || null;
      }
    } catch (pe) {}
    return out;
  }

  var readyState = await waitReady(25000);
  if (readyState.session) {
    return JSON.stringify({
      success: false,
      stage: "session",
      error: "Sign in page detected",
      rentalId: rentalId,
      wheelsReady: false
    });
  }
  if (!readyState.ready) {
    return JSON.stringify({
      success: false,
      stage: "not_ready",
      error: "wheels/rentalcommands/rdDispDocno_text not ready within timeout",
      rentalId: rentalId,
      wheelsReady: false,
      snapshot: readSnapshot()
    });
  }

  var domReady = await ensureDomReadbackMatches(
    checkInMileage, checkInFuel, checkInUserId, checkInDate, checkInTime
  );
  var appliedFields = domReady.snapshot;
  if (!domReady.ok) {
    var failDetail = domReady.eval && domReady.eval.issues && domReady.eval.issues.length
      ? domReady.eval.issues.join("; ")
      : ("rdMileageTo_hidden=" + (domReady.snapshot.rdMileageTo_hidden || "0")
        + " rdMileageFrom_hidden=" + (domReady.snapshot.rdMileageFrom_hidden || "?"));
    return JSON.stringify({
      success: false,
      stage: "validation_failed",
      message: "Check-in fields not ready for PRECHECKIN: " + failDetail,
      rentalId: rentalId,
      wheelsReady: true,
      snapshot: readSnapshot(),
      rentalStatus: readRentalStatus(),
      requiredCheck: domReady.snapshot
    });
  }

  var rentalStatusEarly = readRentalStatus();
  var eligibilityEarly = assessPrecheckinEligibility(rentalStatusEarly);
  console.log("[PrecheckinWebView] eligibility pageTitle=" + (eligibilityEarly.pageTitle || "")
    + " rdStatus=" + (eligibilityEarly.rdStatus || "")
    + " eligible=" + (eligibilityEarly.eligibleForPrecheckin === true));
  if (!eligibilityEarly.eligible) {
    return JSON.stringify({
      success: false,
      stage: "status_not_eligible",
      message: eligibilityEarly.blocker || eligibilityEarly.reason,
      reason: eligibilityEarly.reason,
      reasonCode: eligibilityEarly.reasonCode,
      rentalId: rentalId,
      wheelsReady: true,
      eligibleForPrecheckin: false,
      rentalStatus: rentalStatusEarly,
      snapshot: readSnapshot()
    });
  }

  var fieldValidation = validatePrecheckinFields(checkInMileage, checkInFuel);
  console.log("[PrecheckinWebView] validation kmParam=" + checkInMileage
    + " domTo=" + fieldValue("rdMileageTo_hidden")
    + " ok=" + fieldValidation.ok);
  if (!fieldValidation.ok) {
    return JSON.stringify({
      success: false,
      stage: "validation_failed",
      message: fieldValidation.messages.join(" "),
      rentalId: rentalId,
      wheelsReady: true,
      snapshot: readSnapshot(),
      rentalStatus: readRentalStatus()
    });
  }

  var calcDiagnostics = null;
  if (checkInMileage != null || checkInFuel != null) {
    calcDiagnostics = await runPrecheckinCalcRatesSequence(checkInMileage, checkInFuel);
    if (calcDiagnostics.ok) {
      console.log("[PrecheckinWebView] CalcRates precheckin sequence success=true rdStatus="
        + (readRentalStatus().rdStatus || "?"));
    } else {
      console.log("[PrecheckinWebView] CalcRates precheckin sequence success=false msg="
        + (calcDiagnostics.message || calcDiagnostics.reason || "unknown"));
      return JSON.stringify({
        success: false,
        stage: "calcrates_failed",
        message: calcDiagnostics.message || calcDiagnostics.reason || "CalcRates pre-check-in sequence failed",
        rentalId: rentalId,
        wheelsReady: true,
        eligibleForPrecheckin: true,
        snapshot: readSnapshot(),
        rentalStatus: readRentalStatus(),
        appliedFields: appliedFields,
        calcRates: calcDiagnostics
      });
    }
  }

  var snapshot = readSnapshot();
  if (!snapshot.rdDispDocno_text) {
    return JSON.stringify({
      success: false,
      stage: "missing_disp_docno",
      error: "rdDispDocno_text empty in live DOM",
      rentalId: rentalId,
      wheelsReady: true,
      snapshot: snapshot,
      rentalStatus: readRentalStatus()
    });
  }

  var rentalStatus = readRentalStatus();
  var eligibility = assessPrecheckinEligibility(rentalStatus);
  if (!eligibility.eligible) {
    return JSON.stringify({
      success: false,
      stage: "status_not_eligible",
      message: eligibility.reason,
      reason: eligibility.reason,
      reasonCode: eligibility.reasonCode,
      rentalId: rentalId,
      wheelsReady: true,
      snapshot: snapshot,
      rentalStatus: rentalStatus
    });
  }

  var target = snapshot.target;
  var cmd = resolvePrecheckinSaveCommand(snapshot);
  console.log("[PrecheckinWebView] postBack cmd=" + cmd
    + " precheckinCmd=" + (resolvePrecheckinCommand(snapshot) || "nil")
    + " saveCmd=" + resolveSaveCommand());
  var pk = snapshot.pk || String(rentalId);
  if (!target || !cmd) {
    return JSON.stringify({
      success: false,
      stage: "missing_postback",
      error: "postBack target or BTSAVE command missing",
      rentalId: rentalId,
      wheelsReady: true,
      snapshot: snapshot,
      rentalStatus: rentalStatus
    });
  }

  // Re-apply immediately before postBack and confirm DOM readback one last time.
  domReady = await ensureDomReadbackMatches(
    checkInMileage, checkInFuel, checkInUserId, checkInDate, checkInTime
  );
  appliedFields = domReady.snapshot;
  if (!domReady.ok) {
    var failDetail = domReady.eval && domReady.eval.issues && domReady.eval.issues.length
      ? domReady.eval.issues.join("; ")
      : "unknown";
    return JSON.stringify({
      success: false,
      stage: "validation_failed",
      message: "Check-in fields not written to WheelSys DOM before BTSAVE: " + failDetail,
      rentalId: rentalId,
      wheelsReady: true,
      snapshot: readSnapshot(),
      rentalStatus: rentalStatus,
      requiredCheck: domReady.snapshot
    });
  }
  await sleep(30);

  if (checkInMileage != null) {
    await applyReturnKmAndDriven(checkInMileage, resolvedMileageFieldIds());
  }
  var postPatch = buildPrecheckinPostPatch(
    checkInMileage, checkInFuel, checkInUserId, checkInDate, checkInTime
  );
  console.log("[PrecheckinWebView] postPatch ready", JSON.stringify(postPatch));

  installAfterSaveHook();

  var capture = installNetworkCapture(postPatch);
  try {
    window.wheels.postBack(target, cmd, pk);
    var waitStart = Date.now();
    while (Date.now() - waitStart < 25000) {
      if (window.__precheckinResult) break;
      if (capture.done && capture.text && capture.text.indexOf("wheels.afterSave") >= 0) break;
      await sleep(50);
    }
  } finally {
    if (capture.restore) capture.restore();
  }

  var diagnostics = readPostbackDiagnostics();
  var text = capture.text || "";
  var hookParsed = parseAfterSaveFromHook(diagnostics.afterSave);
  var networkParsed = parseAfterSave(text);
  var afterSaveSuccess = hookParsed.success != null ? hookParsed.success : networkParsed.success;
  var afterSaveMessage = hookParsed.message || networkParsed.message || null;
  var containsAfterSave = Boolean(diagnostics.afterSave) || text.indexOf("wheels.afterSave") >= 0;
  var containsPrecheckin = /precheckin/i.test(text) || /precheckin/i.test(diagnostics.bodyTextSample || "");
  var bodyHasSignIn = text.indexOf("Sign in") >= 0 || text.indexOf("login.aspx") >= 0;
  var success = afterSaveSuccess === true && !bodyHasSignIn;
  var displayMessage = success
    ? (afterSaveMessage && String(afterSaveMessage).trim() ? String(afterSaveMessage).trim() : "Pre-check-in completed.")
    : (extractFailureMessage(text, diagnostics, afterSaveMessage) || "WheelSys rejected pre-check-in.");

  return JSON.stringify({
    success: success,
    stage: "precheckin_postback",
    message: displayMessage,
    reason: success ? null : (eligibility.reason || null),
    rentalId: rentalId,
    httpStatus: capture.status,
    responseLength: text.length,
    containsAfterSave: containsAfterSave,
    containsPrecheckin: containsPrecheckin,
    afterSaveSuccess: afterSaveSuccess,
    afterSaveMessage: afterSaveMessage,
    afterSaveSnippet: hookParsed.fullJson || networkParsed.snippet || null,
    afterSave: diagnostics.afterSave,
    afterSaveFullJson: hookParsed.fullJson,
    responsePreview: text.slice(0, 5000),
    bodyTextSample: diagnostics.bodyTextSample,
    htmlSample: diagnostics.htmlSample,
    pageTitle: diagnostics.title,
    pageUrl: diagnostics.url,
    snapshot: snapshot,
    rentalStatus: rentalStatus,
    errors: diagnostics.errors,
    wheelsReady: true,
    eligibleForPrecheckin: eligibility.eligibleForPrecheckin !== false,
    calcRates: calcDiagnostics,
    appliedFields: appliedFields,
    postPatch: postPatch,
    postPatchApplied: capture.postPatchApplied === true,
    postBodySample: capture.postBodySample || null
  });
} catch (e) {
  return JSON.stringify({
    success: false,
    stage: "exception",
    error: String(e),
    stack: e && e.stack ? String(e.stack) : null,
    rentalId: \(rentalId)
  });
}
"""
    }
}

// MARK: - WKNavigationDelegate

extension WheelSysPrecheckinWebViewFetcher: WKNavigationDelegate {

    nonisolated func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        Task { @MainActor in
            let href = webView.url?.absoluteString ?? ""
            if href.lowercased().contains("sign-in") || href.lowercased().contains("login") {
                navContinuation?.resume(throwing: WheelSysPrecheckinWebViewError.sessionExpired)
            } else {
                navContinuation?.resume()
            }
            navContinuation = nil
        }
    }

    nonisolated func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        Task { @MainActor in
            navContinuation?.resume(throwing: WheelSysPrecheckinWebViewError.pageLoadFailed(
                error.localizedDescription
            ))
            navContinuation = nil
        }
    }

    nonisolated func webView(
        _ webView: WKWebView,
        didFailProvisionalNavigation navigation: WKNavigation!,
        withError error: Error
    ) {
        Task { @MainActor in
            navContinuation?.resume(throwing: WheelSysPrecheckinWebViewError.pageLoadFailed(
                error.localizedDescription
            ))
            navContinuation = nil
        }
    }
}
