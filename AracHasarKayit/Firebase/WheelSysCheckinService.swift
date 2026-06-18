import Foundation
import FirebaseAuth
import FirebaseFunctions
import WebKit

// MARK: - Errors

enum WheelSysCheckinServiceError: LocalizedError {
    case notAuthenticated
    case operationFailed(String)

    var errorDescription: String? {
        switch self {
        case .notAuthenticated: return "You must be signed in.".localized
        case .operationFailed(let msg): return msg
        }
    }
}

// MARK: - Models

struct WheelSysRentalSearchHit: Identifiable, Hashable {
    let id: String
    let entityId: String?
    let resNo: String
    let plate: String
    let customer: String
    let km: Int?
    let source: String

    var displayTitle: String {
        if let e = entityId, !e.isEmpty { return "\(resNo) · #\(e)" }
        return resNo
    }

    var hasEntityId: Bool { entityId != nil && !(entityId!.isEmpty) }
}

struct WheelSysRentalPreview {
    let entityId: String
    let vehicleEntityId: String
    let resNo: String
    let raNo: String
    let plate: String
    let mileageFrom: Int
    let mileageTo: Int
    let fuelFrom: Int
    let fuelTo: Int
    let checkoutMileageText: String
    let checkinMileageText: String
    let vehicleMasterMileage: Int?
    let vehicleMasterFuel: Int?
    let milesDriven: Int
    let checkInUserId: String
    let checkInUserOptions: [(id: String, name: String)]
    let dateTo: String
    let timeTo: String
    let insurance: WheelSysInsuranceSummary?
    let rentalNotes: [WheelSysEntityNote]
    let vehicleNotes: [WheelSysEntityNote]
}

struct WheelSysAssignmentResult {
    let success: Bool
    let message: String
    let bookingEntityId: Int?
    let carId: Int?
    let plateNo: String?
}

struct WheelSysBookingPreview {
    let entityId: Int
    /// Real RES number, e.g. "RES-17694" (rdDispDocno_text / displaydocno).
    let resNo: String
    /// Agent/external confirmation number, e.g. "JIG(A)-6813462-67939" (rdConfno_text).
    let confirmationNo: String?
    /// IRN from booking page, e.g. "8075732".
    let irn: String?
    let carGroup: String
    let isAssigned: Bool
    let insurance: WheelSysInsuranceSummary?
    let driverName: String?
}

struct ResolvedBookingContext {
    let bookingEntityId: Int
    let cacheKey: String
    let resNo: String
    let resolvedFrom: String
    let correlationId: String
}

/// Full result from wheelsysCheckinUpdate callable.
struct WheelSysCheckinResult {
    /// Firebase callable returned success.
    let success: Bool
    /// Human-readable message (may be WheelSys error text).
    let message: String
    let mileageFrom: Int?
    let mileageTo: Int?
    let milesDriven: Int?
    let fuelTo: Int?
    /// Mileage verified by re-fetching after save. nil = verify step skipped or failed.
    let verifiedMileageTo: Int?
    let vehicleMasterSynced: Bool
    let vehicleEntityId: String?
    let vehicleFuelVerified: Int?
    let noteErrors: [String]
}

struct WheelSysSessionStatus {
    let hasSession: Bool
    let isValid: Bool
    let fleetChartValid: Bool
    let station: String
    let expiresAtMs: Int64?
}

struct WheelSysFleetEvent: Identifiable, Hashable {
    let eventId: String
    let vehicleId: String
    let domain: Int
    let type: String
    let status: String
    let rentalEntityId: Int?
    let recordId: String
    let start: String
    let end: String
    let stationFrom: String
    let initialCarGroup: String
    let driverName: String
    let startTimeText: String
    let endTimeText: String

    var id: String { eventId.isEmpty ? "\(vehicleId)-\(recordId)-\(start)" : eventId }
}

struct WheelSysFleetVehicle: Identifiable, Hashable {
    let vehicleId: String
    let group: String
    let plate: String
    let model: String
    let station: String
    let mileage: Int
    let color: String?
    let fuelType: String
    let status: String
    let rawCssClass: String
    let events: [WheelSysFleetEvent]

    var id: String { vehicleId }
}

struct WheelSysFleetChartResult {
    let station: String
    let startDate: String
    let endDate: String
    let vehiclesCount: Int
    let eventsCount: Int
    let rentalEventsCount: Int
    let vehicles: [WheelSysFleetVehicle]
    let allEvents: [WheelSysFleetEvent]
}

// MARK: - Service

enum WheelSysCheckinService {
    private static let functions = Functions.functions(region: "europe-west6")

    // MARK: Search

    static func searchByRes(franchiseId: String, resQuery: String) async throws -> [WheelSysRentalSearchHit] {
        guard Auth.auth().currentUser != nil else { throw WheelSysCheckinServiceError.notAuthenticated }
        let q = resQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return [] }

        let result = try await functions.httpsCallable("wheelsysSearchRentalByRes").call([
            "franchiseId": franchiseId.uppercased(),
            "resQuery": q,
            "station": "ZRH",
        ])
        guard let data = result.data as? [String: Any] else { return [] }

        var hits: [WheelSysRentalSearchHit] = []

        if let local = data["localExits"] as? [[String: Any]] {
            for row in local {
                let res = string(row["resNo"])
                let exitId = string(row["exitId"])
                hits.append(WheelSysRentalSearchHit(
                    id: "exit-\(exitId)-\(res)",
                    entityId: nil,
                    resNo: res,
                    plate: string(row["plate"]),
                    customer: string(row["customer"]),
                    km: int(row["km"]),
                    source: "vehicle_sentinel"
                ))
            }
        }

        if let cached = data["cached"] as? [[String: Any]] {
            for row in cached {
                let entityId = string(row["entityId"])
                hits.append(WheelSysRentalSearchHit(
                    id: "cache-\(entityId)-\(string(row["resNo"]))",
                    entityId: entityId.isEmpty ? nil : entityId,
                    resNo: string(row["resNo"]),
                    plate: string(row["plateNo"]),
                    customer: "",
                    km: int(row["mileageFrom"]),
                    source: "cache"
                ))
            }
        }

        if let ws = data["wheelsysHits"] as? [[String: Any]] {
            for row in ws {
                let entityId = string(row["entityId"])
                let res = string(row["resNo"])
                hits.append(WheelSysRentalSearchHit(
                    id: "ws-\(entityId)-\(res)",
                    entityId: entityId.isEmpty ? nil : entityId,
                    resNo: res,
                    plate: "",
                    customer: "",
                    km: nil,
                    source: "wheelsys"
                ))
            }
        }

        var seen = Set<String>()
        return dedupeSearchHits(
            hits
                .sorted {
                    let scoreA = ($0.hasEntityId ? 4 : 0) + ($0.source == "cache" ? 2 : 0)
                    let scoreB = ($1.hasEntityId ? 4 : 0) + ($1.source == "cache" ? 2 : 0)
                    return scoreA > scoreB
                }
                .filter { hit in
                    let key = "\(hit.resNo)|\(hit.entityId ?? "")|\(hit.plate)"
                    if seen.contains(key) { return false }
                    seen.insert(key)
                    return true
                }
        )
    }

    /// One row per RES — merge cache (entityId) with Vehicle Sentinel (plate/customer).
    private static func dedupeSearchHits(_ hits: [WheelSysRentalSearchHit]) -> [WheelSysRentalSearchHit] {
        var byRes: [String: WheelSysRentalSearchHit] = [:]
        for hit in hits {
            let key = resSearchKey(hit.resNo)
            if let existing = byRes[key] {
                byRes[key] = mergeSearchHits(existing, hit)
            } else {
                byRes[key] = hit
            }
        }
        return byRes.values.sorted {
            if $0.hasEntityId != $1.hasEntityId { return $0.hasEntityId }
            return $0.resNo < $1.resNo
        }
    }

    private static func resSearchKey(_ resNo: String) -> String {
        let digits = resNo.replacingOccurrences(of: "[^0-9]", with: "", options: .regularExpression)
        if digits.isEmpty { return resNo.uppercased() }
        return "RES-\(digits)"
    }

    private static func mergeSearchHits(
        _ a: WheelSysRentalSearchHit,
        _ b: WheelSysRentalSearchHit
    ) -> WheelSysRentalSearchHit {
        let primary = a.hasEntityId ? a : (b.hasEntityId ? b : a)
        let other = primary.id == a.id ? b : a
        let entityId = primary.entityId ?? other.entityId
        let resNo = primary.resNo.isEmpty ? other.resNo : primary.resNo
        let plate = normalizePlate(primary.plate).isEmpty ? other.plate : primary.plate
        return WheelSysRentalSearchHit(
            id: entityId.map { "merged-\($0)-\(resSearchKey(resNo))" } ?? primary.id,
            entityId: entityId,
            resNo: resNo,
            plate: plate,
            customer: primary.customer.isEmpty ? other.customer : primary.customer,
            km: primary.km ?? other.km,
            source: primary.hasEntityId ? primary.source : other.source
        )
    }

    private static func normalizePlate(_ plate: String) -> String {
        WheelSysPlateNormalizer.canonical(plate)
    }

    // MARK: Session

    static func sessionStatus(franchiseId: String) async throws -> WheelSysSessionStatus {
        guard Auth.auth().currentUser != nil else { throw WheelSysCheckinServiceError.notAuthenticated }
        let result = try await functions.httpsCallable("wheelsysSessionStatus").call([
            "franchiseId": franchiseId.uppercased(),
            "station": "ZRH",
        ])
        guard let data = result.data as? [String: Any] else {
            return WheelSysSessionStatus(
                hasSession: false, isValid: false, fleetChartValid: false,
                station: "ZRH", expiresAtMs: nil
            )
        }
        let expires: Int64? = {
            if let n = data["expiresAtMs"] as? NSNumber { return n.int64Value }
            if let n = data["expiresAtMs"] as? Int { return Int64(n) }
            return nil
        }()
        return WheelSysSessionStatus(
            hasSession: data["hasSession"] as? Bool ?? false,
            isValid: data["isValid"] as? Bool ?? false,
            fleetChartValid: data["fleetChartValid"] as? Bool ?? false,
            station: string(data["station"]).isEmpty ? "ZRH" : string(data["station"]),
            expiresAtMs: expires
        )
    }

    static func saveSessionCookie(franchiseId: String, sessionCookie: String) async throws {
        guard Auth.auth().currentUser != nil else { throw WheelSysCheckinServiceError.notAuthenticated }
        guard let authCookie = WheelSysCookieCache.authOnly(from: sessionCookie) else {
            throw WheelSysCheckinServiceError.operationFailed(
                "WheelSys session cookie is incomplete.".localized
            )
        }
        WheelSysCookieCache.set(authCookie)
        _ = try await functions.httpsCallable("wheelsysSaveSession").call([
            "franchiseId": franchiseId.uppercased(),
            "sessionCookie": authCookie,
            "station": "ZRH",
            "ttlHours": 24,
        ])
    }

    // MARK: WKWebView Cookie Helper

    /// Read live WheelSys session cookies from the in-app WKWebView.
    /// Must be called from any thread; internally marshals to main queue.
    /// Returns nil if required cookies are absent.
    @MainActor
    static func getWheelSysCookieString() async -> String? {
        // Prefer in-memory cache from last login capture (most reliable after sheet closes).
        if WheelSysCookieCache.isValid, let cached = WheelSysCookieCache.lastCookie {
            print("[WheelSys] using cached login cookie")
            return WheelSysCookieCache.authOnly(from: cached) ?? cached
        }

        return await withCheckedContinuation { continuation in
            WKWebsiteDataStore.default().httpCookieStore.getAllCookies { cookies in
                let wheelsysCookies = cookies.filter {
                    $0.domain.contains("wheelsys.greenmotion.com")
                }
                var ws = ""
                var sid = ""
                for cookie in wheelsysCookies {
                    if cookie.name == ".wheelsys" { ws = cookie.value }
                    if cookie.name == "__Secure-SID" { sid = cookie.value }
                }
                guard !ws.isEmpty, !sid.isEmpty else {
                    continuation.resume(returning: nil)
                    return
                }
                let cookieString = WheelSysCookieCache.buildAuthCookie(wheelsys: ws, secureSID: sid)
                WheelSysCookieCache.logPresence(cookieString, label: "wkwebview read")
                continuation.resume(returning: cookieString)
            }
        }
    }

    /// Returns true if cookie string has both required WheelSys session tokens.
    static func isValidWheelSysCookie(_ cookie: String?) -> Bool {
        guard let c = cookie, !c.isEmpty else { return false }
        return c.contains(".wheelsys=") && c.contains("__Secure-SID=")
    }

    // MARK: Fleet Chart — WebView JS fetch

    /// Fetch fleet data by running `fetch()` inside the authenticated WKWebView context.
    /// Backend proxy approach fails because WheelSys binds sessions to the originating IP.
    static func loadFleetChart(
        franchiseId: String,
        station: String = "ZRH",
        startDate: String? = nil,
        endDate: String? = nil
    ) async throws -> WheelSysFleetChartResult {
        guard Auth.auth().currentUser != nil else { throw WheelSysCheckinServiceError.notAuthenticated }

        let cid = WheelSysDebug.newCorrelationId()
        WheelSysDebug.log("Fleet", "loadFleetChart franchise=\(franchiseId) station=\(station)", cid: cid)
        let raw = try await WheelSysFleetWebViewFetcher.fetch(station: station.uppercased())
        let parsed = try parseFleetWebViewResponse(raw, station: station.uppercased())
        WheelSysDebug.log("Fleet", "parsed vehicles=\(parsed.vehiclesCount) events=\(parsed.eventsCount) rentals=\(parsed.rentalEventsCount)", cid: cid)
        return parsed
    }

    // MARK: Availability — WebView JS fetch

    static func loadAvailability(
        franchiseId: String,
        station: String = "ZRH",
        dateFromISO: String = "2026-06-11T00:00:00.000Z",
        dateToISO: String = "2026-07-19T23:59:59.000Z",
        metric: String = "available"
    ) async throws -> WheelSysAvailabilityResult {
        guard Auth.auth().currentUser != nil else { throw WheelSysCheckinServiceError.notAuthenticated }

        let raw = try await WheelSysAvailabilityWebViewFetcher.fetch(
            station: station.uppercased(),
            dateFrom: dateFromISO,
            dateTo: dateToISO
        )
        return try parseAvailabilityWebViewResponse(
            raw,
            station: station.uppercased(),
            dateFromISO: dateFromISO,
            dateToISO: dateToISO,
            metric: metric
        )
    }

    private static func parseAvailabilityWebViewResponse(
        _ raw: String,
        station: String,
        dateFromISO: String,
        dateToISO: String,
        metric: String
    ) throws -> WheelSysAvailabilityResult {
        guard !raw.isEmpty,
              let data = raw.data(using: .utf8),
              let wrapper = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            throw WheelSysAvailabilityFetchError.parseFailure("wrapper JSON invalid")
        }

        let step = wrapper["step"] as? String ?? ""
        guard wrapper["ok"] as? Bool == true, step == "Success" else {
            let preview = (wrapper["cacheTextPreview"] as? String)
                ?? (wrapper["getDataTextPreview"] as? String)
                ?? step
            let status = (wrapper["cacheStatus"] as? NSNumber)?.intValue
                ?? (wrapper["getDataStatus"] as? NSNumber)?.intValue ?? 0
            if status == 401 || step == "LoginRequired" {
                throw WheelSysAvailabilityFetchError.sessionExpired
            }
            throw WheelSysAvailabilityFetchError.stepFailed(step, status, preview)
        }

        let cacheKey = wrapper["cacheKey"] as? String ?? ""
        guard !cacheKey.isEmpty else {
            throw WheelSysAvailabilityFetchError.parseFailure("cacheKey missing")
        }

        guard let rawRows = wrapper["rows"] as? [[String: Any]] else {
            throw WheelSysAvailabilityFetchError.parseFailure("rows array missing")
        }

        let rows = rawRows.compactMap { WheelSysAvailabilityHourKey.parseRow($0) }
        let readyAttempt = (wrapper["readyAttempt"] as? NSNumber)?.intValue
        print("[WheelSysAvailabilityWebView] parsed rows count=\(rows.count)")
        if let first = rows.first {
            print("[WheelSysAvailabilityWebView] firstRowHourKeysCount=\(first.hourKeyCount)")
        }

        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let dateFrom = iso.date(from: dateFromISO) ?? Date()
        let dateTo = iso.date(from: dateToISO) ?? dateFrom

        return WheelSysAvailabilityResult(
            cacheKey: cacheKey,
            metric: metric,
            station: station,
            dateFrom: dateFrom,
            dateTo: dateTo,
            readyAttempt: readyAttempt,
            rows: rows
        )
    }

    /// Resolve the WheelSys RentalTable_Id for a given plate using fleet data.
    /// Used to ensure check-in targets the correct rental entity.
    static func findRentalEntityId(in fleet: WheelSysFleetChartResult, for plate: String) -> Int? {
        let norm = normalizePlateForMatch(plate)
        guard !norm.isEmpty else { return nil }

        guard let vehicle = fleet.vehicles.first(where: { normalizePlateForMatch($0.plate) == norm }) else {
            print("[WheelSysFleetWebView] no vehicle matched plate=\(norm)")
            return nil
        }

        let active = vehicle.events.first { $0.type == "rental" && $0.status == "active" && $0.rentalEntityId != nil }
        let any    = vehicle.events.first { $0.type == "rental" && $0.rentalEntityId != nil }
        let match  = active ?? any
        let id     = match?.rentalEntityId
        print("[WheelSysFleetWebView] matched plate=\(norm) vehicleId=\(vehicle.vehicleId) rentalEntityId=\(id.map(String.init) ?? "nil") eventStatus=\(match?.status ?? "none")")
        return id
    }

    // MARK: Fleet parsing

    private static func parseFleetWebViewResponse(
        _ raw: String, station: String
    ) throws -> WheelSysFleetChartResult {
        guard !raw.isEmpty,
              let outerData = raw.data(using: .utf8),
              let outer = try? JSONSerialization.jsonObject(with: outerData) as? [String: Any]
        else {
            throw WheelSysFleetFetchError.parseFailure("outer JSON invalid")
        }

        if let reason = outer["reason"] as? String, reason == "LOGIN_REQUIRED" {
            throw WheelSysFleetFetchError.sessionExpired
        }

        if let err = outer["error"] as? String, !err.isEmpty {
            throw WheelSysFleetFetchError.parseFailure("JS: \(err)")
        }

        let status  = (outer["status"] as? NSNumber)?.intValue ?? 0
        let bodyStr = (outer["body"] as? String)
            ?? (outer["responseText"] as? String)
            ?? ""

        guard status == 200 else {
            let preview = String(bodyStr.prefix(500))
            print("[WheelSysFleetWebView] HTTP status=\(status)")
            print("[WheelSysFleetWebView] preview=\(preview)")
            if preview.lowercased().contains("login") || preview.lowercased().contains("sign in") {
                throw WheelSysFleetFetchError.sessionExpired
            }
            throw WheelSysFleetFetchError.httpError(status, preview)
        }

        guard let bodyData = bodyStr.data(using: .utf8),
              let bodyObj  = try? JSONSerialization.jsonObject(with: bodyData) as? [String: Any],
              let d        = bodyObj["d"] as? [String: Any]
        else {
            throw WheelSysFleetFetchError.parseFailure("body.d missing")
        }

        let dSuccess = d["success"] as? Bool ?? false
        let dMessage = d["message"] as? String ?? ""
        print("[WheelSysFleetWebView] outer d success=\(dSuccess)")

        guard dSuccess else {
            if dMessage.lowercased().contains("session") || dMessage.lowercased().contains("login") {
                throw WheelSysFleetFetchError.sessionExpired
            }
            throw WheelSysFleetFetchError.parseFailure("d.success=false: \(dMessage)")
        }

        let dataStr = d["data"] as? String ?? ""
        guard !dataStr.isEmpty,
              let innerData = dataStr.data(using: .utf8),
              let inner = try? JSONSerialization.jsonObject(with: innerData) as? [String: Any]
        else {
            throw WheelSysFleetFetchError.parseFailure("d.data parse failed")
        }

        let rawResources = inner["resources"] as? [[String: Any]] ?? []
        let rawEvents    = inner["events"]    as? [[String: Any]] ?? []
        print("[WheelSysFleetWebView] parsed resources count=\(rawResources.count)")
        print("[WheelSysFleetWebView] parsed events count=\(rawEvents.count)")

        return buildFleetResult(resources: rawResources, events: rawEvents, station: station)
    }

    private static func buildFleetResult(
        resources: [[String: Any]],
        events: [[String: Any]],
        station: String
    ) -> WheelSysFleetChartResult {
        let normEvents = events.compactMap { normalizeRawEvent($0) }

        // Compute start/end date strings for display (today → +20 days)
        let today     = Date()
        let endDate   = Calendar.current.date(byAdding: .day, value: 20, to: today) ?? today
        let fmt       = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        let startDateStr = fmt.string(from: today)
        let endDateStr   = fmt.string(from: endDate)

        var vehicles: [WheelSysFleetVehicle] = []
        for group in resources {
            let groupCode = (group["name"] as? String).flatMap { $0.isEmpty ? nil : $0 }
                ?? (group["groupName"] as? String) ?? ""
            let children = group["children"] as? [[String: Any]] ?? []
            for child in children {
                let vehicleId = string(child["id"])
                guard !vehicleId.isEmpty, !vehicleId.hasSuffix("_grp") else { continue }
                let cols     = child["columns"] as? [[String: Any]] ?? []
                let cssClass = string(child["cssClass"])
                let plate    = cleanFleetPlate(fleetColHtml(cols, order: 2))
                let model    = cleanFleetCell(fleetColHtml(cols, order: 3))
                let vStation = cleanFleetCell(fleetColHtml(cols, order: 4))
                let mileage  = fleetParseMileage(cleanFleetCell(fleetColHtml(cols, order: 5)))
                let (color, fuelType) = fleetParseFuelColor(cleanFleetCell(fleetColHtml(cols, order: 9)))
                let vEvents  = normEvents.filter { $0.vehicleId == vehicleId }
                let hasActive = vEvents.contains { $0.type == "rental" && $0.status == "active" }
                let status   = hasActive ? "on_rental" : vehicleStatusFromClass(cssClass)

                vehicles.append(WheelSysFleetVehicle(
                    vehicleId: vehicleId,
                    group: groupCode,
                    plate: plate,
                    model: model,
                    station: vStation.isEmpty ? station : vStation,
                    mileage: mileage,
                    color: color.isEmpty ? nil : color,
                    fuelType: fuelType,
                    status: status,
                    rawCssClass: cssClass,
                    events: vEvents
                ))
            }
        }

        let rentalCount = normEvents.filter { $0.domain == 101 || $0.type == "rental" }.count

        return WheelSysFleetChartResult(
            station: station,
            startDate: startDateStr,
            endDate: endDateStr,
            vehiclesCount: vehicles.count,
            eventsCount: normEvents.count,
            rentalEventsCount: rentalCount,
            vehicles: vehicles,
            allEvents: normEvents
        )
    }

    private static func normalizeRawEvent(_ ev: [String: Any]) -> WheelSysFleetEvent? {
        let vehicleId = string(ev["resource"])
        guard !vehicleId.isEmpty else { return nil }
        let html     = string(ev["html"])
        let domain   = int(ev["Domain"]) ?? int(ev["domain"]) ?? 0
        let rentalId = int(ev["RentalTable_Id"]) ?? int(ev["rentalTable_Id"]) ?? int(ev["RentalTableId"])
        let type     = fleetEventType(html: html, domain: domain)
        let status   = fleetEventStatus(html: html)
        return WheelSysFleetEvent(
            eventId: string(ev["id"]),
            vehicleId: vehicleId,
            domain: domain,
            type: type,
            status: status,
            rentalEntityId: rentalId,
            recordId: string(ev["recordId"]),
            start: firstEventDateString(ev, html: html, keys: ["start", "Start", "StartDate", "startDate", "eventStart"], htmlAttr: "data-start"),
            end: firstEventDateString(ev, html: html, keys: ["end", "End", "EndDate", "endDate", "eventEnd"], htmlAttr: "data-end"),
            stationFrom: string(ev["stationFrom"]),
            initialCarGroup: string(ev["initialCarGroup"]),
            driverName: extractFleetSpan(html: html, cls: "fleetchart-event-text-driver"),
            startTimeText: extractFleetSpan(html: html, cls: "fleetchart-event-text-start-time"),
            endTimeText: extractFleetSpan(html: html, cls: "fleetchart-event-text-end-time")
        )
    }

    private static func firstEventDateString(
        _ ev: [String: Any],
        html: String,
        keys: [String],
        htmlAttr: String
    ) -> String {
        for key in keys {
            if let n = ev[key] as? NSNumber {
                return "/Date(\(n.int64Value))/"
            }
            let s = string(ev[key])
            if !s.isEmpty { return s }
        }
        let fromHtml = extractHtmlDataAttribute(html, attr: htmlAttr)
        if !fromHtml.isEmpty { return fromHtml }
        return ""
    }

    private static func extractHtmlDataAttribute(_ html: String, attr: String) -> String {
        let escaped = NSRegularExpression.escapedPattern(for: attr)
        let pattern = "\(escaped)\\s*=\\s*[\"']([^\"']+)[\"']"
        guard let re = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { return "" }
        let ns = html as NSString
        guard let m = re.firstMatch(in: html, range: NSRange(location: 0, length: ns.length)),
              m.numberOfRanges > 1 else { return "" }
        let r = m.range(at: 1)
        guard r.location != NSNotFound else { return "" }
        return ns.substring(with: r).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: Fleet HTML helpers

    private static func fleetColHtml(_ cols: [[String: Any]], order: Int) -> String {
        cols.first { ($0["order"] as? NSNumber)?.intValue == order }.flatMap { $0["html"] as? String } ?? ""
    }

    private static func cleanFleetCell(_ html: String) -> String {
        var s = html
        s = s.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
        s = s.replacingOccurrences(of: "&nbsp;", with: " ", options: .caseInsensitive)
        s = s.replacingOccurrences(of: "&amp;",  with: "&", options: .caseInsensitive)
        s = s.replacingOccurrences(of: "&lt;",   with: "<", options: .caseInsensitive)
        s = s.replacingOccurrences(of: "&gt;",   with: ">", options: .caseInsensitive)
        return s.components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }.joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func cleanFleetPlate(_ html: String) -> String {
        cleanFleetCell(html).uppercased()
    }

    /// Strip separators for plate comparison. "ZG 87464" == "ZG87464" == "ZG-87464".
    /// Delegates to the shared normalizer so app + WheelSys + backend stay in sync.
    private static func normalizePlateForMatch(_ plate: String) -> String {
        WheelSysPlateNormalizer.canonical(plate)
    }

    private static func fleetParseMileage(_ text: String) -> Int {
        Int(text.filter { $0.isNumber }) ?? 0
    }

    private static func fleetParseFuelColor(_ text: String) -> (String, String) {
        let parts = text.components(separatedBy: "/")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        let fuels: Set<String> = ["petrol", "diesel", "electric", "hybrid"]
        if parts.count >= 2 { return (parts[0], parts[1]) }
        if let only = parts.first {
            return fuels.contains(only.lowercased()) ? ("", only) : (only, "")
        }
        return ("", "")
    }

    private static func vehicleStatusFromClass(_ css: String) -> String {
        let c = css.lowercased()
        if c.contains("fleetchart-rental-active-bgcolor")        { return "on_rental" }
        if c.contains("fleetchart-non-revenue-running-bgcolor")   { return "non_revenue" }
        if c.contains("fleetchart-non-revenue-closed-bgcolor")    { return "non_revenue_closed" }
        return "available"
    }

    private static func fleetEventType(html: String, domain: Int) -> String {
        let h = html.lowercased()
        if h.contains("fleetchart-event-main-rental")      || domain == 101 { return "rental" }
        if h.contains("fleetchart-event-main-booking")     || domain == 100 { return "booking" }
        if h.contains("fleetchart-event-main-non-revenue") || domain == 8   { return "non_revenue" }
        if h.contains("fleetchart-event-insurance")        || domain == 0   { return "insurance" }
        return "other"
    }

    private static func fleetEventStatus(html: String) -> String {
        let h = html.lowercased()
        if h.contains("fleetchart-rental-active-bgcolor")        { return "active" }
        if h.contains("fleetchart-rental-closed-bgcolor")        { return "closed" }
        if h.contains("fleetchart-booking-bgcolor")              { return "booking" }
        if h.contains("fleetchart-non-revenue-running-bgcolor")  { return "active" }
        if h.contains("fleetchart-non-revenue-closed-bgcolor")   { return "closed" }
        return "unknown"
    }

    private static func extractFleetSpan(html: String, cls: String) -> String {
        let pattern = "class=['\"]\\Q\(cls)\\E['\"][^>]*>([^<]*)"
        guard let re = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { return "" }
        let ns = html as NSString
        guard let m = re.firstMatch(in: html, range: NSRange(location: 0, length: ns.length)),
              m.numberOfRanges > 1 else { return "" }
        let r = m.range(at: 1)
        guard r.location != NSNotFound else { return "" }
        return cleanFleetCell(ns.substring(with: r))
    }

    private static func parseFleetChart(_ data: [String: Any]) -> WheelSysFleetChartResult {
        let vehiclesRaw = data["vehicles"] as? [[String: Any]] ?? []
        let vehicles = vehiclesRaw.map { row -> WheelSysFleetVehicle in
            let eventsRaw = row["events"] as? [[String: Any]] ?? []
            let events = eventsRaw.map { ev -> WheelSysFleetEvent in
                WheelSysFleetEvent(
                    eventId: string(ev["eventId"]),
                    vehicleId: string(ev["vehicleId"]),
                    domain: int(ev["domain"]) ?? 0,
                    type: string(ev["type"]),
                    status: string(ev["status"]),
                    rentalEntityId: int(ev["rentalEntityId"]),
                    recordId: string(ev["recordId"]),
                    start: string(ev["start"]),
                    end: string(ev["end"]),
                    stationFrom: string(ev["stationFrom"]),
                    initialCarGroup: string(ev["initialCarGroup"]),
                    driverName: string(ev["driverName"]),
                    startTimeText: string(ev["startTimeText"]),
                    endTimeText: string(ev["endTimeText"])
                )
            }
            return WheelSysFleetVehicle(
                vehicleId: string(row["vehicleId"]),
                group: string(row["group"]),
                plate: string(row["plate"]),
                model: string(row["model"]),
                station: string(row["station"]),
                mileage: int(row["mileage"]) ?? 0,
                color: {
                    let c = string(row["color"])
                    return c.isEmpty ? nil : c
                }(),
                fuelType: string(row["fuelType"]),
                status: string(row["status"]),
                rawCssClass: string(row["rawCssClass"]),
                events: events
            )
        }
        let flatEvents = vehicles.flatMap { $0.events }
        let rentalCount = flatEvents.filter { $0.domain == 101 || $0.type == "rental" }.count
        return WheelSysFleetChartResult(
            station: string(data["station"]).isEmpty ? "ZRH" : string(data["station"]),
            startDate: string(data["startDate"]),
            endDate: string(data["endDate"]),
            vehiclesCount: int(data["vehiclesCount"]) ?? vehicles.count,
            eventsCount: int(data["eventsCount"]) ?? flatEvents.count,
            rentalEventsCount: rentalCount,
            vehicles: vehicles,
            allEvents: flatEvents
        )
    }

    private static func mapFleetCallableError(_ error: Error) -> Error {
        WheelSysCheckinServiceError.operationFailed(describeCallableError(error))
    }

    /// Human-readable Firebase callable error (never logs cookies).
    static func describeCallableError(_ error: Error) -> String {
        let ns = error as NSError
        guard ns.domain == FunctionsErrorDomain else {
            return error.localizedDescription
        }

        let details = ns.userInfo[FunctionsErrorDetailsKey] as? [String: Any]
        let detailCode = string(details?["code"])
        let httpStatus = int(details?["httpStatus"])

        var parts: [String] = []

        let failureReason = (ns.userInfo[NSLocalizedFailureReasonErrorKey] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let localized = ns.localizedDescription.trimmingCharacters(in: .whitespacesAndNewlines)

        if !failureReason.isEmpty, failureReason.uppercased() != "INTERNAL" {
            parts.append(failureReason)
        } else if !localized.isEmpty, localized.uppercased() != "INTERNAL" {
            parts.append(localized)
        }

        if parts.isEmpty {
            let serverMessage = string(ns.userInfo["message"])
            if !serverMessage.isEmpty, serverMessage.uppercased() != "INTERNAL" {
                parts.append(serverMessage)
            }
        }

        if parts.isEmpty {
            for (_, value) in ns.userInfo {
                guard let text = value as? String else { continue }
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard trimmed.count > 3, trimmed.uppercased() != "INTERNAL" else { continue }
                if trimmed.contains(" ") || trimmed.contains(".") {
                    parts.append(trimmed)
                    break
                }
            }
        }

        if detailCode == "WHEELSYS_SESSION_EXPIRED" || detailCode == "WHEELSYS_SESSION_MISSING" {
            return "wheelsys_fleet.session_expired".localized
        }

        if !detailCode.isEmpty {
            parts.append("[\(detailCode)]")
        }
        if let status = httpStatus {
            parts.append("(HTTP \(status))")
        }
        let preview = string(details?["debugPreview"])
        if !preview.isEmpty {
            parts.append(preview)
        }
        let wheelSysMsg = string(details?["wheelSysMessage"])
        if !wheelSysMsg.isEmpty, !parts.contains(wheelSysMsg) {
            parts.append(wheelSysMsg)
        }

        if parts.isEmpty {
            if ns.code == FunctionsErrorCode.notFound.rawValue {
                return "wheelsys_fleet.function_missing".localized
            }
            return "wheelsys_fleet.unknown_error".localized
        }
        return parts.joined(separator: " ")
    }

    // MARK: Preview

    static func loadPreview(
        franchiseId: String,
        entityId: String,
        expectedResNo: String? = nil
    ) async throws -> WheelSysRentalPreview {
        guard Auth.auth().currentUser != nil else { throw WheelSysCheckinServiceError.notAuthenticated }
        var payload: [String: Any] = [
            "franchiseId": franchiseId.uppercased(),
            "entityId": entityId,
            "station": "ZRH",
        ]
        if let exp = expectedResNo?.trimmingCharacters(in: .whitespacesAndNewlines), !exp.isEmpty {
            payload["expectedResNo"] = exp
        }
        let result = try await functions.httpsCallable("wheelsysGetRentalPreview").call(payload)
        guard let data = result.data as? [String: Any] else {
            throw WheelSysCheckinServiceError.operationFailed("Invalid preview response.".localized)
        }
        var userOptions: [(id: String, name: String)] = []
        if let opts = data["checkInUserOptions"] as? [[String: Any]] {
            for row in opts {
                let id = string(row["id"])
                let name = string(row["name"])
                if !id.isEmpty { userOptions.append((id: id, name: name)) }
            }
        }
        let notesBag = data["notes"] as? [String: Any]
        let vehicleMaster = data["vehicleMaster"] as? [String: Any]
        let checkoutText = string(data["checkoutMileageText"])
        let checkinText = string(data["checkinMileageText"])
        return WheelSysRentalPreview(
            entityId: string(data["entityId"]),
            vehicleEntityId: string(data["vehicleEntityId"]),
            resNo: string(data["resNo"]),
            raNo: string(data["raNo"]),
            plate: string(data["plate"]),
            mileageFrom: int(data["mileageFrom"]) ?? 0,
            mileageTo: int(data["mileageTo"]) ?? 0,
            fuelFrom: int(data["fuelFrom"]) ?? 0,
            fuelTo: int(data["fuelTo"]) ?? 0,
            checkoutMileageText: checkoutText.isEmpty ? string(data["mileageFromText"]) : checkoutText,
            checkinMileageText: checkinText.isEmpty ? string(data["mileageToText"]) : checkinText,
            vehicleMasterMileage: int(data["vehicleMasterMileage"]) ?? int(vehicleMaster?["mileage"]),
            vehicleMasterFuel: int(data["vehicleMasterFuel"]) ?? int(vehicleMaster?["tank"]),
            milesDriven: int(data["milesDriven"]) ?? 0,
            checkInUserId: string(data["userTo"]),
            checkInUserOptions: userOptions,
            dateTo: string(data["dateTo"]),
            timeTo: string(data["timeTo"]),
            insurance: parseInsuranceSummary(data["insurance"]),
            rentalNotes: parseEntityNotes(data["rentalNotes"] ?? notesBag?["rentalNotes"]),
            vehicleNotes: parseEntityNotes(data["vehicleNotes"] ?? notesBag?["vehicleNotes"])
        )
    }

    // MARK: Notes

    static func saveNote(
        franchiseId: String,
        entityKey: String,
        domain: Int,
        noteText: String,
        creatorId: String? = nil
    ) async throws {
        guard Auth.auth().currentUser != nil else { throw WheelSysCheckinServiceError.notAuthenticated }
        let trimmed = noteText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw WheelSysCheckinServiceError.operationFailed("Note text is required.".localized)
        }
        let key = entityKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else {
            throw WheelSysCheckinServiceError.operationFailed("Entity key is required.".localized)
        }

        var payload: [String: Any] = [
            "franchiseId": franchiseId.uppercased(),
            "entityKey": key,
            "domain": domain,
            "noteText": trimmed,
            "station": "ZRH",
        ]
        if let creatorId = creatorId?.trimmingCharacters(in: .whitespacesAndNewlines), !creatorId.isEmpty {
            payload["creatorId"] = creatorId
        }

        let result = try await functions.httpsCallable("wheelsysSaveNote").call(payload)
        guard let data = result.data as? [String: Any],
              data["success"] as? Bool == true else {
            let msg = (result.data as? [String: Any]).flatMap { string($0["message"]) } ?? ""
            throw WheelSysCheckinServiceError.operationFailed(
                msg.isEmpty ? "Failed to save note.".localized : msg
            )
        }
    }

    /// Save the same note on rental + vehicle entities (vehicle optional).
    static func saveReturnNotes(
        franchiseId: String,
        rentalEntityId: String,
        vehicleEntityId: String?,
        noteText: String,
        creatorId: String?
    ) async throws {
        var lastError: Error?
        do {
            try await saveNote(
                franchiseId: franchiseId,
                entityKey: rentalEntityId,
                domain: 5,
                noteText: noteText,
                creatorId: creatorId
            )
        } catch {
            lastError = error
        }

        if let vehicleEntityId = vehicleEntityId?.trimmingCharacters(in: .whitespacesAndNewlines),
           !vehicleEntityId.isEmpty {
            do {
                try await saveNote(
                    franchiseId: franchiseId,
                    entityKey: vehicleEntityId,
                    domain: 1,
                    noteText: noteText,
                    creatorId: creatorId
                )
            } catch {
                if lastError == nil { lastError = error }
            }
        }

        if let lastError {
            throw lastError
        }
    }

    private static func parseEntityNotes(_ value: Any?) -> [WheelSysEntityNote] {
        guard let rows = value as? [[String: Any]] else { return [] }
        return rows.compactMap { row in
            let text = string(row["text"])
            guard !text.isEmpty else { return nil }
            let id = string(row["id"])
            return WheelSysEntityNote(
                id: id.isEmpty ? UUID().uuidString : id,
                text: text,
                createdBy: string(row["createdBy"]),
                createdAt: string(row["createdAt"]),
                source: string(row["source"])
            )
        }
    }

    private static func parseInsuranceSummary(_ value: Any?) -> WheelSysInsuranceSummary? {
        guard let row = value as? [String: Any] else { return nil }
        let typesRaw = row["insuranceTypes"] as? [Any] ?? []
        let types = typesRaw.map { string($0) }.filter { !$0.isEmpty }
        let summary = WheelSysInsuranceSummary(
            hasInsuranceCharge: row["hasInsuranceCharge"] as? Bool ?? false,
            insuranceChargeAmount: string(row["insuranceChargeAmount"]),
            excessAmount: string(row["excessAmount"]),
            damageExcessAmount: string(row["damageExcessAmount"]),
            insuranceTypes: types
        )
        if !summary.hasInsuranceCharge,
           summary.insuranceChargeAmount.isEmpty,
           summary.excessAmount.isEmpty,
           summary.damageExcessAmount.isEmpty,
           types.isEmpty {
            return nil
        }
        return summary
    }

    // MARK: Sync

    /// Submit check-in mileage/fuel to WheelSys.
    /// Optionally links the result back to a Vehicle Sentinel Firestore document so
    /// `wheelsysSyncStatus` / `wheelsysLastSyncAt` etc. are written automatically.
    static func submitCheckinUpdate(
        franchiseId: String,
        entityId: String,
        resNo: String,
        plate: String,
        checkInMileage: Int,
        checkInFuel: Int,
        checkInUserId: String?,
        /// e.g. "exitIslemleri" or "iadeIslemleri"
        firestoreCollection: String? = nil,
        /// Document ID inside that collection
        firestoreDocId: String? = nil,
        addAutoNotes: Bool = true,
        rentalNoteText: String? = nil,
        vehicleEntityIdHint: String? = nil,
        fleetCarId: String? = nil
    ) async throws -> WheelSysCheckinResult {
        guard Auth.auth().currentUser != nil else { throw WheelSysCheckinServiceError.notAuthenticated }

        // Client-side validation mirrors backend validation.
        guard checkInMileage > 0 else {
            throw WheelSysCheckinServiceError.operationFailed("Check-in mileage must be greater than zero.".localized)
        }
        guard (0...8).contains(checkInFuel) else {
            throw WheelSysCheckinServiceError.operationFailed("Fuel must be between 0 and 8.".localized)
        }

        var payload: [String: Any] = [
            "franchiseId": franchiseId.uppercased(),
            "entityId": entityId,
            "resNo": resNo,
            "plate": plate,
            "checkInMileage": checkInMileage,
            "checkInFuel": checkInFuel,
            "station": "ZRH",
        ]
        if let uid = checkInUserId, !uid.isEmpty { payload["checkInUserId"] = uid }
        if let col = firestoreCollection, !col.isEmpty { payload["firestoreCollection"] = col }
        if let docId = firestoreDocId, !docId.isEmpty { payload["firestoreDocId"] = docId }
        if addAutoNotes { payload["addNotes"] = true }
        if let note = rentalNoteText?.trimmingCharacters(in: .whitespacesAndNewlines), !note.isEmpty {
            payload["rentalNoteText"] = note
            payload["vehicleNoteText"] = note
        }
        if let vehicleId = vehicleEntityIdHint?.trimmingCharacters(in: .whitespacesAndNewlines), !vehicleId.isEmpty {
            payload["vehicleEntityId"] = vehicleId
        }
        if let carId = fleetCarId?.trimmingCharacters(in: .whitespacesAndNewlines), !carId.isEmpty {
            payload["fleetCarId"] = carId
        }

        let result = try await functions.httpsCallable("wheelsysCheckinUpdate").call(payload)
        guard let data = result.data as? [String: Any] else {
            throw WheelSysCheckinServiceError.operationFailed("Invalid update response.".localized)
        }
        let inner = data["result"] as? [String: Any]
        let notesBag = data["notes"] as? [String: Any]
        let noteErrors = (notesBag?["errors"] as? [String]) ?? []
        return WheelSysCheckinResult(
            success: data["success"] as? Bool ?? false,
            message: string(data["message"]),
            mileageFrom: int(inner?["mileageFrom"]),
            mileageTo: int(inner?["mileageTo"]),
            milesDriven: int(inner?["milesDriven"]),
            fuelTo: int(inner?["fuelTo"]),
            verifiedMileageTo: int(inner?["verifiedMileageTo"]),
            vehicleMasterSynced: inner?["vehicleMasterSynced"] as? Bool ?? false,
            vehicleEntityId: {
                let v = string(inner?["vehicleEntityId"])
                return v.isEmpty ? nil : v
            }(),
            vehicleFuelVerified: int(inner?["vehicleFuelVerified"]),
            noteErrors: noteErrors
        )
    }

    // MARK: Booking assignment (checkout)

    static func resolveBookingContext(
        franchiseId: String,
        bookingEntityId: Int,
        station: String = "ZRH",
        resNo: String? = nil,
        displayDocNo: String? = nil,
        correlationId: String
    ) async throws -> ResolvedBookingContext {
        guard Auth.auth().currentUser != nil else { throw WheelSysCheckinServiceError.notAuthenticated }
        var payload: [String: Any] = [
            "franchiseId": franchiseId.uppercased(),
            "bookingEntityId": bookingEntityId,
            "station": station,
            "correlationId": correlationId,
        ]
        if let resNo = resNo?.trimmingCharacters(in: .whitespacesAndNewlines), !resNo.isEmpty {
            payload["resNo"] = resNo
        }
        if let displayDocNo = displayDocNo?.trimmingCharacters(in: .whitespacesAndNewlines), !displayDocNo.isEmpty {
            payload["displayDocNo"] = displayDocNo
        }
        do {
            let result = try await functions.httpsCallable("wheelsysResolveBookingContext").call(payload)
            guard let data = result.data as? [String: Any] else {
                throw WheelSysCheckinServiceError.operationFailed("Invalid booking context response.".localized)
            }
            let resolvedId = int(data["bookingEntityId"]) ?? int(data["entityId"]) ?? bookingEntityId
            let cacheKey = string(data["cacheKey"])
            guard resolvedId > 0, !cacheKey.isEmpty else {
                throw WheelSysCheckinServiceError.operationFailed("Booking context is incomplete.".localized)
            }
            return ResolvedBookingContext(
                bookingEntityId: resolvedId,
                cacheKey: cacheKey,
                resNo: string(data["resNo"]),
                resolvedFrom: string(data["source"]),
                correlationId: string(data["correlationId"]).isEmpty ? correlationId : string(data["correlationId"])
            )
        } catch {
            throw WheelSysCheckinServiceError.operationFailed(describeCallableError(error))
        }
    }

    static func loadBookingPreview(
        franchiseId: String,
        entityId: Int,
        resNo: String? = nil,
        displayDocNo: String? = nil
    ) async throws -> WheelSysBookingPreview {
        guard Auth.auth().currentUser != nil else { throw WheelSysCheckinServiceError.notAuthenticated }
        var payload: [String: Any] = [
            "franchiseId": franchiseId.uppercased(),
            "entityId": entityId,
            "station": "ZRH",
        ]
        if let resNo = resNo?.trimmingCharacters(in: .whitespacesAndNewlines), !resNo.isEmpty {
            payload["resNo"] = resNo
        }
        if let displayDocNo = displayDocNo?.trimmingCharacters(in: .whitespacesAndNewlines), !displayDocNo.isEmpty {
            payload["displayDocNo"] = displayDocNo
        }
        do {
            let result = try await functions.httpsCallable("wheelsysGetBookingPreview").call(payload)
            guard let data = result.data as? [String: Any] else {
                throw WheelSysCheckinServiceError.operationFailed("Invalid booking preview.".localized)
            }
            let driver = string(data["driverName"])
            let conf = string(data["confirmationNo"])
            let irnVal = string(data["irn"])
            print("[WheelSys][Mapping] id=\(int(data["entityId"]) ?? entityId) "
                + "displayDocNo=\(string(data["resNo"])) "
                + "confirmationNo=\(conf.isEmpty ? "nil" : conf) "
                + "irn=\(irnVal.isEmpty ? "nil" : irnVal) "
                + "voucher=nil")
            return WheelSysBookingPreview(
                entityId: int(data["entityId"]) ?? entityId,
                resNo: string(data["resNo"]),
                confirmationNo: conf.isEmpty ? nil : conf,
                irn: irnVal.isEmpty ? nil : irnVal,
                carGroup: string(data["carGroup"]),
                isAssigned: data["isAssigned"] as? Bool ?? false,
                insurance: parseInsuranceSummary(data["insurance"]),
                driverName: driver.isEmpty ? nil : driver
            )
        } catch {
            throw WheelSysCheckinServiceError.operationFailed(describeCallableError(error))
        }
    }

    static func assignVehicleToBooking(
        franchiseId: String,
        bookingEntityId: Int,
        carId: Int,
        plateNo: String,
        carGroup: String?,
        checkOutMileage: Int,
        checkOutFuel: Int,
        resNo: String,
        preResolvedCacheKey: String? = nil,
        preResolvedBookingEntityId: Int? = nil,
        correlationId: String? = nil,
        displayDocNo: String? = nil,
        firestoreCollection: String? = nil,
        firestoreDocId: String? = nil
    ) async throws -> WheelSysAssignmentResult {
        guard Auth.auth().currentUser != nil else { throw WheelSysCheckinServiceError.notAuthenticated }
        guard bookingEntityId > 0, carId > 0 else {
            throw WheelSysCheckinServiceError.operationFailed("Invalid booking or vehicle id.".localized)
        }
        var payload: [String: Any] = [
            "franchiseId": franchiseId.uppercased(),
            "bookingEntityId": bookingEntityId,
            "carId": carId,
            "plateNo": plateNo,
            "checkOutMileage": checkOutMileage,
            "checkOutFuel": checkOutFuel,
            "resNo": resNo,
            "station": "ZRH",
        ]
        if let doc = displayDocNo?.trimmingCharacters(in: .whitespacesAndNewlines), !doc.isEmpty {
            payload["displayDocNo"] = doc
        }
        if let g = carGroup?.trimmingCharacters(in: .whitespacesAndNewlines), !g.isEmpty {
            payload["carGroup"] = g
        }
        if let preResolvedCacheKey = preResolvedCacheKey?.trimmingCharacters(in: .whitespacesAndNewlines),
           !preResolvedCacheKey.isEmpty {
            payload["preResolvedCacheKey"] = preResolvedCacheKey
        }
        if let preResolvedBookingEntityId, preResolvedBookingEntityId > 0 {
            payload["preResolvedBookingEntityId"] = preResolvedBookingEntityId
        }
        if let correlationId = correlationId?.trimmingCharacters(in: .whitespacesAndNewlines), !correlationId.isEmpty {
            payload["correlationId"] = correlationId
        }
        if let col = firestoreCollection, !col.isEmpty { payload["firestoreCollection"] = col }
        if let docId = firestoreDocId, !docId.isEmpty { payload["firestoreDocId"] = docId }

        do {
            let result = try await functions.httpsCallable("wheelsysAssignVehicleToBooking").call(payload)
            guard let data = result.data as? [String: Any] else {
                throw WheelSysCheckinServiceError.operationFailed("Invalid assignment response.".localized)
            }
            let inner = data["result"] as? [String: Any]
            return WheelSysAssignmentResult(
                success: data["success"] as? Bool ?? false,
                message: string(data["message"]),
                bookingEntityId: int(inner?["bookingEntityId"]) ?? int(data["bookingEntityId"]),
                carId: int(inner?["carId"]),
                plateNo: {
                    let p = string(inner?["plateNo"])
                    return p.isEmpty ? nil : p
                }()
            )
        } catch {
            throw WheelSysCheckinServiceError.operationFailed(describeCallableError(error))
        }
    }

    // MARK: Helpers

    private static func string(_ value: Any?) -> String {
        guard let v = value else { return "" }
        return String(describing: v).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func int(_ value: Any?) -> Int? {
        if let n = value as? Int { return n }
        if let n = value as? NSNumber { return n.intValue }
        if let s = value as? String { return Int(s) }
        return nil
    }
}
