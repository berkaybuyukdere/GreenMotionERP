import Foundation
import FirebaseAuth
import FirebaseFunctions

enum WheelSysJournalAPIServiceError: LocalizedError {
    case notAuthenticated
    case operationFailed(String)
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .notAuthenticated: return "You must be signed in.".localized
        case .operationFailed(let msg): return msg
        case .invalidResponse: return "Invalid journal snapshot response.".localized
        }
    }
}

enum WheelSysJournalAPIService {
    private static let functions = Functions.functions(region: "europe-west6")

    static func loadSnapshot(
        franchiseId: String,
        selectedDate: String,
        station: String = "ZRH"
    ) async throws -> WheelSysJournalSnapshot {
        guard Auth.auth().currentUser != nil else {
            throw WheelSysJournalAPIServiceError.notAuthenticated
        }

        let day = selectedDate.trimmingCharacters(in: .whitespacesAndNewlines)
        let st = station.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !day.isEmpty else {
            throw WheelSysJournalAPIServiceError.operationFailed("selectedDate is required.".localized)
        }

        let result: HTTPSCallableResult
        do {
            result = try await functions.httpsCallable("wheelsysGetJournalSnapshot").call([
                "franchiseId": franchiseId.uppercased(),
                "selectedDate": day,
                "station": st.isEmpty ? "ZRH" : st,
            ])
        } catch {
            throw WheelSysJournalAPIServiceError.operationFailed(
                WheelSysCheckinService.describeCallableError(error)
            )
        }

        guard let data = result.data as? [String: Any] else {
            throw WheelSysJournalAPIServiceError.invalidResponse
        }
        guard data["success"] as? Bool != false else {
            let msg = string(data["message"])
            throw WheelSysJournalAPIServiceError.operationFailed(
                msg.isEmpty ? "Journal snapshot request failed.".localized : msg
            )
        }

        let resolvedDate = string(data["selectedDate"]).isEmpty ? day : string(data["selectedDate"])
        let resolvedStation = string(data["station"]).isEmpty ? st : string(data["station"])

        let checkOuts = (data["checkOuts"] as? [[String: Any]] ?? [])
            .enumerated()
            .compactMap { parseCheckout($0.element, index: $0.offset) }
        let checkIns = (data["checkIns"] as? [[String: Any]] ?? [])
            .enumerated()
            .compactMap { parseCheckin($0.element, index: $0.offset) }
        let available = (data["availableVehicles"] as? [[String: Any]] ?? [])
            .compactMap { parseAvailableVehicle($0) }

        print("[JournalAPI] snapshot date=\(resolvedDate) station=\(resolvedStation) checkOuts=\(checkOuts.count) checkIns=\(checkIns.count) available=\(available.count)")

        return WheelSysJournalSnapshot(
            selectedDate: resolvedDate,
            station: resolvedStation,
            checkOuts: checkOuts,
            checkIns: checkIns,
            availableVehicles: available,
            source: string(data["source"]).isEmpty ? "journal_api" : string(data["source"])
        )
    }

    // MARK: Parsing

    private static func parseCheckout(_ row: [String: Any], index: Int) -> WheelSysJournalCheckout? {
        let plate = firstString(row, "plate", "plateno", "plateNo")
        let normalized = normalizedPlate(plate, row: row)
        let ids = resolveEntityIds(row)
        let domain = int(row["domain"])
        let unassigned = row["isUnassigned"] as? Bool
            ?? Self.isPlateUnassigned(plate)

        let displayDocNo = firstString(row, "displayDocNo", "displaydocno")
        let entityKey = ids.booking ?? ids.rental
        let id = entityKey.map { "checkout-\($0)-\(index)" }
            ?? "checkout-\(displayDocNo)-\(index)"

        return WheelSysJournalCheckout(
            id: id,
            displayDocNo: displayDocNo,
            confirmationNo: firstString(row, "confirmationNo", "confirmationno"),
            resNo: firstString(row, "resNo", "resno"),
            driverName: firstString(row, "driverName", "drivername"),
            plate: plate,
            normalizedPlate: normalized,
            carGroup: firstString(row, "carGroup", "cargroup"),
            carGroupInv: firstString(row, "carGroupInv", "cargroupinv"),
            fuel: int(row["fuel"]),
            dateFrom: optionalString(row["dateFrom"] ?? row["datefrom"]),
            dateTo: optionalString(row["dateTo"] ?? row["dateto"]),
            status: string(row["status"]),
            agent: firstString(row, "agent"),
            domain: domain,
            rentalEntityId: ids.rental,
            bookingEntityId: ids.booking,
            stationTo: optionalString(row["stationTo"] ?? row["stationto"]),
            isUnassigned: unassigned,
            rawFields: stringifyRaw(row)
        )
    }

    private static func parseCheckin(_ row: [String: Any], index: Int) -> WheelSysJournalCheckin? {
        let plate = firstString(row, "plate", "plateno", "plateNo")
        let normalized = normalizedPlate(plate, row: row)
        let ids = resolveEntityIds(row)
        let vehicleEntityId = resolveVehicleEntityId(row)

        let displayDocNo = firstString(row, "displayDocNo", "displaydocno")
        let entityKey = ids.rental ?? ids.booking
        let id = entityKey.map { "checkin-\($0)-\(index)" }
            ?? "checkin-\(displayDocNo)-\(index)"

        return WheelSysJournalCheckin(
            id: id,
            displayDocNo: displayDocNo,
            confirmationNo: firstString(row, "confirmationNo", "confirmationno"),
            resNo: firstString(row, "resNo", "resno"),
            driverName: firstString(row, "driverName", "drivername"),
            plate: plate,
            normalizedPlate: normalized,
            carGroup: firstString(row, "carGroup", "cargroup"),
            carGroupInv: firstString(row, "carGroupInv", "cargroupinv", "CarGroupInv"),
            fuel: int(row["fuel"]),
            mileage: int(row["mileage"]),
            dateFrom: optionalString(row["dateFrom"] ?? row["datefrom"]),
            dateTo: optionalString(row["dateTo"] ?? row["dateto"]),
            status: string(row["status"]),
            agent: firstString(row, "agent"),
            domain: int(row["domain"]),
            rentalEntityId: ids.rental,
            bookingEntityId: ids.booking,
            vehicleEntityId: vehicleEntityId,
            stationFrom: optionalString(row["stationFrom"] ?? row["stationfrom"]),
            balance: optionalString(row["balance"]),
            model: optionalString(row["model"] ?? row["carmodel"]),
            rawFields: stringifyRaw(row)
        )
    }

    private static func parseAvailableVehicle(_ row: [String: Any]) -> WheelSysJournalVehicleAvailability? {
        let plate = firstString(row, "plate", "plateno", "plateNo")
        let normalized = normalizedPlate(plate, row: row)
        let vehicleId = resolveVehicleEntityId(row) ?? string(row["vehicleEntityId"])
        guard !vehicleId.isEmpty || !normalized.isEmpty else { return nil }

        return WheelSysJournalVehicleAvailability(
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
            active: bool(row["active"]),
            inUse: bool(row["inUse"] ?? row["inuse"]),
            hardHold: bool(row["hardHold"] ?? row["hardhold"]),
            onService: bool(row["onService"] ?? row["OnService"]),
            vin: optionalString(row["vin"] ?? row["Vin"]),
            rawFields: stringifyRaw(row)
        )
    }

    // MARK: Helpers

    private static func resolveEntityIds(_ row: [String: Any]) -> (rental: Int?, booking: Int?) {
        let raw = row["raw"] as? [String: Any] ?? row
        let domain = int(row["domain"]) ?? int(raw["domain"]) ?? int(raw["Domain"])
        let isBooking = domain == 100

        func num(_ keys: String...) -> Int? {
            for key in keys {
                if let v = int(row[key]) ?? int(raw[key]) { return v }
                if let fields = row["rawFields"] as? [String: String],
                   let s = fields[key], let v = Int(s) { return v }
            }
            return nil
        }

        var rental = num("rentalEntityId", "RentalTable_Id", "rentalTable_Id", "RentalTableId")
        var booking = num("bookingEntityId", "BookingTable_Id", "bookingTable_Id", "BookingTableId")
        let entity = num("entityId", "EntityId", "Id", "id", "rentalId")

        if isBooking {
            if booking == nil { booking = entity }
        } else if rental == nil {
            rental = entity
        }

        if rental == nil && booking == nil {
            if isBooking { booking = entity } else { rental = entity }
        }

        return (rental, booking)
    }

    private static func resolveEntityId(_ row: [String: Any]) -> Int? {
        let ids = resolveEntityIds(row)
        return ids.rental ?? ids.booking
    }

    private static func resolveVehicleEntityId(_ row: [String: Any]) -> String? {
        let candidates = [
            string(row["vehicleEntityId"]),
            string(row["CarTable_Id"]),
            string(row["carTable_Id"]),
            string(row["carId"]),
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

    private static func isPlateUnassigned(_ plate: String) -> Bool {
        let t = plate.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty || t == "-" || t == "—"
    }
}
