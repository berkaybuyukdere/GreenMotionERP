import Foundation
import UIKit
import WebKit

enum WheelSysNTRFetchError: LocalizedError {
    case sessionExpired
    case pageLoadFailed(String)
    case panelNotReady
    case userDetectionFailed
    case javaScriptError(String)
    case saveFailed(String)
    case invalidResponse(String)

    var errorDescription: String? {
        switch self {
        case .sessionExpired:
            return "WheelSys session expired. Please log in again."
        case .pageLoadFailed(let msg):
            return "NTR page load failed: \(msg)"
        case .panelNotReady:
            return "WheelSys non-revenue page is not ready."
        case .userDetectionFailed:
            return "Could not detect logged-in Wheelsys user. Open the NTR page once and ensure user fields are loaded."
        case .javaScriptError(let msg):
            return "NTR script error: \(msg)"
        case .saveFailed(let msg):
            return msg
        case .invalidResponse(let msg):
            return "NTR invalid response: \(msg)"
        }
    }
}

/// WKWebView bridge for WheelSys nonrevenue.aspx create/close (BTSAVE).
@MainActor
final class WheelSysNTRWebViewFetcher: NSObject {

    private static let baseURL = "https://ch.wheelsys.greenmotion.com"
    private static let cookieDomain = "ch.wheelsys.greenmotion.com"
    private static let userAgent =
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 "
        + "(KHTML, like Gecko) Chrome/125.0.0.0 Safari/537.36"

    private var webView: WKWebView?
    private var hostWindow: UIWindow?
    private var navContinuation: CheckedContinuation<Void, Error>?

    func createNonRevenueTicket(_ request: WheelSysNTRCreateRequest) async throws -> WheelSysNTRCreateResult {
        try await loadPage(entityId: nil)
        let user = try await detectLoggedInUser()
        LogManager.shared.info("[WheelSys][NTR][User] detected id=\(user.id) name=\(user.name)")
        LogManager.shared.info(
            "[WheelSys][NTR][Create] plate=\(request.vehicle.plateNo) "
            + "vehicleId=\(request.vehicle.wheelsysVehicleId) userId=\(user.id)"
        )

        let js = Self.makeCreateJS(request: request, user: user)
        let raw = try await runAsyncJS(js)
        let parsed = try Self.decodeOperationResult(from: raw, stage: "create")
        guard parsed.afterSave.success else {
            if let preview = parsed.responsePreview, !preview.isEmpty {
                LogManager.shared.error("[WheelSys][NTR][Create] responsePreview=\(String(preview.prefix(3000)))")
            }
            let msg = Self.ntrErrorMessage(from: parsed.afterSave, fallback: "NTR create failed")
            throw WheelSysNTRFetchError.saveFailed(msg)
        }
        guard let entityId = parsed.afterSave.keyValue else {
            throw WheelSysNTRFetchError.saveFailed("NTR create succeeded but keyValue missing")
        }
        LogManager.shared.info(
            "[WheelSys][NTR][afterSave] success=true keyValue=\(entityId) "
            + "message=\(parsed.afterSave.message ?? "nil")"
        )
        return WheelSysNTRCreateResult(
            entityId: entityId,
            docNo: parsed.afterSave.docNo,
            loggedInUser: user,
            afterSave: parsed.afterSave
        )
    }

    func closeNonRevenueTicket(_ request: WheelSysNTRCloseRequest) async throws -> WheelSysNTRCloseResult {
        try await loadPage(entityId: request.ntrEntityId)
        let user = try await detectLoggedInUser()
        let checkout = try await readCheckoutDateTime()
        let proposed = request.closeDateTime ?? WheelSysZurichDateTime.now()
        let closeDate = WheelSysZurichDateTime.validNTRCloseDate(checkout: checkout.date, proposedClose: proposed)

        LogManager.shared.info("[WheelSys][NTR][User] detected id=\(user.id) name=\(user.name)")
        LogManager.shared.info(
            "[WheelSys][NTR][Close] entityId=\(request.ntrEntityId) "
            + "checkout=\(WheelSysZurichDateTime.formatDate(checkout.date)) \(WheelSysZurichDateTime.formatTime(checkout.date)) "
            + "close=\(WheelSysZurichDateTime.formatDate(closeDate)) \(WheelSysZurichDateTime.formatTime(closeDate)) "
            + "kmTo=\(request.closeKm) fuelTo=\(request.closeFuelEighths) userId=\(user.id)"
        )

        let js = Self.makeCloseJS(
            request: request,
            user: user,
            closeDate: closeDate,
            checkoutKm: checkout.km,
            checkoutFuel: checkout.fuel
        )
        let raw = try await runAsyncJS(js)
        let parsed = try Self.decodeOperationResult(from: raw, stage: "close")
        guard parsed.afterSave.success else {
            if let preview = parsed.responsePreview, !preview.isEmpty {
                LogManager.shared.error("[WheelSys][NTR][Close] responsePreview=\(String(preview.prefix(3000)))")
            }
            let msg = Self.ntrErrorMessage(from: parsed.afterSave, fallback: "NTR close failed")
            throw WheelSysNTRFetchError.saveFailed(msg)
        }
        LogManager.shared.info(
            "[WheelSys][NTR][afterSave] success=true keyValue=\(parsed.afterSave.keyValue ?? request.ntrEntityId) "
            + "message=\(parsed.afterSave.message ?? "nil")"
        )
        return WheelSysNTRCloseResult(
            entityId: request.ntrEntityId,
            loggedInUser: user,
            afterSave: parsed.afterSave,
            milesTravelled: parsed.milesTravelled ?? 0,
            fuelUsed: parsed.fuelUsed ?? 0,
            closeDateTime: closeDate
        )
    }

    func cleanup() {
        navContinuation?.resume(throwing: WheelSysNTRFetchError.pageLoadFailed("cleanup"))
        navContinuation = nil
        webView?.navigationDelegate = nil
        webView = nil
        hostWindow?.isHidden = true
        hostWindow = nil
    }

    // MARK: - Page load

    private func loadPage(entityId: Int?) async throws {
        guard WheelSysCookieCache.isValid else {
            throw WheelSysNTRFetchError.sessionExpired
        }
        let path = entityId.map { "?entityId=\($0)" } ?? ""
        let url = URL(string: "\(Self.baseURL)/ui/manage/master/nonrevenue.aspx\(path)")!

        let wv = makeWebView()
        webView = wv
        attachToHiddenWindow(wv)

        try await injectCookiesAndLoad(wv, url: url)
        try await Task.sleep(nanoseconds: 1_500_000_000)
        try await waitForPanel(on: wv)
    }

    private func waitForPanel(on wv: WKWebView) async throws {
        let probeJS = """
        (function() {
          const html = document.documentElement.innerHTML || '';
          const isLogin = /login\\.aspx/i.test(location.href)
            || (html.includes('Sign in') && !html.includes('nonrevenuePanel'));
          const hasPanel = html.includes('nonrevenuePanel')
            || !!document.querySelector('[id*="nonrevenuePanel"]');
          return JSON.stringify({ isLogin, hasPanel });
        })();
        """
        for attempt in 0..<8 {
            let value = try await evaluateString(probeJS, on: wv)
            if let data = value.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                if json["isLogin"] as? Bool == true {
                    throw WheelSysNTRFetchError.sessionExpired
                }
                if json["hasPanel"] as? Bool == true { return }
            }
            try await Task.sleep(nanoseconds: UInt64(400_000_000 + attempt * 200_000_000))
        }
        throw WheelSysNTRFetchError.panelNotReady
    }

    private struct CheckoutSnapshot {
        let date: Date
        let km: Int
        let fuel: Int
    }

    private func readCheckoutDateTime() async throws -> CheckoutSnapshot {
        let js = """
        (function() {
          function val(id) {
            const el = document.getElementById(id);
            return el ? String(el.value || '').trim() : '';
          }
          function intVal(id) {
            const raw = val(id + '_hidden') || val(id);
            const n = parseInt(String(raw).replace(/[^0-9-]/g, ''), 10);
            return isNaN(n) ? 0 : n;
          }
          return JSON.stringify({
            dateFrom: val('rdDateFrom_text'),
            timeFrom: val('rdTimeFrom_text'),
            kmFrom: intVal('rdKilomFrom'),
            fuelFrom: intVal('rdFuelFrom')
          });
        })();
        """
        let raw = try await evaluateString(js, on: webView!)
        guard let data = raw.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let checkout = WheelSysZurichDateTime.parse(
                dateText: json["dateFrom"] as? String,
                timeText: json["timeFrom"] as? String
              )
        else {
            throw WheelSysNTRFetchError.invalidResponse("Could not parse NTR checkout date/time")
        }
        let km = json["kmFrom"] as? Int ?? Int(String(describing: json["kmFrom"] ?? "0")) ?? 0
        let fuel = json["fuelFrom"] as? Int ?? Int(String(describing: json["fuelFrom"] ?? "0")) ?? 0
        return CheckoutSnapshot(date: checkout, km: km, fuel: fuel)
    }

    private func detectLoggedInUser() async throws -> WheelSysLoggedInUser {
        let raw = try await evaluateString(Self.getLoggedInWheelsysUserJS, on: webView!)
        guard let data = raw.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            throw WheelSysNTRFetchError.userDetectionFailed
        }
        if json["error"] as? String != nil {
            throw WheelSysNTRFetchError.userDetectionFailed
        }
        let id = (json["id"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !id.isEmpty else { throw WheelSysNTRFetchError.userDetectionFailed }
        let name = (json["name"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return WheelSysLoggedInUser(id: id, name: name)
    }

    // MARK: - JS builders

    private static let getLoggedInWheelsysUserJS = """
    (function() {
      function clean(v) { return v == null ? "" : String(v).trim(); }
      function bySelectorValue(selector) {
        const el = document.querySelector(selector);
        return el ? clean(el.value) : "";
      }
      function fromCombo(id) {
        const combo = document.querySelector("#" + id + "_combo");
        if (!combo || !clean(combo.value)) return null;
        const opt = combo.options[combo.selectedIndex];
        return { id: clean(combo.value), name: clean(opt && opt.textContent) };
      }
      function fromNfo() {
        const html = document.documentElement.innerHTML || "";
        const nfoMatch = html.match(/nfo=([^&"'\\\\s]+)/);
        if (!nfoMatch) return null;
        try {
          const decoded = decodeURIComponent(nfoMatch[1]);
          const json = JSON.parse(atob(decoded));
          const id = clean(json.userId || json.UserId || json.uid);
          if (!id) return null;
          const opt =
            document.querySelector('#rdUserFrom_combo option[value="' + id + '"]') ||
            document.querySelector('#rdUserTo_combo option[value="' + id + '"]');
          return { id, name: clean(opt && opt.textContent) || clean(json.userName || json.name) };
        } catch (e) {
          console.warn("[WheelSys][UserDetect] nfo decode failed", e);
          return null;
        }
      }
      const nfoUser = fromNfo();
      if (nfoUser && nfoUser.id) return JSON.stringify(nfoUser);
      const fromUser = fromCombo("rdUserFrom") || fromCombo("rdUserTo");
      if (fromUser && fromUser.id) return JSON.stringify(fromUser);
      const drivenId = bySelectorValue("#DrivenByUser_value");
      const drivenName = bySelectorValue("#DrivenByUser_text");
      if (drivenId) return JSON.stringify({ id: drivenId, name: drivenName });
      const globals = [window.wheels, window.WheelSys, window.pageUser];
      for (const g of globals) {
        if (g && g.userId) {
          const id = clean(g.userId);
          const name = clean(g.userName || g.name || "");
          if (id) return JSON.stringify({ id, name });
        }
      }
      return JSON.stringify({ error: "Could not detect logged-in Wheelsys user." });
    })();
    """

    private static let parseAfterSaveResponseJS = """
    function parseAfterSaveResponse(text, status, responseOk) {
      const preview = text.slice(0, 3000);
      const idx = text.indexOf("wheels.afterSave");
      let afterSave = { success: false };
      let docNo = null;
      if (idx >= 0) {
        const slice = text.slice(idx);
        const braceStart = slice.indexOf("{");
        if (braceStart >= 0) {
          let depth = 0, inStr = false, esc = false, end = -1;
          for (let i = braceStart; i < slice.length; i++) {
            const ch = slice[i];
            if (inStr) {
              if (esc) esc = false;
              else if (ch === "\\\\") esc = true;
              else if (ch === '"') inStr = false;
              continue;
            }
            if (ch === '"') { inStr = true; continue; }
            if (ch === "{") depth++;
            else if (ch === "}") {
              depth--;
              if (depth === 0) { end = i; break; }
            }
          }
          if (end > braceStart) {
            try { afterSave = JSON.parse(slice.slice(braceStart, end + 1)); } catch (_) {}
          }
        }
      }
      const docMatch = text.match(/rdDocno_text[^>]*value="([^"]*)"/i);
      if (docMatch) docNo = docMatch[1];
      const saveOk = afterSave.success === true;
      return {
        success: saveOk && responseOk,
        status,
        afterSave,
        docNo,
        responsePreview: preview
      };
    }
    """

    private static func makeCreateJS(request: WheelSysNTRCreateRequest, user: WheelSysLoggedInUser) -> String {
        let v = request.vehicle
        let startDate = jsString(WheelSysZurichDateTime.formatDate(request.startDateTime))
        let startTime = jsString(WheelSysZurichDateTime.formatTime(request.startDateTime))
        let endDate = jsString(WheelSysZurichDateTime.formatDate(request.plannedEndDateTime))
        let endTime = jsString(WheelSysZurichDateTime.formatTime(request.plannedEndDateTime))
        let kmText = jsString(WheelSysZurichDateTime.formatKmText(v.mileage))
        let fuelText = jsString(WheelSysZurichDateTime.formatFuelText(v.fuelEighths))
        let modelId = jsString(v.modelId ?? "")

        return """
        try {
          const user = { id: \(jsString(user.id)), name: \(jsString(user.name)) };
          const station = \(jsString(request.station));
          const form = document.forms[0];
          if (!form) return JSON.stringify({ success: false, stage: "form", error: "No form" });
          function val(id) {
            const el = document.getElementById(id);
            return el ? String(el.value || "").trim() : "";
          }
          function comboText(id) {
            const combo = document.getElementById(id + "_combo");
            if (!combo) return "";
            const opt = combo.options[combo.selectedIndex];
            return opt ? String(opt.textContent || "").trim() : "";
          }
          const fd = new FormData(form);
          fd.set("ctl00$ctl00$ctl00$coreBody$ScriptManager",
                 "ctl00$ctl00$ctl00$coreBody$contentBody$formFields$nonrevenuePanel|nonrevenuePanel");
          fd.set("__EVENTTARGET", "nonrevenuePanel");
          fd.set("__EVENTARGUMENT", JSON.stringify({ action: "BTSAVE", itemId: "" }));
          fd.set("__ASYNCPOST", "true");
          fd.set("rdStatus", "1");
          fd.set("rdStatusName_text", "Active");
          fd.set("ctl00$ctl00$ctl00$coreBody$contentBody$formFields$hdRtmView", "NonRevenueForm");
          fd.set("ctl00$ctl00$ctl00$coreBody$contentBody$formFields$hdEmail", "no");
          fd.set("ctl00$ctl00$ctl00$coreBody$contentBody$formFields$hdSequenceType", "1");
          fd.set("ctl00$ctl00$ctl00$coreBody$contentBody$formFields$hdStation", station);
          fd.set("rdNonRevenueType_combo", "\(request.type.rawValue)");
          fd.set("drivenbyVal", "1");
          fd.set("DrivenBy", "1");
          fd.set("DrivenByUser_text", user.name);
          fd.set("DrivenByUser_value", user.id);
          fd.set("DrivenByUser_hqe", "true");
          fd.set("rdPlateNo_text", \(jsString(v.plateNo)));
          fd.set("rdPlateNo_value", \(jsString(v.wheelsysVehicleId)));
          fd.set("rdPlateNo_hqe", "true");
          fd.set("rdGroup_text", \(jsString(v.carGroup)));
          const modelId = \(modelId) || val("rdModel_value");
          fd.set("rdModel_text", \(jsString(v.modelName)));
          fd.set("rdModel_value", modelId);
          fd.set("rdModel_hqe", "true");
          fd.set("rdDateFrom_text", \(startDate));
          fd.set("rdTimeFrom_text", \(startTime));
          fd.set("rdStationFrom_combo", station);
          fd.set("rdLocationFrom_combo", val("rdLocationFrom_combo") || station);
          fd.set("rdLocationFrom_text", val("rdLocationFrom_text") || comboText("rdLocationFrom") || station);
          fd.set("rdRemarksFrom_text", val("rdRemarksFrom_text"));
          fd.set("rdKilomFrom_text", \(kmText));
          fd.set("rdKilomFrom_hidden", "\(max(0, v.mileage))");
          fd.set("rdFuelFrom_text", \(fuelText));
          fd.set("rdFuelFrom_hidden", "\(max(0, v.fuelEighths))");
          fd.set("rdUserFrom_combo", user.id);
          fd.set("rdUserFrom_text", user.name);
          fd.set("rdDateTo_text", \(endDate));
          fd.set("rdTimeTo_text", \(endTime));
          fd.set("rdStationTo_combo", station);
          fd.set("rdLocationTo_combo", val("rdLocationTo_combo") || station);
          fd.set("rdLocationTo_text", val("rdLocationTo_text") || comboText("rdLocationTo") || station);
          fd.set("rdRemarksTo_text", val("rdRemarksTo_text"));
          fd.set("rdKilomTo_text", "0");
          fd.set("rdKilomTo_hidden", "0");
          fd.set("rdFuelTo_text", "0 /8");
          fd.set("rdFuelTo_hidden", "0");
          const cacheKey = fd.get("cachekey");
          if (!cacheKey || String(cacheKey).trim().length === 0) {
            return JSON.stringify({ success: false, stage: "cachekey", error: "cachekey missing" });
          }
          const body = new URLSearchParams();
          for (const [key, value] of fd.entries()) {
            body.append(key, value == null ? "" : String(value));
          }
          const response = await fetch("/ui/manage/master/nonrevenue.aspx", {
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
          return JSON.stringify(parseAfterSaveResponse(text, response.status, response.ok));
        } catch (e) {
          return JSON.stringify({ success: false, stage: "exception", error: String(e) });
        }

        \(Self.parseAfterSaveResponseJS)
        """
    }

    private static func makeCloseJS(
        request: WheelSysNTRCloseRequest,
        user: WheelSysLoggedInUser,
        closeDate: Date,
        checkoutKm: Int,
        checkoutFuel: Int
    ) -> String {
        let closeDateText = jsString(WheelSysZurichDateTime.formatDate(closeDate))
        let closeTimeText = jsString(WheelSysZurichDateTime.formatTime(closeDate))
        let kmToText = jsString(WheelSysZurichDateTime.formatKmText(request.closeKm))
        let fuelToText = jsString(WheelSysZurichDateTime.formatFuelText(request.closeFuelEighths))
        let miles = max(0, request.closeKm - checkoutKm)
        let fuelUsed = max(0, checkoutFuel - request.closeFuelEighths)
        let fuelUsedText = jsString(WheelSysZurichDateTime.formatFuelUsedText(fuelUsed))

        return """
        try {
          const entityId = \(request.ntrEntityId);
          const user = { id: \(jsString(user.id)), name: \(jsString(user.name)) };
          const station = \(jsString(request.station));
          const form = document.forms[0];
          if (!form) return JSON.stringify({ success: false, stage: "form", error: "No form" });
          function val(id) {
            const el = document.getElementById(id);
            return el ? String(el.value || "").trim() : "";
          }
          function comboText(id) {
            const combo = document.getElementById(id + "_combo");
            if (!combo) return "";
            const opt = combo.options[combo.selectedIndex];
            return opt ? String(opt.textContent || "").trim() : "";
          }
          const fd = new FormData(form);
          fd.set("ctl00$ctl00$ctl00$coreBody$ScriptManager",
                 "ctl00$ctl00$ctl00$coreBody$contentBody$formFields$nonrevenuePanel|nonrevenuePanel");
          fd.set("__EVENTTARGET", "nonrevenuePanel");
          fd.set("__EVENTARGUMENT", JSON.stringify({ action: "BTSAVE", itemId: String(entityId) }));
          fd.set("__ASYNCPOST", "true");
          fd.set("rdStatus", "3");
          fd.set("rdStatusName_text", "Closed");
          fd.set("rdDateTo_text", \(closeDateText));
          fd.set("rdTimeTo_text", \(closeTimeText));
          fd.set("rdStationTo_combo", station);
          fd.set("rdLocationTo_combo", val("rdLocationTo_combo") || station);
          fd.set("rdLocationTo_text", val("rdLocationTo_text") || comboText("rdLocationTo") || station);
          fd.set("rdRemarksTo_text", val("rdRemarksTo_text"));
          fd.set("rdKilomTo_text", \(kmToText));
          fd.set("rdKilomTo_hidden", "\(max(0, request.closeKm))");
          fd.set("rdFuelTo_text", \(fuelToText));
          fd.set("rdFuelTo_hidden", "\(max(0, request.closeFuelEighths))");
          fd.set("rdUserTo_combo", user.id);
          fd.set("rdUserTo_text", user.name);
          fd.set("milesTravelled_text", "\(miles)");
          fd.set("milesTravelled_hidden", "\(miles)");
          fd.set("fuelUsed_text", \(fuelUsedText));
          fd.set("fuelUsed_hidden", "\(fuelUsed)");
          const body = new URLSearchParams();
          for (const [key, value] of fd.entries()) {
            body.append(key, value == null ? "" : String(value));
          }
          const response = await fetch("/ui/manage/master/nonrevenue.aspx?entityId=" + entityId, {
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
          const parsed = parseAfterSaveResponse(text, response.status, response.ok);
          parsed.milesTravelled = \(miles);
          parsed.fuelUsed = \(fuelUsed);
          return JSON.stringify(parsed);
        } catch (e) {
          return JSON.stringify({ success: false, stage: "exception", error: String(e) });
        }

        \(Self.parseAfterSaveResponseJS)
        """
    }

    // MARK: - Decode

    /// WheelSys may return ProcException as a plain string or `{ Message: "RENTAL OVERLAP", ... }`.
    private enum WheelSysProcExceptionField: Decodable {
        case text(String)
        case detail(WheelSysValidationException)

        struct WheelSysValidationException: Decodable {
            let Message: String?
            let message: String?
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let text = try? container.decode(String.self) {
                self = .text(text)
                return
            }
            if let detail = try? container.decode(WheelSysValidationException.self) {
                self = .detail(detail)
                return
            }
            self = .text("")
        }

        var resolvedMessage: String? {
            switch self {
            case .text(let raw):
                let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmed.isEmpty ? nil : trimmed
            case .detail(let detail):
                let msg = (detail.Message ?? detail.message ?? "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                return msg.isEmpty ? nil : msg
            }
        }
    }

    private struct OperationJSResult: Decodable {
        let success: Bool?
        let stage: String?
        let error: String?
        let afterSave: AfterSavePayload?
        let docNo: String?
        let milesTravelled: Int?
        let fuelUsed: Int?
        let responsePreview: String?

        struct AfterSavePayload: Decodable {
            let success: Bool?
            let keyValue: Int?
            let message: String?
            let mustReloadEntity: Bool?
            let procException: WheelSysProcExceptionField?
            let ProcException: WheelSysProcExceptionField?

            enum CodingKeys: String, CodingKey {
                case success, keyValue, message, mustReloadEntity
                case procException = "procException"
                case ProcException = "ProcException"
            }

            var resolvedProcException: String? {
                procException?.resolvedMessage ?? ProcException?.resolvedMessage
            }
        }
    }

    private struct DecodedOperationResult {
        let afterSave: WheelSysAfterSaveResult
        let milesTravelled: Int?
        let fuelUsed: Int?
        let responsePreview: String?
    }

    private static func ntrErrorMessage(from afterSave: WheelSysAfterSaveResult, fallback: String) -> String {
        let raw: String = {
            if let msg = afterSave.message?.trimmingCharacters(in: .whitespacesAndNewlines), !msg.isEmpty {
                return msg
            }
            if let ex = afterSave.procException?.trimmingCharacters(in: .whitespacesAndNewlines), !ex.isEmpty {
                return ex
            }
            return fallback
        }()
        return WheelSysUserFacingError.message(forRaw: raw)
    }

    private static func userFacingNTRMessage(_ raw: String) -> String {
        WheelSysUserFacingError.message(forRaw: raw)
    }

    private static func decodeOperationResult(from value: Any?, stage: String) throws -> DecodedOperationResult {
        let jsonStr: String
        if let s = value as? String { jsonStr = s }
        else if let dict = value as? [String: Any],
                let data = try? JSONSerialization.data(withJSONObject: dict),
                let s = String(data: data, encoding: .utf8) { jsonStr = s }
        else {
            throw WheelSysNTRFetchError.invalidResponse("\(stage) JS returned unexpected type")
        }

        guard let data = jsonStr.data(using: .utf8) else {
            throw WheelSysNTRFetchError.invalidResponse("\(stage) JSON encode failed")
        }

        let parsed: OperationJSResult
        if let decoded = try? JSONDecoder().decode(OperationJSResult.self, from: data) {
            parsed = decoded
        } else if let fallback = parseOperationResultFallback(from: data, stage: stage) {
            parsed = fallback
        } else {
            LogManager.shared.error("[WheelSys][NTR][\(stage)] JSON decode failed preview=\(String(jsonStr.prefix(500)))")
            throw WheelSysNTRFetchError.invalidResponse("\(stage) JSON decode failed")
        }

        if let err = parsed.error, !err.isEmpty {
            throw WheelSysNTRFetchError.javaScriptError(err)
        }

        let payload = parsed.afterSave
        let afterSave = WheelSysAfterSaveResult(
            success: payload?.success == true || parsed.success == true,
            keyValue: payload?.keyValue,
            message: payload?.message,
            procException: payload?.resolvedProcException,
            mustReloadEntity: payload?.mustReloadEntity,
            docNo: parsed.docNo
        )
        return DecodedOperationResult(
            afterSave: afterSave,
            milesTravelled: parsed.milesTravelled,
            fuelUsed: parsed.fuelUsed,
            responsePreview: parsed.responsePreview
        )
    }

    private static func parseOperationResultFallback(from data: Data, stage: String) -> OperationJSResult? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        let afterSaveDict = root["afterSave"] as? [String: Any]
        let procMessage = extractProcExceptionMessage(from: afterSaveDict)
        let message = stringValue(afterSaveDict?["message"]) ?? procMessage
        let afterSave = OperationJSResult.AfterSavePayload(
            success: afterSaveDict?["success"] as? Bool,
            keyValue: intValue(afterSaveDict?["keyValue"]),
            message: message,
            mustReloadEntity: afterSaveDict?["mustReloadEntity"] as? Bool,
            procException: procMessage.map { .text($0) },
            ProcException: procMessage.map { .text($0) }
        )
        return OperationJSResult(
            success: root["success"] as? Bool,
            stage: stringValue(root["stage"]),
            error: stringValue(root["error"]),
            afterSave: afterSave,
            docNo: stringValue(root["docNo"]),
            milesTravelled: intValue(root["milesTravelled"]),
            fuelUsed: intValue(root["fuelUsed"]),
            responsePreview: stringValue(root["responsePreview"])
        )
    }

    private static func extractProcExceptionMessage(from afterSave: [String: Any]?) -> String? {
        guard let afterSave else { return nil }
        for key in ["ProcException", "procException"] {
            if let text = afterSave[key] as? String {
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { return trimmed }
            }
            if let obj = afterSave[key] as? [String: Any] {
                let msg = stringValue(obj["Message"]) ?? stringValue(obj["message"])
                if let msg, !msg.isEmpty { return msg }
            }
        }
        return nil
    }

    private static func stringValue(_ value: Any?) -> String? {
        guard let value else { return nil }
        let text = String(describing: value).trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }

    private static func intValue(_ value: Any?) -> Int? {
        if let n = value as? Int { return n }
        if let n = value as? NSNumber { return n.intValue }
        if let s = value as? String { return Int(s) }
        return nil
    }

    // MARK: - WebView helpers

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

    private func injectCookiesAndLoad(_ wv: WKWebView, url: URL) async throws {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            injectCachedCookies(into: wv.configuration.websiteDataStore.httpCookieStore) {
                self.navContinuation = cont
                wv.load(URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData))
            }
        }
    }

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
                .name: name, .value: value, .domain: Self.cookieDomain, .path: "/",
            ]
            if name.hasPrefix("__Secure-") { properties[.secure] = "TRUE" }
            if let cookie = HTTPCookie(properties: properties) { cookies.append(cookie) }
        }
        guard !cookies.isEmpty else { completion(); return }
        let group = DispatchGroup()
        for cookie in cookies {
            group.enter()
            store.setCookie(cookie) { group.leave() }
        }
        group.notify(queue: .main, execute: completion)
    }

    private func runAsyncJS(_ js: String) async throws -> Any? {
        guard let wv = webView else { throw WheelSysNTRFetchError.pageLoadFailed("no webview") }
        return try await withCheckedThrowingContinuation { cont in
            wv.callAsyncJavaScript(js, arguments: [:], in: nil, in: .page) { result in
                Task { @MainActor in
                    switch result {
                    case .success(let value): cont.resume(returning: value)
                    case .failure(let error):
                        cont.resume(throwing: WheelSysNTRFetchError.javaScriptError(error.localizedDescription))
                    }
                }
            }
        }
    }

    private func evaluateString(_ js: String, on wv: WKWebView) async throws -> String {
        try await withCheckedThrowingContinuation { cont in
            wv.evaluateJavaScript(js) { value, error in
                Task { @MainActor in
                    if let error {
                        cont.resume(throwing: WheelSysNTRFetchError.javaScriptError(error.localizedDescription))
                        return
                    }
                    if let s = value as? String {
                        cont.resume(returning: s)
                    } else {
                        cont.resume(throwing: WheelSysNTRFetchError.invalidResponse("evaluate returned non-string"))
                    }
                }
            }
        }
    }

    private static func jsString(_ value: String) -> String {
        let escaped = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "")
        return "\"\(escaped)\""
    }
}

extension WheelSysNTRWebViewFetcher: WKNavigationDelegate {
    nonisolated func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        Task { @MainActor in
            self.navContinuation?.resume()
            self.navContinuation = nil
        }
    }

    nonisolated func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        Task { @MainActor in
            self.navContinuation?.resume(throwing: WheelSysNTRFetchError.pageLoadFailed(error.localizedDescription))
            self.navContinuation = nil
        }
    }

    nonisolated func webView(
        _ webView: WKWebView,
        didFailProvisionalNavigation navigation: WKNavigation!,
        withError error: Error
    ) {
        Task { @MainActor in
            self.navContinuation?.resume(throwing: WheelSysNTRFetchError.pageLoadFailed(error.localizedDescription))
            self.navContinuation = nil
        }
    }
}
