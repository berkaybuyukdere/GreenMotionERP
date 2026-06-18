import Foundation
import FirebaseAuth
import FirebaseFunctions

enum WheelSysDailyViewServiceError: LocalizedError {
    case notAuthenticated
    case operationFailed(String)
    case invalidResponse
    case unknownTab(String)

    var errorDescription: String? {
        switch self {
        case .notAuthenticated: return "You must be signed in.".localized
        case .operationFailed(let msg): return msg
        case .invalidResponse: return "Invalid daily view response.".localized
        case .unknownTab(let tab): return "Unknown daily view tab: \(tab)"
        }
    }
}

enum WheelSysDailyViewService {
    private static let functions = Functions.functions(region: "europe-west6")

    static func loadTab(
        franchiseId: String,
        tab: WheelSysDailyViewTab,
        selectedDate: String,
        station: String = "ZRH"
    ) async throws -> WheelSysDailyViewTabPayload {
        guard Auth.auth().currentUser != nil else {
            throw WheelSysDailyViewServiceError.notAuthenticated
        }

        let day = selectedDate.trimmingCharacters(in: .whitespacesAndNewlines)
        let st = station.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !day.isEmpty else {
            throw WheelSysDailyViewServiceError.operationFailed("selectedDate is required.".localized)
        }

        let result: HTTPSCallableResult
        do {
            result = try await functions.httpsCallable("wheelsysGetDailyView").call([
                "franchiseId": franchiseId.uppercased(),
                "tab": tab.rawValue,
                "selectedDate": day,
                "station": st.isEmpty ? "ZRH" : st,
            ])
        } catch {
            throw WheelSysDailyViewServiceError.operationFailed(
                WheelSysCheckinService.describeCallableError(error)
            )
        }

        guard let data = result.data as? [String: Any] else {
            throw WheelSysDailyViewServiceError.invalidResponse
        }
        guard data["success"] as? Bool != false else {
            let msg = string(data["message"])
            throw WheelSysDailyViewServiceError.operationFailed(
                msg.isEmpty ? "Daily view request failed.".localized : msg
            )
        }

        let resolvedDate = string(data["selectedDate"]).isEmpty ? day : string(data["selectedDate"])
        let resolvedStation = string(data["station"]).isEmpty ? st : string(data["station"])
        let rows = data["rows"] as? [[String: Any]] ?? []

        print("[DailyView] tab=\(tab.rawValue) date=\(resolvedDate) station=\(resolvedStation) rows=\(rows.count)")

        return WheelSysDailyViewTabPayload(
            tab: tab,
            selectedDate: resolvedDate,
            station: resolvedStation,
            rows: parseRows(tab: tab, rows: rows)
        )
    }

    static func loadAll(
        franchiseId: String,
        selectedDate: String,
        station: String = "ZRH"
    ) async throws -> WheelSysDailyViewAllResult {
        guard Auth.auth().currentUser != nil else {
            throw WheelSysDailyViewServiceError.notAuthenticated
        }

        let day = selectedDate.trimmingCharacters(in: .whitespacesAndNewlines)
        let st = station.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !day.isEmpty else {
            throw WheelSysDailyViewServiceError.operationFailed("selectedDate is required.".localized)
        }

        let result: HTTPSCallableResult
        do {
            result = try await functions.httpsCallable("wheelsysGetDailyViewAll").call([
                "franchiseId": franchiseId.uppercased(),
                "selectedDate": day,
                "station": st.isEmpty ? "ZRH" : st,
            ])
        } catch {
            throw WheelSysDailyViewServiceError.operationFailed(
                WheelSysCheckinService.describeCallableError(error)
            )
        }

        guard let data = result.data as? [String: Any] else {
            throw WheelSysDailyViewServiceError.invalidResponse
        }
        guard data["success"] as? Bool != false else {
            let msg = string(data["message"])
            throw WheelSysDailyViewServiceError.operationFailed(
                msg.isEmpty ? "Daily view request failed.".localized : msg
            )
        }

        let resolvedDate = string(data["selectedDate"]).isEmpty ? day : string(data["selectedDate"])
        let resolvedStation = string(data["station"]).isEmpty ? st : string(data["station"])
        let tabsBag = data["tabs"] as? [String: Any]

        let checkouts = extractRows(data["checkouts"] ?? tabsBag?["checkouts"])
            .enumerated()
            .compactMap { parseCheckout($0.element, index: $0.offset) }
        let checkins = extractRows(data["checkins"] ?? tabsBag?["checkins"])
            .enumerated()
            .compactMap { parseCheckin($0.element, index: $0.offset) }
        let nonRevenue = extractRows(data["nonrevenue"] ?? tabsBag?["nonrevenue"])
            .enumerated()
            .compactMap { parseNonRevenue($0.element, index: $0.offset) }
        let available = extractRows(data["available"] ?? tabsBag?["available"])
            .compactMap { parseAvailable($0) }
        let bookings = extractRows(data["bookings"] ?? tabsBag?["bookings"])
            .enumerated()
            .compactMap { parseBooking($0.element, index: $0.offset) }

        print("[DailyView] all date=\(resolvedDate) checkouts=\(checkouts.count) checkins=\(checkins.count) nonrevenue=\(nonRevenue.count) available=\(available.count) bookings=\(bookings.count)")

        return WheelSysDailyViewAllResult(
            selectedDate: resolvedDate,
            station: resolvedStation,
            checkouts: checkouts,
            checkins: checkins,
            nonRevenue: nonRevenue,
            available: available,
            bookings: bookings
        )
    }

    // MARK: Row parsing

    private static func parseRows(tab: WheelSysDailyViewTab, rows: [[String: Any]]) -> WheelSysDailyViewTabRows {
        switch tab {
        case .checkouts:
            return .checkouts(rows.enumerated().compactMap { parseCheckout($0.element, index: $0.offset) })
        case .checkins:
            return .checkins(rows.enumerated().compactMap { parseCheckin($0.element, index: $0.offset) })
        case .nonRevenue:
            return .nonRevenue(rows.enumerated().compactMap { parseNonRevenue($0.element, index: $0.offset) })
        case .available:
            return .available(rows.compactMap { parseAvailable($0) })
        case .bookings:
            return .bookings(rows.enumerated().compactMap { parseBooking($0.element, index: $0.offset) })
        }
    }

    private static func parseCheckout(_ row: [String: Any], index: Int) -> WheelSysDailyViewCheckout? {
        let plate = firstString(row, "plate", "plateno", "plateNo")
        let normalized = normalizedPlate(plate, row: row)
        let entityId = resolveEntityId(row)
        let domain = int(row["domain"])
        let unassigned = row["isUnassigned"] as? Bool
            ?? plate.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || domain == 100
        let displayDocNo = firstString(row, "displayDocNo", "displaydocno")
        let id = entityId.map { "dv-checkout-\($0)-\(index)" }
            ?? "dv-checkout-\(displayDocNo)-\(index)"

        return WheelSysDailyViewCheckout(
            id: id,
            displayDocNo: displayDocNo,
            confirmationNo: firstString(row, "confirmationNo", "confirmationno"),
            driverName: firstString(row, "driverName", "drivername"),
            plate: plate,
            normalizedPlate: normalized,
            carGroup: firstString(row, "carGroup", "cargroup"),
            carGroupInv: firstString(row, "carGroupInv", "cargroupinv"),
            fuel: int(row["fuel"]),
            dateFrom: optionalString(row["dateFrom"] ?? row["datefrom"]),
            dateTo: optionalString(row["dateTo"] ?? row["dateto"]),
            status: string(row["status"]),
            voucherNo: optionalString(row["voucherNo"] ?? row["VoucherNo"]),
            irn: optionalString(row["irn"] ?? row["Irn"]),
            domain: domain,
            rentalEntityId: entityId,
            isUnassigned: unassigned,
            rawFields: stringifyRaw(row)
        )
    }

    private static func parseCheckin(_ row: [String: Any], index: Int) -> WheelSysDailyViewCheckin? {
        let plate = firstString(row, "plate", "plateno", "plateNo")
        let normalized = normalizedPlate(plate, row: row)
        let entityId = resolveEntityId(row)
        let displayDocNo = firstString(row, "displayDocNo", "displaydocno")
        let id = entityId.map { "dv-checkin-\($0)-\(index)" }
            ?? "dv-checkin-\(displayDocNo)-\(index)"

        return WheelSysDailyViewCheckin(
            id: id,
            displayDocNo: displayDocNo,
            driverName: firstString(row, "driverName", "drivername"),
            plate: plate,
            normalizedPlate: normalized,
            mileage: int(row["mileage"]),
            fuel: int(row["fuel"]),
            dateFrom: optionalString(row["dateFrom"] ?? row["datefrom"]),
            dateTo: optionalString(row["dateTo"] ?? row["dateto"]),
            status: string(row["status"]),
            voucherNo: optionalString(row["voucherNo"] ?? row["VoucherNo"]),
            domain: int(row["domain"]),
            rentalEntityId: entityId,
            vehicleEntityId: resolveVehicleEntityId(row),
            rawFields: stringifyRaw(row)
        )
    }

    private static func parseNonRevenue(_ row: [String: Any], index: Int) -> WheelSysDailyViewNonRevenue? {
        let plate = firstString(row, "plate", "plateno", "plateNo")
        let displayDocNo = firstString(row, "displayDocNo", "displaydocno")
        let id = "dv-nrt-\(displayDocNo)-\(index)"

        return WheelSysDailyViewNonRevenue(
            id: id,
            displayDocNo: displayDocNo,
            dateFrom: optionalString(row["dateFrom"] ?? row["datefrom"]),
            dateTo: optionalString(row["dateTo"] ?? row["dateto"]),
            plate: plate,
            normalizedPlate: normalizedPlate(plate, row: row),
            modelName: firstString(row, "modelName", "model_name", "carmodel"),
            drivenByName: firstString(row, "drivenByName", "drivenbyname"),
            nonRevenueTypeName: firstString(row, "nonRevenueTypeName", "nonrevenuetype_name"),
            remarks: optionalString(row["remarks"]),
            domain: int(row["domain"]),
            rawFields: stringifyRaw(row)
        )
    }

    private static func parseAvailable(_ row: [String: Any]) -> WheelSysDailyViewAvailable? {
        let plate = firstString(row, "plate", "plateno", "plateNo")
        let normalized = normalizedPlate(plate, row: row)
        let vehicleId = resolveVehicleEntityId(row) ?? string(row["vehicleEntityId"])
        guard !vehicleId.isEmpty || !normalized.isEmpty else { return nil }

        return WheelSysDailyViewAvailable(
            vehicleEntityId: vehicleId,
            plate: plate,
            normalizedPlate: normalized,
            group: firstString(row, "group", "carGroup", "cargroup"),
            grpCode: firstString(row, "grpCode", "grpcode"),
            model: firstString(row, "model", "carmodel", "carModel"),
            station: firstString(row, "station"),
            mileage: int(row["mileage"]) ?? 0,
            fuel: int(row["fuel"]),
            availableUntil: optionalString(row["availableUntil"] ?? row["available_until"]),
            lastCheckin: optionalString(row["lastCheckin"] ?? row["lastcheckin"]),
            lastCheckinLocation: optionalString(row["lastCheckinLocation"] ?? row["lastcheckinlocation"]),
            active: bool(row["active"]),
            inUse: bool(row["inUse"] ?? row["inuse"]),
            hardHold: bool(row["hardHold"] ?? row["hardhold"]),
            onService: bool(row["onService"] ?? row["OnService"]),
            vin: optionalString(row["vin"] ?? row["Vin"]),
            rawFields: stringifyRaw(row)
        )
    }

    private static func parseBooking(_ row: [String: Any], index: Int) -> WheelSysDailyViewBooking? {
        let displayDocNo = firstString(row, "displayDocNo", "displaydocno")
        let entityId = int(row["id"]) ?? int(row["entityId"])
        let id = entityId.map { "dv-booking-\($0)" } ?? "dv-booking-\(displayDocNo)-\(index)"

        return WheelSysDailyViewBooking(
            id: id,
            entityId: entityId,
            usageType: optionalString(row["usageType"] ?? row["usagetype"]),
            sstr: optionalString(row["sstr"]),
            irn: optionalString(row["irn"] ?? row["Irn"]),
            dateFrom: optionalString(row["dateFrom"] ?? row["datefrom"]),
            dateTo: optionalString(row["dateTo"] ?? row["dateto"]),
            displayDocNo: displayDocNo,
            carGroup: firstString(row, "carGroup", "cargroup"),
            carGroupInv: firstString(row, "carGroupInv", "cargroupinv"),
            driverName: firstString(row, "driverName", "drivername"),
            agent: optionalString(row["agent"]),
            rpd: optionalString(row["rpd"]),
            resDate: optionalString(row["resDate"] ?? row["resdate"]),
            voucherNo: optionalString(row["voucherNo"] ?? row["VoucherNo"]),
            rawFields: stringifyRaw(row)
        )
    }

    // MARK: Helpers

    private static func extractRows(_ value: Any?) -> [[String: Any]] {
        if let rows = value as? [[String: Any]] { return rows }
        if let bag = value as? [String: Any], let rows = bag["rows"] as? [[String: Any]] { return rows }
        return []
    }

    private static func resolveEntityId(_ row: [String: Any]) -> Int? {
        int(row["rentalEntityId"])
            ?? int(row["entityId"])
            ?? int(row["id"])
            ?? int(row["rentalId"])
    }

    private static func resolveVehicleEntityId(_ row: [String: Any]) -> String? {
        let candidates = [
            string(row["vehicleEntityId"]),
            string(row["CarTable_Id"]),
            string(row["carTable_Id"]),
            string(row["carId"]),
            string(row["id"]),
        ]
        for candidate in candidates where !candidate.isEmpty {
            return candidate
        }
        return nil
    }

    private static func normalizedPlate(_ plate: String, row: [String: Any]) -> String {
        let fromRow = string(row["normalizedPlate"])
        if !fromRow.isEmpty { return fromRow }
        return WheelSysPlateNormalizer.canonical(plate)
    }

    private static func firstString(_ row: [String: Any], _ keys: String...) -> String {
        for key in keys {
            let value = string(row[key])
            if !value.isEmpty { return value }
        }
        return ""
    }

    private static func optionalString(_ value: Any?) -> String? {
        let s = string(value)
        return s.isEmpty ? nil : s
    }

    private static func stringifyRaw(_ row: [String: Any]) -> [String: String] {
        var out: [String: String] = [:]
        for (key, value) in row {
            out[key] = String(describing: value)
        }
        return out
    }

    private static func string(_ value: Any?) -> String {
        guard let value else { return "" }
        if value is NSNull { return "" }
        return String(describing: value).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func int(_ value: Any?) -> Int? {
        if let n = value as? Int { return n }
        if let n = value as? NSNumber { return n.intValue }
        if let s = value as? String, let n = Int(s) { return n }
        return nil
    }

    private static func bool(_ value: Any?) -> Bool {
        if let b = value as? Bool { return b }
        if let n = value as? NSNumber { return n.boolValue }
        if let s = value as? String {
            let lower = s.lowercased()
            return lower == "true" || lower == "1" || lower == "yes"
        }
        return false
    }
}

// MARK: - Tab payload

struct WheelSysDailyViewTabPayload: Hashable {
    let tab: WheelSysDailyViewTab
    let selectedDate: String
    let station: String
    let rows: WheelSysDailyViewTabRows
}

enum WheelSysDailyViewTabRows: Hashable {
    case checkouts([WheelSysDailyViewCheckout])
    case checkins([WheelSysDailyViewCheckin])
    case nonRevenue([WheelSysDailyViewNonRevenue])
    case available([WheelSysDailyViewAvailable])
    case bookings([WheelSysDailyViewBooking])

    var count: Int {
        switch self {
        case .checkouts(let rows): return rows.count
        case .checkins(let rows): return rows.count
        case .nonRevenue(let rows): return rows.count
        case .available(let rows): return rows.count
        case .bookings(let rows): return rows.count
        }
    }
}
