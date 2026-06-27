import Foundation
import UIKit
import WebKit

// MARK: - Models

/// Vehicle update mode for booking.aspx BTSAVE.
enum WheelSysVehicleUpdateMode: String, Hashable, Codable {
    case assign
    case change
    case remove
}

struct WheelSysBookingPageContext {
    let bookingEntityId: Int
    /// Form field `cachekey` extracted from DOM — required for BTSAVE.
    let cacheKey: String
    let viewState: String?
    /// All current FormData(document.forms[0]) entries.
    let formData: [String: String]
    /// rdDispDocno_text — the real RES number, e.g. RES-17694. Never the confirmation number.
    let displayDocNo: String?
    /// rdIrnDisp_text — IRN, e.g. 8075732.
    let irn: String?
    /// rdConfno_text — agent/external confirmation, e.g. JIG(A)-6813462-67939.
    let confirmationNo: String?
    /// rdVoucherno_text
    let voucherNo: String?
    /// Currently assigned plate (rdPlateNo_text).
    let currentPlate: String?
    /// Currently assigned Wheelsys vehicle id (rdPlateNo_value).
    let currentVehicleId: String?
    /// rdDriver_text — driver name from booking page.
    let driverName: String?
    /// rdGroup_combo — operational vehicle group.
    let operationalGroup: String?
    /// rdGroupRes_text — original reservation/booked group display.
    let reservationGroup: String?
    /// rdGroupInv_combo — charge/invoice group (must be preserved on save).
    let chargeGroup: String?
    /// rdUsageType hidden field.
    let usageType: String?
}

/// Vehicle + operational category fields for BTSAVE (does not touch charge group).
struct WheelSysVehicleAssignPayload {
    let plate: String
    let vehicleId: Int
    let operationalGroup: String
    let modelName: String
    let modelId: Int
}

/// Response from rentalsupport/car/canusecar.
struct WheelSysCanUseCarResult: Codable {
    let carId: Int?
    let plateNo: String?
    let isUsable: Bool?
    let carGroup: String?
    let carInfo: CarInfo?
    let warnings: [Warning]?

    enum CodingKeys: String, CodingKey {
        case carId = "CarId"
        case plateNo = "PlateNo"
        case isUsable = "IsUsable"
        case carGroup = "CarGroup"
        case carInfo = "CarInfo"
        case warnings = "Warnings"
    }

    struct CarInfo: Codable {
        let modelName: String?
        let modelTableId: Int?

        enum CodingKeys: String, CodingKey {
            case modelName = "ModelName"
            case modelTableId = "ModelTableId"
        }
    }

    struct Warning: Codable {
        let availAction: String?
        let remarks: String?

        enum CodingKeys: String, CodingKey {
            case availAction = "AvailAction"
            case remarks = "Remarks"
        }
    }

    var warningMessage: String? {
        guard let warnings, !warnings.isEmpty else { return nil }
        let parts = warnings.compactMap { w -> String? in
            let action = w.availAction?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let remarks = w.remarks?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !action.isEmpty && !remarks.isEmpty { return "\(action): \(remarks)" }
            if !action.isEmpty { return action }
            if !remarks.isEmpty { return remarks }
            return nil
        }
        return parts.isEmpty ? nil : parts.joined(separator: "; ")
    }
}

/// Codable result returned by the BTSAVE JS wrapper.
/// The JS returns JSON.stringify({...}), which callAsyncJavaScript resolves to a String.
struct WheelSysAssignSaveResult: Codable {
    let success: Bool
    let stage: String?
    let mode: String?
    let status: Int?
    let responseOk: Bool?
    let containsAfterSave: Bool?
    let containsSuccessTrue: Bool?
    let containsFailureFalse: Bool?
    let bodyHasSignIn: Bool?
    let bookingEntityId: Int?
    let plate: String?
    let vehicleId: Int?
    let responseLength: Int?
    let afterSaveSnippet: String?
    let responsePreview: String?
    let keyValue: Int?
    let irn: String?
    let newTitle: String?
    let error: String?
    let stack: String?
}

// MARK: - Errors

enum WheelSysBookingFetchError: LocalizedError {
    case sessionExpired
    case cacheKeyMissing
    case noWebView
    case pageLoadFailed(String)
    case javaScriptError(String)
    case invalidResponse(String)
    case saveFailed(String)

    var errorDescription: String? {
        switch self {
        case .sessionExpired:
            return "WheelSys session expired. Please log in again."
        case .cacheKeyMissing:
            return "Booking page cachekey could not be extracted. Please reopen the booking page."
        case .noWebView:
            return "Booking page WebView not ready."
        case .pageLoadFailed(let msg):
            return "Booking page load failed: \(msg)"
        case .javaScriptError(let msg):
            return "Booking page script error: \(msg)"
        case .invalidResponse(let msg):
            return "Booking page invalid response: \(msg)"
        case .saveFailed(let msg):
            return msg
        }
    }
}

// MARK: - Fetcher

/// Loads `booking.aspx?entityId=X` inside the shared WKWebView session (authenticated via
/// `.default()` data store), extracts form context including `cachekey`, then performs
/// the real BTSAVE POST using `credentials: include`.
///
/// Key implementation notes:
/// - `extractContextJS` is used with `evaluateJavaScript` → IIFE expression, result = expression value.
/// - `makeAssignJS` is used with `callAsyncJavaScript` → raw function body with `return` at top level.
///   Do NOT wrap in `(async function(){...})()` — `callAsyncJavaScript` already provides the async wrapper.
@MainActor
final class WheelSysBookingPageFetcher: NSObject {

    private static let baseURL = "https://ch.wheelsys.greenmotion.com"
    private static let userAgent =
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 "
        + "(KHTML, like Gecko) Chrome/125.0.0.0 Safari/537.36"

    let bookingEntityId: Int

    private var webView: WKWebView?
    private var hostWindow: UIWindow?
    private var navContinuation: CheckedContinuation<Void, Error>?

    init(bookingEntityId: Int) {
        self.bookingEntityId = bookingEntityId
        super.init()
    }

    // MARK: - Phase 1: Load page + extract context

    func loadAndExtractContext() async throws -> WheelSysBookingPageContext {
        let url = URL(
            string: "\(Self.baseURL)/ui/manage/master/booking.aspx?entityId=\(bookingEntityId)"
        )!
        print("[WheelSys][Assign] loading booking page url=\(url.absoluteString)")

        let wv = makeWebView()
        self.webView = wv
        attachToHiddenWindow(wv)

        try await loadPage(wv, url: url)

        var ctx = try await extractContext(from: wv)

        if ctx.cacheKey.isEmpty {
            print("[WheelSys][Assign] cachekey missing — reloading booking page once")
            try await loadPage(wv, url: url)
            ctx = try await extractContext(from: wv)
            guard !ctx.cacheKey.isEmpty else {
                throw WheelSysBookingFetchError.cacheKeyMissing
            }
        }

        print("[WheelSys][Assign] extracted context "
            + "cacheKeyExists=\(!ctx.cacheKey.isEmpty) "
            + "displayDocNo=\(ctx.displayDocNo ?? "nil") "
            + "irn=\(ctx.irn ?? "nil") "
            + "confirmationNo=\(ctx.confirmationNo ?? "nil")")

        return ctx
    }

    // MARK: - Phase 2: BTSAVE (assign / change / remove)

    func performAssign(
        plate: String,
        vehicleId: Int,
        payload: WheelSysVehicleAssignPayload? = nil
    ) async throws -> WheelSysAssignSaveResult {
        try await performVehicleUpdate(mode: .assign, plate: plate, vehicleId: vehicleId, assignPayload: payload)
    }

    func performChange(
        plate: String,
        vehicleId: Int,
        oldPlate: String?,
        payload: WheelSysVehicleAssignPayload? = nil
    ) async throws -> WheelSysAssignSaveResult {
        print("[WheelSys][Assign] mode=change bookingEntityId=\(bookingEntityId) "
            + "oldPlate=\(oldPlate ?? "nil") newPlate=\(plate) newVehicleId=\(vehicleId)")
        return try await performVehicleUpdate(mode: .change, plate: plate, vehicleId: vehicleId, assignPayload: payload)
    }

    func performRemove(oldPlate: String?) async throws -> WheelSysAssignSaveResult {
        print("[WheelSys][Assign] mode=remove bookingEntityId=\(bookingEntityId) "
            + "oldPlate=\(oldPlate ?? "nil")")
        return try await performVehicleUpdate(mode: .remove, plate: nil, vehicleId: nil, assignPayload: nil)
    }

    func performVehicleUpdate(
        mode: WheelSysVehicleUpdateMode,
        plate: String?,
        vehicleId: Int?,
        assignPayload: WheelSysVehicleAssignPayload? = nil
    ) async throws -> WheelSysAssignSaveResult {
        guard let wv = webView else {
            throw WheelSysBookingFetchError.noWebView
        }

        switch mode {
        case .assign, .change:
            guard let plate, let vehicleId else {
                throw WheelSysBookingFetchError.saveFailed("Plate and vehicle ID required for \(mode.rawValue)")
            }
            if mode == .assign {
                print("[WheelSys][Assign] mode=assign bookingEntityId=\(bookingEntityId) "
                    + "plate=\(plate) vehicleId=\(vehicleId)")
            }
            if let assignPayload {
                print("[WheelSys][Assign] mode=\(mode.rawValue) operationalGroup=\(assignPayload.operationalGroup) "
                    + "chargeGroup preserved bookingEntityId=\(bookingEntityId)")
            }
            print("[WheelSys][Assign] mode=\(mode.rawValue) posting BTSAVE "
                + "bookingEntityId=\(bookingEntityId) plate=\(plate) vehicleId=\(vehicleId)")
            let js = Self.makeVehicleUpdateJS(
                mode: mode,
                bookingEntityId: bookingEntityId,
                plate: plate,
                vehicleId: vehicleId,
                assignPayload: assignPayload
            )
            return try await executeVehicleUpdateJS(js, on: wv, expectedEntityId: bookingEntityId)

        case .remove:
            print("[WheelSys][Assign] mode=remove posting BTSAVE bookingEntityId=\(bookingEntityId)")
            let js = Self.makeVehicleUpdateJS(
                mode: .remove,
                bookingEntityId: bookingEntityId,
                plate: "",
                vehicleId: 0,
                assignPayload: nil
            )
            return try await executeVehicleUpdateJS(js, on: wv, expectedEntityId: bookingEntityId)
        }
    }

    /// Pre-save usability check via authenticated WebView session.
    func checkCanUseCar(
        plate: String,
        vehicleId: Int,
        dateFrom: String,
        dateTo: String,
        usageReq: Int = 1
    ) async throws -> WheelSysCanUseCarResult {
        guard let wv = webView else {
            throw WheelSysBookingFetchError.noWebView
        }
        let js = Self.makeCanUseCarJS(
            plate: plate,
            vehicleId: vehicleId,
            rentalId: bookingEntityId,
            dateFrom: dateFrom,
            dateTo: dateTo,
            usageReq: usageReq
        )
        return try await withCheckedThrowingContinuation { cont in
            wv.callAsyncJavaScript(js, arguments: [:], in: nil, in: .page) { result in
                Task { @MainActor in
                    switch result {
                    case .success(let value):
                        do {
                            let parsed = try Self.decodeCanUseCarResult(from: value)
                            cont.resume(returning: parsed)
                        } catch {
                            cont.resume(throwing: error)
                        }
                    case .failure(let error):
                        cont.resume(throwing: WheelSysBookingFetchError.javaScriptError(
                            error.localizedDescription
                        ))
                    }
                }
            }
        }
    }

    private func executeVehicleUpdateJS(
        _ js: String,
        on wv: WKWebView,
        expectedEntityId: Int
    ) async throws -> WheelSysAssignSaveResult {
        try await withCheckedThrowingContinuation { cont in
            wv.callAsyncJavaScript(js, arguments: [:], in: nil, in: .page) { [weak self] result in
                Task { @MainActor in
                    guard self != nil else {
                        cont.resume(throwing: WheelSysBookingFetchError.noWebView)
                        return
                    }
                    switch result {
                    case .success(let value):
                        do {
                            let parsed = try Self.decodeAssignResult(
                                from: value,
                                expectedEntityId: expectedEntityId
                            )
                            cont.resume(returning: parsed)
                        } catch {
                            cont.resume(throwing: error)
                        }
                    case .failure(let error):
                        cont.resume(throwing: WheelSysBookingFetchError.javaScriptError(
                            error.localizedDescription
                        ))
                    }
                }
            }
        }
    }

    func cleanup() {
        navContinuation?.resume(throwing: WheelSysBookingFetchError.pageLoadFailed("cleanup"))
        navContinuation = nil
        webView?.navigationDelegate = nil
        webView = nil
        hostWindow?.isHidden = true
        hostWindow = nil
    }

    // MARK: - Private helpers

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

    private func loadPage(_ wv: WKWebView, url: URL) async throws {
        let request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 30)
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            self.navContinuation = cont
            wv.load(request)
        }
        // ASP.NET JavaScript initialization delay
        try await Task.sleep(nanoseconds: 1_500_000_000)
    }

    private func extractContext(from wv: WKWebView) async throws -> WheelSysBookingPageContext {
        // extractContextJS is a synchronous IIFE — used with evaluateJavaScript, returns expression value.
        return try await withCheckedThrowingContinuation { cont in
            wv.evaluateJavaScript(Self.extractContextJS) { [weak self] value, error in
                Task { @MainActor in
                    guard let self else { return }
                    if let error {
                        cont.resume(throwing: WheelSysBookingFetchError.javaScriptError(
                            error.localizedDescription
                        ))
                        return
                    }
                    guard let jsonStr = value as? String else {
                        cont.resume(throwing: WheelSysBookingFetchError.javaScriptError(
                            "Context JS returned \(type(of: value)) instead of String"
                        ))
                        return
                    }
                    do {
                        let ctx = try self.parseContext(jsonStr)
                        cont.resume(returning: ctx)
                    } catch {
                        cont.resume(throwing: error)
                    }
                }
            }
        }
    }

    private func parseContext(_ jsonStr: String) throws -> WheelSysBookingPageContext {
        guard !jsonStr.isEmpty,
              let data = jsonStr.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            throw WheelSysBookingFetchError.javaScriptError("Context extraction JSON invalid")
        }

        if json["bodyHasSignIn"] as? Bool == true {
            throw WheelSysBookingFetchError.sessionExpired
        }
        if json["success"] as? Bool != true {
            let errMsg = json["error"] as? String ?? "Unknown context error"
            throw WheelSysBookingFetchError.javaScriptError(errMsg)
        }

        let formData = (json["formData"] as? [String: Any] ?? [:]).compactMapValues { v -> String? in
            let s = String(describing: v).trimmingCharacters(in: .whitespacesAndNewlines)
            return s.isEmpty ? nil : s
        }

        func pick(_ key: String) -> String? {
            let v = (json[key] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            return v.isEmpty ? nil : v
        }

        return WheelSysBookingPageContext(
            bookingEntityId: bookingEntityId,
            cacheKey: pick("cachekey") ?? "",
            viewState: pick("viewstate"),
            formData: formData,
            displayDocNo: pick("rdDispDocno_text"),
            irn: pick("rdIrnDisp_text"),
            confirmationNo: pick("rdConfno_text"),
            voucherNo: pick("rdVoucherno_text"),
            currentPlate: pick("rdPlateNo_text"),
            currentVehicleId: pick("rdPlateNo_value"),
            driverName: pick("rdDriver_text"),
            operationalGroup: pick("rdGroup_combo"),
            reservationGroup: pick("rdGroupRes_text"),
            chargeGroup: pick("rdGroupInv_combo"),
            usageType: pick("rdUsageType") ?? formData["rdUsageType"]
        )
    }

    /// Decodes the JSON string returned by the BTSAVE JS function body.
    /// WKWebView's callAsyncJavaScript resolves the async function and returns the result:
    ///   - If JS returns a String (our case: JSON.stringify({...})) → value is String
    ///   - If JS returns an Object → value may be a Dictionary
    private static func decodeAssignResult(
        from value: Any?,
        expectedEntityId: Int
    ) throws -> WheelSysAssignSaveResult {
        let resultString: String

        if let string = value as? String {
            resultString = string
        } else if let dict = value as? [String: Any],
                  let data = try? JSONSerialization.data(withJSONObject: dict),
                  let str = String(data: data, encoding: .utf8) {
            resultString = str
        } else {
            let typeDesc = String(describing: type(of: value))
            let preview = String(describing: value).prefix(200)
            print("[WheelSys][Assign] BTSAVE raw JS result type=\(typeDesc) preview=\(preview)")
            throw WheelSysBookingFetchError.invalidResponse(
                "BTSAVE JS returned \(typeDesc) instead of String"
            )
        }

        print("[WheelSys][Assign] raw JS result prefix=\(String(resultString.prefix(1000)))")

        guard !resultString.isEmpty, let data = resultString.data(using: .utf8) else {
            throw WheelSysBookingFetchError.invalidResponse("BTSAVE JS returned empty result")
        }

        let result: WheelSysAssignSaveResult
        do {
            result = try JSONDecoder().decode(WheelSysAssignSaveResult.self, from: data)
        } catch {
            print("[WheelSys][Assign] BTSAVE decode error=\(error) resultString=\(String(resultString.prefix(2000)))")
            throw WheelSysBookingFetchError.invalidResponse(
                "BTSAVE result decode failed: \(error.localizedDescription)"
            )
        }

        print("[WheelSys][Assign] BTSAVE parsed "
            + "success=\(result.success) "
            + "status=\(result.status ?? -1) "
            + "containsAfterSave=\(result.containsAfterSave ?? false) "
            + "containsSuccessTrue=\(result.containsSuccessTrue ?? false) "
            + "bodyHasSignIn=\(result.bodyHasSignIn ?? false)")

        if result.bodyHasSignIn == true, result.success == false {
            throw WheelSysBookingFetchError.sessionExpired
        }

        if !result.success {
            let stage = result.stage ?? "unknown"
            let errMsg = result.error ?? "BTSAVE failed"
            print("[WheelSys][Assign] BTSAVE failed "
                + "stage=\(stage) "
                + "error=\(errMsg) "
                + "afterSaveSnippet=\(result.afterSaveSnippet ?? "nil") "
                + "responsePreview=\(String((result.responsePreview ?? "").prefix(500)))")
            throw WheelSysBookingFetchError.saveFailed(
                "\(errMsg). status=\(result.status ?? -1), "
                + "containsAfterSave=\(result.containsAfterSave ?? false), "
                + "containsSuccessTrue=\(result.containsSuccessTrue ?? false)"
            )
        }

        if let kv = result.keyValue, kv > 0, kv != expectedEntityId {
            print("[WheelSys][Assign] BTSAVE keyValue mismatch expected=\(expectedEntityId) got=\(kv)")
            throw WheelSysBookingFetchError.saveFailed(
                "BTSAVE keyValue \(kv) does not match booking entity \(expectedEntityId)"
            )
        }

        print("[WheelSys][Assign] BTSAVE save success keyValue=\(result.keyValue.map(String.init) ?? "nil") "
            + "irn=\(result.irn ?? "nil")")

        return result
    }

    private static func decodeCanUseCarResult(from value: Any?) throws -> WheelSysCanUseCarResult {
        let resultString: String
        if let string = value as? String {
            resultString = string
        } else if let dict = value as? [String: Any],
                  let data = try? JSONSerialization.data(withJSONObject: dict),
                  let str = String(data: data, encoding: .utf8) {
            resultString = str
        } else {
            throw WheelSysBookingFetchError.invalidResponse(
                "canUseCar returned \(type(of: value)) instead of String"
            )
        }
        guard let data = resultString.data(using: .utf8) else {
            throw WheelSysBookingFetchError.invalidResponse("canUseCar empty result")
        }
        return try JSONDecoder().decode(WheelSysCanUseCarResult.self, from: data)
    }

    // MARK: - JavaScript

    /// Synchronous IIFE — used with `evaluateJavaScript`. Returns expression value = JSON string.
    private static let extractContextJS = #"""
(function() {
  try {
    var form = document.forms[0];
    if (!form) return JSON.stringify({ success: false, error: "No form found" });
    var fd = new FormData(form);
    var data = {};
    fd.forEach(function(value, key) { data[key] = value; });
    function getVal(name) {
      var el = document.querySelector('[name="' + name + '"]') || document.getElementById(name);
      return el ? (el.value || '') : null;
    }
    var bodyText = document.body ? document.body.innerText : '';
    return JSON.stringify({
      success: true,
      href: location.href,
      title: document.title,
      bodyHasSignIn: bodyText.indexOf('Sign in') >= 0 || bodyText.indexOf('Sign In') >= 0,
      cachekey: data['cachekey'] || getVal('cachekey') || '',
      viewstate: data['__VIEWSTATE'] || getVal('__VIEWSTATE') || null,
      rdDispDocno_text: data['rdDispDocno_text'] || getVal('rdDispDocno_text') || '',
      rdIrnDisp_text: data['rdIrnDisp_text'] || getVal('rdIrnDisp_text') || '',
      rdConfno_text: data['rdConfno_text'] || getVal('rdConfno_text') || '',
      rdVoucherno_text: data['rdVoucherno_text'] || getVal('rdVoucherno_text') || '',
      rdPlateNo_text: data['rdPlateNo_text'] || getVal('rdPlateNo_text') || '',
      rdPlateNo_value: data['rdPlateNo_value'] || getVal('rdPlateNo_value') || '',
      rdDriver_text: data['rdDriver_text'] || getVal('rdDriver_text') || '',
      rdDriver_value: data['rdDriver_value'] || getVal('rdDriver_value') || '',
      rdGroup_combo: data['rdGroup_combo'] || getVal('rdGroup_combo') || '',
      rdGroupRes_text: data['rdGroupRes_text'] || getVal('rdGroupRes_text') || '',
      rdGroupInv_combo: data['rdGroupInv_combo'] || getVal('rdGroupInv_combo') || '',
      rdUsageType: data['rdUsageType'] || getVal('rdUsageType') || '',
      formData: data
    });
  } catch(e) {
    return JSON.stringify({ success: false, error: String(e) });
  }
})()
"""#

    // MARK: - Safe JS literal helpers

    /// JSON-encodes a Swift String into a JS string literal (handles quotes, backslashes, etc.)
    private static func jsStringLiteral(_ value: String) -> String {
        let data = (try? JSONEncoder().encode(value)) ?? Data()
        return String(data: data, encoding: .utf8) ?? "\"\""
    }

    /// Raw function body for `callAsyncJavaScript` — assign, change, or remove vehicle via BTSAVE.
    private static func makeVehicleUpdateJS(
        mode: WheelSysVehicleUpdateMode,
        bookingEntityId: Int,
        plate: String,
        vehicleId: Int,
        assignPayload: WheelSysVehicleAssignPayload?
    ) -> String {
        let plateFieldsJS: String
        switch mode {
        case .assign, .change:
            if let payload = assignPayload {
                let groupJS = jsStringLiteral(payload.operationalGroup)
                let modelJS = jsStringLiteral(payload.modelName)
                plateFieldsJS = """
  fd.set("rdGroup_combo", \(groupJS));
  fd.set("rdPlateNo_text", plate);
  fd.set("rdPlateNo_value", String(vehicleId));
  fd.set("rdPlateNo_hqe", "true");
  fd.set("rdModel_text", \(modelJS));
  fd.set("rdModel_value", String(\(payload.modelId)));
  fd.set("rdModel_hqe", "true");
"""
            } else {
                plateFieldsJS = """
  fd.set("rdPlateNo_text", plate);
  fd.set("rdPlateNo_value", String(vehicleId));
  fd.set("rdPlateNo_hqe", "true");
"""
            }
        case .remove:
            plateFieldsJS = """
  fd.set("rdPlateNo_text", "");
  fd.set("rdPlateNo_value", "");
  fd.set("rdPlateNo_hqe", "");
  fd.set("rdPlateNo_tvl", "");
"""
        }

        let template = """
try {
  const bookingEntityId = BOOKING_ENTITY_ID_PLACEHOLDER;
  const plate = PLATE_PLACEHOLDER;
  const vehicleId = VEHICLE_ID_PLACEHOLDER;
  const mode = MODE_PLACEHOLDER;
  const form = document.forms[0];
  if (!form) {
    return JSON.stringify({
      success: false,
      stage: "form",
      error: "No form found on booking page"
    });
  }
  const fd = new FormData(form);
  fd.set("ctl00$ctl00$ctl00$coreBody$ScriptManager",
         "ctl00$ctl00$ctl00$coreBody$contentBody$formFields$rentalPanel|rentalPanel");
  fd.set("__EVENTTARGET", "rentalPanel");
  fd.set("__EVENTARGUMENT", JSON.stringify({
    action: "BTSAVE",
    itemId: String(bookingEntityId)
  }));
PLATE_FIELDS_PLACEHOLDER
  fd.set("__ASYNCPOST", "true");
  const cacheKey = fd.get("cachekey");
  if (!cacheKey || String(cacheKey).trim().length === 0) {
    return JSON.stringify({
      success: false,
      stage: "cachekey",
      error: "Booking cachekey missing before save"
    });
  }
  const body = new URLSearchParams();
  for (const [key, value] of fd.entries()) {
    body.append(key, value == null ? "" : String(value));
  }
  const response = await fetch("/ui/manage/master/booking.aspx?entityId=" + bookingEntityId, {
    method: "POST",
    credentials: "include",
    headers: {
      "Content-Type": "application/x-www-form-urlencoded; charset=utf-8",
      "X-MicrosoftAjax": "Delta=true",
      "X-Requested-With": "XMLHttpRequest"
    },
    body: body.toString()
  });
  const text = await response.text();
  const containsAfterSave = text.includes("wheels.afterSave");
  const containsSuccessTrue = text.includes('"success":true') || text.includes('"success": true');
  const containsFailureFalse = text.includes('"success":false') || text.includes('"success": false');
  const bodyHasSignIn =
    text.includes("Sign in") ||
    text.includes("Login") ||
    text.includes("Password") ||
    text.includes("login.aspx");
  const success =
    response.ok &&
    containsAfterSave &&
    containsSuccessTrue &&
    !containsFailureFalse &&
    !bodyHasSignIn;
  let afterSaveSnippet = null;
  const idx = text.indexOf("wheels.afterSave");
  if (idx >= 0) {
    afterSaveSnippet = text.slice(idx, Math.min(idx + 3000, text.length));
  }
  let keyValue = null, irn = null, newTitle = null;
  if (afterSaveSnippet) {
    try {
      const m = afterSaveSnippet.match(/wheels\\.afterSave\\(\\{([\\s\\S]*?)\\},\\s*false\\)/);
      if (m) {
        const parsed = JSON.parse("{" + m[1] + "}");
        keyValue = parsed.keyValue || null;
        irn = (parsed.ExtraData && parsed.ExtraData.irn) || null;
        newTitle = (parsed.ExtraData && parsed.ExtraData.newTitle) || null;
      }
    } catch(pe) {}
  }
  return JSON.stringify({
    success: success,
    stage: "btsave",
    mode: mode,
    status: response.status,
    responseOk: response.ok,
    containsAfterSave: containsAfterSave,
    containsSuccessTrue: containsSuccessTrue,
    containsFailureFalse: containsFailureFalse,
    bodyHasSignIn: bodyHasSignIn,
    bookingEntityId: bookingEntityId,
    plate: plate,
    vehicleId: vehicleId,
    responseLength: text.length,
    afterSaveSnippet: afterSaveSnippet,
    keyValue: keyValue,
    irn: irn,
    newTitle: newTitle,
    responsePreview: text.slice(0, 5000)
  });
} catch(e) {
  return JSON.stringify({
    success: false,
    stage: "exception",
    error: String(e),
    stack: e && e.stack ? String(e.stack) : null
  });
}
"""
        return template
            .replacingOccurrences(of: "BOOKING_ENTITY_ID_PLACEHOLDER", with: String(bookingEntityId))
            .replacingOccurrences(of: "PLATE_PLACEHOLDER", with: jsStringLiteral(plate))
            .replacingOccurrences(of: "VEHICLE_ID_PLACEHOLDER", with: String(vehicleId))
            .replacingOccurrences(of: "MODE_PLACEHOLDER", with: jsStringLiteral(mode.rawValue))
            .replacingOccurrences(of: "PLATE_FIELDS_PLACEHOLDER", with: plateFieldsJS)
    }

    private static func makeCanUseCarJS(
        plate: String,
        vehicleId: Int,
        rentalId: Int,
        dateFrom: String,
        dateTo: String,
        usageReq: Int
    ) -> String {
        let body = [
            "plateNo=\(plate.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? plate)",
            "carId=\(vehicleId)",
            "dateFrom=\(dateFrom.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? dateFrom)",
            "dateTo=\(dateTo.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? dateTo)",
            "usageReq=\(usageReq)",
            "rId=\(rentalId)",
            "isRentalId=true",
        ].joined(separator: "&")

        return """
try {
  const response = await fetch("/api/entities/rentalsupport/car/canusecar", {
    method: "POST",
    credentials: "include",
    headers: {
      "Content-Type": "application/x-www-form-urlencoded; charset=UTF-8",
      "X-Requested-With": "XMLHttpRequest"
    },
    body: \(jsStringLiteral(body))
  });
  if (!response.ok) {
    return JSON.stringify({ IsUsable: false, error: "canUseCar HTTP " + response.status });
  }
  const json = await response.json();
  return JSON.stringify(json);
} catch(e) {
  return JSON.stringify({ IsUsable: false, error: String(e) });
}
"""
    }
}

// MARK: - WKNavigationDelegate

extension WheelSysBookingPageFetcher: WKNavigationDelegate {

    nonisolated func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        Task { @MainActor in
            self.navContinuation?.resume()
            self.navContinuation = nil
        }
    }

    nonisolated func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        Task { @MainActor in
            self.navContinuation?.resume(
                throwing: WheelSysBookingFetchError.pageLoadFailed(error.localizedDescription)
            )
            self.navContinuation = nil
        }
    }

    nonisolated func webView(
        _ webView: WKWebView,
        didFailProvisionalNavigation navigation: WKNavigation!,
        withError error: Error
    ) {
        Task { @MainActor in
            self.navContinuation?.resume(
                throwing: WheelSysBookingFetchError.pageLoadFailed(error.localizedDescription)
            )
            self.navContinuation = nil
        }
    }
}
