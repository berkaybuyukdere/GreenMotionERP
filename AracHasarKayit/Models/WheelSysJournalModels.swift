import Foundation

// MARK: - Journal row

enum WheelSysJournalRowKind: String, Hashable, Codable {
    case checkout
    case `return`
}

enum WheelSysJournalEnrichmentStatus: String, Hashable, Codable {
    case notLoaded
    case loading
    case loaded
    case failed
}

struct WheelSysJournalRow: Identifiable, Hashable {
    let id: String
    let kind: WheelSysJournalRowKind
    var rowNumber: Int
    let plate: String
    let normalizedPlate: String
    let resourceId: String
    let model: String
    let station: String
    let vehicleGroup: String
    let eventStart: Date?
    let eventEnd: Date?
    /// Primary sort/display time — start for checkout, end for return.
    let eventDateTime: Date
    let rentalEntityId: Int
    /// Booking entity id for unassigned rows (domain 100).
    var bookingEntityId: Int?
    let rentalUrl: String
    let driverNameFromFleet: String
    /// RES / confirmation code (bold in journal UI).
    let resCode: String
    /// WheelSys display document number (e.g. rental doc label).
    let displayDocNo: String
    var rentalTitle: String?
    var rentalNumber: String?
    var enrichmentStatus: WheelSysJournalEnrichmentStatus
    /// Fleet event type: rental or booking.
    var eventType: String = "rental"
    /// True when no plate assigned yet (booking row).
    var isUnassigned: Bool = false
    var isAssigned: Bool { !isUnassigned && !plate.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    /// Entity id to use for booking.aspx assign/preview on unassigned rows.
    var effectiveBookingEntityId: Int {
        if isUnassigned, let bookingEntityId, bookingEntityId > 0 { return bookingEntityId }
        return rentalEntityId
    }

    static func rentalPageURL(entityId: Int) -> String {
        "https://ch.wheelsys.greenmotion.com/ui/manage/master/rental.aspx?entityId=\(entityId)"
    }

    static func bookingPageURL(entityId: Int) -> String {
        "https://ch.wheelsys.greenmotion.com/ui/manage/master/booking.aspx?entityId=\(entityId)"
    }
}

/// Prefill for CH checkout after journal row selection.
struct WheelSysCheckoutPrefill: Hashable {
    let bookingEntityId: Int
    let resNo: String
    let customerName: String?
    let vehicleGroup: String
    let eventDateTime: Date?
    let assignedPlate: String?
    let isUnassigned: Bool
}

// MARK: - Journal API snapshot (journal.aspx/GetDetailsRecords)

struct WheelSysJournalSnapshot: Hashable {
    let selectedDate: String
    let station: String
    let checkOuts: [WheelSysJournalCheckout]
    let checkIns: [WheelSysJournalCheckin]
    let availableVehicles: [WheelSysJournalVehicleAvailability]
    let source: String

    var checkoutCount: Int { checkOuts.count }
    var checkinCount: Int { checkIns.count }
    var availableCount: Int { availableVehicles.count }
}

struct WheelSysJournalCheckout: Identifiable, Hashable {
    let id: String
    let displayDocNo: String
    let confirmationNo: String
    /// WheelSys reservation code (RES-12345).
    let resNo: String
    let driverName: String
    let plate: String
    let normalizedPlate: String
    let carGroup: String
    let carGroupInv: String
    let fuel: Int?
    let dateFrom: String?
    let dateTo: String?
    let status: String
    let agent: String
    let domain: Int?
    let rentalEntityId: Int?
    let bookingEntityId: Int?
    let stationTo: String?
    let isUnassigned: Bool
    let rawFields: [String: String]

    /// The real RES code (e.g. "RES-17694") — from displayDocNo or resNo.
    var reservationCode: String {
        // displayDocNo IS the RES number from Wheelsys (rdDispDocno_text / displaydocno).
        if WheelSysResCode.isReservationCode(displayDocNo) { return displayDocNo }
        if WheelSysResCode.isReservationCode(resNo) { return resNo }
        return ""
    }

    /// The external/agent confirmation code (e.g. "JIG(A)-6813462-67939").
    /// Always use confirmationNo — never use the RES field for this.
    var agentConfirmationCode: String {
        return confirmationNo
    }

    var resNoLegacy: String {
        reservationCode.isEmpty ? confirmationNo : reservationCode
    }
}

struct WheelSysJournalCheckin: Identifiable, Hashable {
    let id: String
    let displayDocNo: String
    let confirmationNo: String
    let resNo: String
    let driverName: String
    let plate: String
    let normalizedPlate: String
    let carGroup: String
    let carGroupInv: String
    let fuel: Int?
    let mileage: Int?
    let dateFrom: String?
    let dateTo: String?
    let status: String
    let agent: String
    let domain: Int?
    let rentalEntityId: Int?
    let bookingEntityId: Int?
    let vehicleEntityId: String?
    let stationFrom: String?
    let balance: String?
    let model: String?
    let rawFields: [String: String]

    /// The real RES code (e.g. "RES-17694") — from displayDocNo or resNo.
    var reservationCode: String {
        if WheelSysResCode.isReservationCode(displayDocNo) { return displayDocNo }
        if WheelSysResCode.isReservationCode(resNo) { return resNo }
        return ""
    }

    /// The external/agent confirmation code (e.g. "JIG(A)-6813462-67939").
    var agentConfirmationCode: String {
        return confirmationNo
    }
}

struct WheelSysJournalVehicleAvailability: Identifiable, Hashable {
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
    let active: Bool
    let inUse: Bool
    let hardHold: Bool
    let onService: Bool
    let vin: String?
    let rawFields: [String: String]

    var id: String { vehicleEntityId.isEmpty ? normalizedPlate : vehicleEntityId }
}

// MARK: - Journal API → UI row mapping

enum WheelSysJournalRowMapper {

    static func checkoutRows(from snapshot: WheelSysJournalSnapshot) -> [WheelSysJournalRow] {
        snapshot.checkOuts.enumerated().map { index, row in
            toJournalRow(row, kind: .checkout, rowNumber: index + 1)
        }
    }

    static func returnRows(from snapshot: WheelSysJournalSnapshot) -> [WheelSysJournalRow] {
        snapshot.checkIns.enumerated().map { index, row in
            toJournalRow(row, kind: .return, rowNumber: index + 1)
        }
    }

    private static func toJournalRow(
        _ checkout: WheelSysJournalCheckout,
        kind: WheelSysJournalRowKind,
        rowNumber: Int
    ) -> WheelSysJournalRow {
        let entityId = checkout.rentalEntityId ?? checkout.bookingEntityId ?? 0
        let bookingId = checkout.bookingEntityId
        let eventDateTime = resolveEventDate(
            primary: kind == .checkout ? checkout.dateFrom : checkout.dateTo,
            fallback: kind == .checkout ? checkout.dateTo : checkout.dateFrom
        )
        let unassigned = checkout.isUnassigned

        return WheelSysJournalRow(
            id: "api-\(kind.rawValue)-\(entityId)-\(rowNumber)-\(checkout.displayDocNo)",
            kind: kind,
            rowNumber: rowNumber,
            plate: checkout.plate,
            normalizedPlate: checkout.normalizedPlate,
            resourceId: checkout.rawFields["id"] ?? "",
            model: "",
            station: checkout.stationTo ?? "",
            vehicleGroup: checkout.carGroup.isEmpty ? checkout.carGroupInv : checkout.carGroup,
            eventStart: parseOptionalDate(checkout.dateFrom),
            eventEnd: parseOptionalDate(checkout.dateTo),
            eventDateTime: eventDateTime,
            rentalEntityId: entityId,
            bookingEntityId: bookingId,
            rentalUrl: unassigned
                ? WheelSysJournalRow.bookingPageURL(entityId: bookingId ?? entityId)
                : WheelSysJournalRow.rentalPageURL(entityId: entityId),
            driverNameFromFleet: checkout.driverName,
            resCode: checkout.reservationCode.isEmpty ? checkout.agentConfirmationCode : checkout.reservationCode,
            displayDocNo: checkout.agentConfirmationCode,
            rentalTitle: nil,
            rentalNumber: checkout.confirmationNo.isEmpty
                ? WheelSysJournalService.parseRentalNumber(from: checkout.displayDocNo)
                : checkout.confirmationNo,
            enrichmentStatus: .notLoaded,
            eventType: (checkout.domain == 100) ? "booking" : "rental",
            isUnassigned: unassigned
        )
    }

    private static func toJournalRow(
        _ checkin: WheelSysJournalCheckin,
        kind: WheelSysJournalRowKind,
        rowNumber: Int
    ) -> WheelSysJournalRow {
        let entityId = checkin.rentalEntityId ?? checkin.bookingEntityId ?? 0
        let eventDateTime = resolveEventDate(primary: checkin.dateTo, fallback: checkin.dateFrom)
        let plate = checkin.plate
        let unassigned = plate.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

        return WheelSysJournalRow(
            id: "api-\(kind.rawValue)-\(entityId)-\(rowNumber)-\(checkin.displayDocNo)",
            kind: kind,
            rowNumber: rowNumber,
            plate: plate,
            normalizedPlate: checkin.normalizedPlate,
            resourceId: checkin.vehicleEntityId ?? "",
            model: checkin.model ?? "",
            station: checkin.stationFrom ?? "",
            vehicleGroup: checkin.carGroup.isEmpty ? checkin.carGroupInv : checkin.carGroup,
            eventStart: parseOptionalDate(checkin.dateFrom),
            eventEnd: parseOptionalDate(checkin.dateTo),
            eventDateTime: eventDateTime,
            rentalEntityId: entityId,
            bookingEntityId: checkin.bookingEntityId,
            rentalUrl: WheelSysJournalRow.rentalPageURL(entityId: entityId),
            driverNameFromFleet: checkin.driverName,
            resCode: checkin.reservationCode.isEmpty ? checkin.agentConfirmationCode : checkin.reservationCode,
            displayDocNo: checkin.agentConfirmationCode,
            rentalTitle: nil,
            rentalNumber: checkin.confirmationNo.isEmpty
                ? WheelSysJournalService.parseRentalNumber(from: checkin.displayDocNo)
                : checkin.confirmationNo,
            enrichmentStatus: .notLoaded,
            eventType: "rental",
            isUnassigned: unassigned
        )
    }

    private static func resolveEventDate(primary: String?, fallback: String?) -> Date {
        if let primary, let date = parseOptionalDate(primary) { return date }
        if let fallback, let date = parseOptionalDate(fallback) { return date }
        return Date()
    }

    private static func parseOptionalDate(_ raw: String?) -> Date? {
        guard let raw, !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return WheelSysJournalService.parseFleetEventDate(raw)
    }
}

// MARK: - Rental detail (parsed from rental.aspx)

struct WheelSysRentalDetail: Hashable {
    let rentalEntityId: Int
    let status: Int
    let htmlLength: Int
    let title: String?
    let rentalNumber: String?
    let customerName: String?
    let driverId: String?
    let reservationDateText: String?
    let driverInfoJson: String?
    let agentBooker: String?
    let checkoutLocation: String?
    let checkinLocation: String?
    let mileageOutText: String?
    let mileageOutHidden: String?
    let mileageInText: String?
    let mileageInHidden: String?
    let fuelOutText: String?
    let fuelOutHidden: String?
    let fuelInText: String?
    let fuelInHidden: String?
    let rawFieldSnapshot: [String: String]
}

// MARK: - Diagnostics (debug field inventory)

struct WheelSysRentalFieldDiagnostic: Hashable, Identifiable {
    var id: String { "\(name)-\(idAttr)" }
    let idAttr: String
    let name: String
    let type: String
    let valuePreview: String
}

struct WheelSysRentalSelectDiagnostic: Hashable, Identifiable {
    var id: String { "\(name)-\(idAttr)" }
    let idAttr: String
    let name: String
    let selectedValue: String
    let selectedText: String
}

struct WheelSysRentalTextareaDiagnostic: Hashable, Identifiable {
    var id: String { "\(name)-\(idAttr)" }
    let idAttr: String
    let name: String
    let valuePreview: String
}

struct WheelSysRentalDiagnostics: Hashable {
    let entityId: Int
    let status: Int
    let htmlLength: Int
    let title: String
    let inputs: [WheelSysRentalFieldDiagnostic]
    let selects: [WheelSysRentalSelectDiagnostic]
    let textareas: [WheelSysRentalTextareaDiagnostic]
    let visibleTextPreview: String
}
