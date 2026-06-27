import Foundation

// MARK: - Tab

enum WheelSysDailyViewTab: String, CaseIterable, Identifiable, Hashable {
    case checkouts
    case precheckins
    case checkins
    case cancellations
    case nonRevenue = "nonrevenue"
    case available
    case bookings

    var id: String { rawValue }

    /// Primary ops tabs shown in the WheelSys hub Daily View.
    static let hubTabs: [WheelSysDailyViewTab] = [
        .checkouts, .precheckins, .checkins, .cancellations,
    ]

    var titleKey: String {
        switch self {
        case .checkouts: return "wheelsys_daily.tab_checkouts"
        case .precheckins: return "wheelsys_daily.tab_precheckins"
        case .checkins: return "wheelsys_daily.tab_checkins"
        case .cancellations: return "wheelsys_daily.tab_cancellations"
        case .nonRevenue: return "wheelsys_daily.tab_non_revenue"
        case .available: return "wheelsys_daily.tab_available"
        case .bookings: return "wheelsys_daily.tab_bookings"
        }
    }

    var title: String { titleKey.localized }
}

// MARK: - UI row (shared across Daily View tabs)

struct WheelSysDailyViewRow: Identifiable, Hashable {
    let id: String
    let displayDocNo: String
    let plate: String
    let vehicleGroup: String
    let driverName: String
    let fuelText: String
    let timeText: String
    let model: String
    let mileage: Int?
    let availableUntil: String?
    let lastCheckIn: String?
    let statusBadges: [String]
    let bookingEntityId: Int?
    let isUnassigned: Bool
    let carGroup: String
    let dateFrom: Date?
    let dateTo: Date?
    let resNo: String?
    let station: String
    let agentName: String
    let detailFields: [String: String]
}

// MARK: - Typed tab rows

struct WheelSysDailyViewAllResult: Hashable {
    let selectedDate: String
    let station: String
    let checkouts: [WheelSysDailyViewCheckout]
    let precheckins: [WheelSysDailyViewPrecheckin]
    let checkins: [WheelSysDailyViewCheckin]
    let cancellations: [WheelSysDailyViewCancellation]
    let nonRevenue: [WheelSysDailyViewNonRevenue]
    let available: [WheelSysDailyViewAvailable]
    let bookings: [WheelSysDailyViewBooking]
}

struct WheelSysDailyViewCheckout: Identifiable, Hashable {
    let id: String
    let displayDocNo: String
    let confirmationNo: String
    let driverName: String
    let plate: String
    let normalizedPlate: String
    let carGroup: String
    let carGroupInv: String
    let fuel: Int?
    let dateFrom: String?
    let dateTo: String?
    let status: String
    let voucherNo: String?
    let irn: String?
    let domain: Int?
    let rentalEntityId: Int?
    let isUnassigned: Bool
    let rawFields: [String: String]
}

struct WheelSysDailyViewCheckin: Identifiable, Hashable {
    let id: String
    let displayDocNo: String
    let driverName: String
    let plate: String
    let normalizedPlate: String
    let mileage: Int?
    let fuel: Int?
    let dateFrom: String?
    let dateTo: String?
    let status: String
    let voucherNo: String?
    let domain: Int?
    let rentalEntityId: Int?
    let vehicleEntityId: String?
    let rawFields: [String: String]
}

struct WheelSysDailyViewPrecheckin: Identifiable, Hashable {
    let id: String
    let displayDocNo: String
    let confirmationNo: String
    let driverName: String
    let plate: String
    let normalizedPlate: String
    let carGroup: String
    let mileage: Int?
    let fuel: Int?
    let dateFrom: String?
    let dateTo: String?
    let status: String
    let stationTo: String?
    let rentalEntityId: Int?
    let rawFields: [String: String]
}

struct WheelSysDailyViewCancellation: Identifiable, Hashable {
    let id: String
    let displayDocNo: String
    let confirmationNo: String
    let driverName: String
    let plate: String
    let normalizedPlate: String
    let carGroup: String
    let dateFrom: String?
    let dateTo: String?
    let cancellationName: String
    let cancellationDate: String?
    let status: String
    let rentalEntityId: Int?
    let rawFields: [String: String]
}

struct WheelSysDailyViewNonRevenue: Identifiable, Hashable {
    let id: String
    let displayDocNo: String
    let dateFrom: String?
    let dateTo: String?
    let plate: String
    let normalizedPlate: String
    let modelName: String
    let drivenByName: String
    let nonRevenueTypeName: String
    let remarks: String?
    let domain: Int?
    let rawFields: [String: String]
}

struct WheelSysDailyViewAvailable: Identifiable, Hashable {
    let vehicleEntityId: String
    let plate: String
    let normalizedPlate: String
    let group: String
    let grpCode: String
    let model: String
    let station: String
    let mileage: Int
    let fuel: Int?
    let availableUntil: String?
    let lastCheckin: String?
    let lastCheckinLocation: String?
    let active: Bool
    let inUse: Bool
    let hardHold: Bool
    let onService: Bool
    let vin: String?
    let rawFields: [String: String]

    var id: String { vehicleEntityId.isEmpty ? normalizedPlate : vehicleEntityId }
}

struct WheelSysDailyViewBooking: Identifiable, Hashable {
    let id: String
    let entityId: Int?
    let usageType: String?
    let sstr: String?
    let irn: String?
    let dateFrom: String?
    let dateTo: String?
    let displayDocNo: String
    let carGroup: String
    let carGroupInv: String
    let driverName: String
    let agent: String?
    let rpd: String?
    let resDate: String?
    let voucherNo: String?
    let rawFields: [String: String]
}

// MARK: - Typed → UI row mapping

enum WheelSysDailyViewRowMapper {

    static func rows(
        from result: WheelSysDailyViewAllResult,
        tab: WheelSysDailyViewTab
    ) -> [WheelSysDailyViewRow] {
        switch tab {
        case .checkouts:
            return result.checkouts.map { mapCheckout($0, station: result.station) }
        case .precheckins:
            return result.precheckins.map { mapPrecheckin($0, station: result.station) }
        case .checkins:
            return result.checkins.map { mapCheckin($0, station: result.station) }
        case .cancellations:
            return result.cancellations.map { mapCancellation($0, station: result.station) }
        case .nonRevenue:
            return result.nonRevenue.map { mapNonRevenue($0, station: result.station) }
        case .available:
            return result.available.map { mapAvailable($0) }
        case .bookings:
            return result.bookings.map { mapBooking($0, station: result.station) }
        }
    }

    static func rows(from payload: WheelSysDailyViewTabPayload) -> [WheelSysDailyViewRow] {
        switch payload.rows {
        case .checkouts(let rows):
            return rows.map { mapCheckout($0, station: payload.station) }
        case .precheckins(let rows):
            return rows.map { mapPrecheckin($0, station: payload.station) }
        case .checkins(let rows):
            return rows.map { mapCheckin($0, station: payload.station) }
        case .cancellations(let rows):
            return rows.map { mapCancellation($0, station: payload.station) }
        case .nonRevenue(let rows):
            return rows.map { mapNonRevenue($0, station: payload.station) }
        case .available(let rows):
            return rows.map { mapAvailable($0) }
        case .bookings(let rows):
            return rows.map { mapBooking($0, station: payload.station) }
        }
    }

    private static func mapCheckout(_ row: WheelSysDailyViewCheckout, station: String) -> WheelSysDailyViewRow {
        let dateFrom = parseDate(row.dateFrom)
        let dateTo = parseDate(row.dateTo)
        return WheelSysDailyViewRow(
            id: row.id,
            displayDocNo: row.displayDocNo.isEmpty ? row.confirmationNo : row.displayDocNo,
            plate: row.plate,
            vehicleGroup: row.carGroup.isEmpty ? row.carGroupInv : row.carGroup,
            driverName: row.driverName,
            fuelText: row.fuel.map(String.init) ?? "—",
            timeText: formatTime(from: dateFrom ?? dateTo),
            model: "",
            mileage: nil,
            availableUntil: nil,
            lastCheckIn: nil,
            statusBadges: row.status.isEmpty ? [] : [row.status],
            bookingEntityId: row.rentalEntityId,
            isUnassigned: row.isUnassigned,
            carGroup: row.carGroup,
            dateFrom: dateFrom,
            dateTo: dateTo,
            resNo: row.confirmationNo.isEmpty ? row.displayDocNo : row.confirmationNo,
            station: station,
            agentName: agentName(from: row.rawFields),
            detailFields: row.rawFields
        )
    }

    private static func mapPrecheckin(_ row: WheelSysDailyViewPrecheckin, station: String) -> WheelSysDailyViewRow {
        let dateFrom = parseDate(row.dateFrom)
        let dateTo = parseDate(row.dateTo)
        return WheelSysDailyViewRow(
            id: row.id,
            displayDocNo: row.displayDocNo,
            plate: row.plate,
            vehicleGroup: row.carGroup,
            driverName: row.driverName,
            fuelText: row.fuel.map(String.init) ?? "—",
            timeText: formatTime(from: dateTo ?? dateFrom),
            model: "",
            mileage: row.mileage,
            availableUntil: nil,
            lastCheckIn: nil,
            statusBadges: row.status.isEmpty ? [] : [row.status],
            bookingEntityId: row.rentalEntityId,
            isUnassigned: false,
            carGroup: row.carGroup,
            dateFrom: dateFrom,
            dateTo: dateTo,
            resNo: row.confirmationNo.isEmpty ? row.displayDocNo : row.confirmationNo,
            station: row.stationTo ?? station,
            agentName: agentName(from: row.rawFields),
            detailFields: row.rawFields
        )
    }

    private static func mapCancellation(_ row: WheelSysDailyViewCancellation, station: String) -> WheelSysDailyViewRow {
        let dateFrom = parseDate(row.dateFrom)
        let dateTo = parseDate(row.dateTo)
        var badges: [String] = []
        if !row.cancellationName.isEmpty { badges.append(row.cancellationName) }
        return WheelSysDailyViewRow(
            id: row.id,
            displayDocNo: row.displayDocNo,
            plate: row.plate,
            vehicleGroup: row.carGroup,
            driverName: row.driverName,
            fuelText: "—",
            timeText: formatTime(from: parseDate(row.cancellationDate) ?? dateFrom),
            model: "",
            mileage: nil,
            availableUntil: nil,
            lastCheckIn: nil,
            statusBadges: badges,
            bookingEntityId: row.rentalEntityId,
            isUnassigned: false,
            carGroup: row.carGroup,
            dateFrom: dateFrom,
            dateTo: dateTo,
            resNo: row.confirmationNo.isEmpty ? row.displayDocNo : row.confirmationNo,
            station: station,
            agentName: agentName(from: row.rawFields),
            detailFields: row.rawFields
        )
    }

    private static func mapCheckin(_ row: WheelSysDailyViewCheckin, station: String) -> WheelSysDailyViewRow {
        let dateFrom = parseDate(row.dateFrom)
        let dateTo = parseDate(row.dateTo)
        return WheelSysDailyViewRow(
            id: row.id,
            displayDocNo: row.displayDocNo,
            plate: row.plate,
            vehicleGroup: "",
            driverName: row.driverName,
            fuelText: row.fuel.map(String.init) ?? "—",
            timeText: formatTime(from: dateTo ?? dateFrom),
            model: "",
            mileage: row.mileage,
            availableUntil: nil,
            lastCheckIn: nil,
            statusBadges: row.status.isEmpty ? [] : [row.status],
            bookingEntityId: row.rentalEntityId,
            isUnassigned: false,
            carGroup: "",
            dateFrom: dateFrom,
            dateTo: dateTo,
            resNo: row.displayDocNo,
            station: station,
            agentName: agentName(from: row.rawFields),
            detailFields: row.rawFields
        )
    }

    private static func mapNonRevenue(_ row: WheelSysDailyViewNonRevenue, station: String) -> WheelSysDailyViewRow {
        let dateFrom = parseDate(row.dateFrom)
        let dateTo = parseDate(row.dateTo)
        var badges: [String] = []
        if !row.nonRevenueTypeName.isEmpty { badges.append(row.nonRevenueTypeName) }
        return WheelSysDailyViewRow(
            id: row.id,
            displayDocNo: row.displayDocNo,
            plate: row.plate,
            vehicleGroup: "",
            driverName: row.drivenByName,
            fuelText: "—",
            timeText: formatTime(from: dateFrom ?? dateTo),
            model: row.modelName,
            mileage: nil,
            availableUntil: nil,
            lastCheckIn: nil,
            statusBadges: badges,
            bookingEntityId: nil,
            isUnassigned: false,
            carGroup: "",
            dateFrom: dateFrom,
            dateTo: dateTo,
            resNo: row.displayDocNo,
            station: station,
            agentName: agentName(from: row.rawFields),
            detailFields: row.rawFields
        )
    }

    private static func mapAvailable(_ row: WheelSysDailyViewAvailable) -> WheelSysDailyViewRow {
        var badges: [String] = []
        if row.active { badges.append("Active") }
        if row.inUse { badges.append("In Use") }
        if row.onService { badges.append("Service") }
        if row.hardHold { badges.append("Hold") }
        return WheelSysDailyViewRow(
            id: row.id,
            displayDocNo: row.plate,
            plate: row.plate,
            vehicleGroup: row.group,
            driverName: "",
            fuelText: row.fuel.map(String.init) ?? "—",
            timeText: "",
            model: row.model,
            mileage: row.mileage,
            availableUntil: row.availableUntil,
            lastCheckIn: row.lastCheckin,
            statusBadges: badges,
            bookingEntityId: nil,
            isUnassigned: false,
            carGroup: row.group,
            dateFrom: parseDate(row.availableUntil),
            dateTo: nil,
            resNo: nil,
            station: row.station,
            agentName: agentName(from: row.rawFields),
            detailFields: row.rawFields
        )
    }

    private static func mapBooking(_ row: WheelSysDailyViewBooking, station: String) -> WheelSysDailyViewRow {
        let dateFrom = parseDate(row.dateFrom)
        let dateTo = parseDate(row.dateTo)
        return WheelSysDailyViewRow(
            id: row.id,
            displayDocNo: row.displayDocNo,
            plate: "",
            vehicleGroup: row.carGroup.isEmpty ? row.carGroupInv : row.carGroup,
            driverName: row.driverName,
            fuelText: "—",
            timeText: formatTime(from: dateFrom ?? dateTo),
            model: "",
            mileage: nil,
            availableUntil: nil,
            lastCheckIn: nil,
            statusBadges: [],
            bookingEntityId: row.entityId,
            isUnassigned: true,
            carGroup: row.carGroup,
            dateFrom: dateFrom,
            dateTo: dateTo,
            resNo: row.displayDocNo,
            station: station,
            agentName: agentName(from: row.rawFields),
            detailFields: row.rawFields
        )
    }

    private static func agentName(from rawFields: [String: String]) -> String {
        for key in ["agent", "Agent", "booker", "Booker"] {
            let value = rawFields[key]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !value.isEmpty, value != "<null>" { return value }
        }
        return ""
    }

    private static func parseDate(_ raw: String?) -> Date? {
        guard let raw, !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return WheelSysJournalService.parseFleetEventDate(raw)
    }

    private static func formatTime(from date: Date?) -> String {
        guard let date else { return "" }
        let df = DateFormatter()
        df.timeZone = WheelSysJournalService.zurichCalendar.timeZone
        df.dateFormat = "HH:mm"
        return df.string(from: date)
    }
}

// MARK: - Search helpers

enum WheelSysDailyViewFilter {

    static func matches(_ haystack: String, query: String) -> Bool {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return true }
        return haystack.localizedCaseInsensitiveContains(q)
    }

    static func filterRows(_ rows: [WheelSysDailyViewRow], query: String) -> [WheelSysDailyViewRow] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return rows }
        return rows.filter { row in
            matches(row.displayDocNo, query: q)
                || matches(row.plate, query: q)
                || matches(row.driverName, query: q)
                || matches(row.resNo ?? "", query: q)
                || matches(row.vehicleGroup, query: q)
        }
    }
}
