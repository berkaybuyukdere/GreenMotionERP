import Foundation

enum WheelSysReturnEntryPoint: String, Hashable, Codable {
    case journalReturn = "journal_return"
    case plateScanReturn = "plate_scan_return"
}

/// Active rental candidate for return / check-in mileage update.
struct WheelSysReturnCandidate: Identifiable, Hashable {
    let id: String
    let rentalEntityId: Int
    let vehicleEntityId: String?
    let plate: String
    let normalizedPlate: String
    let resNo: String
    let raNo: String?
    let irn: String?
    let driverName: String
    let model: String?
    let station: String
    let dateFrom: String?
    let dateTo: String?
    let checkoutMileage: Int?
    let checkoutFuel: Int?
    let source: String

    var displayTitle: String {
        let ra = raNo?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !ra.isEmpty { return ra }
        let res = resNo.trimmingCharacters(in: .whitespacesAndNewlines)
        return res.isEmpty ? "Rental #\(rentalEntityId)" : res
    }
}

struct WheelSysReturnUpdateRequest: Hashable {
    let franchiseId: String
    let rentalEntityId: Int
    let resNo: String
    let plate: String
    let checkInMileage: Int
    let checkInFuel: Int
    let checkInUserId: String?
    let vehicleEntityIdHint: String?
    let fleetCarId: String?
    let entryPoint: WheelSysReturnEntryPoint
    let station: String
    let addAutoNotes: Bool
    let actualCheckInDateTime: Date?
}

struct WheelSysReturnSaveResult: Hashable {
    let success: Bool
    let message: String
    let mileageFrom: Int?
    let mileageTo: Int?
    let milesDriven: Int?
    let fuelTo: Int?
    let verifiedMileageTo: Int?
    let vehicleEntityId: String?
    let dailyViewAvailableVerified: Bool?
    let verificationPending: Bool
    let verificationAttempts: Int?
    let entryPoint: WheelSysReturnEntryPoint
}

struct WheelSysReturnVerificationResult: Hashable {
    let verified: Bool
    let attempts: Int
    let mileage: Int?
    let fuel: Int?
    let pending: Bool
}

/// Prefill for CH return (`IadeIslemView`) opened from WheelSys journal or plate scan.
/// Normalizes WheelSys km/fuel where 0 means "not checked in yet".
enum WheelSysReturnMileageFuel {
    /// Valid return km hint only when WheelSys has a positive check-in odometer.
    static func effectiveCheckinMileage(_ value: Int?) -> Int? {
        guard let value, value > 0 else { return nil }
        return value
    }

    /// Prefer a positive check-in fuel; fall back to checkout/master when WheelSys shows 0/8.
    static func effectiveCheckinFuel(_ value: Int?, checkout: Int?) -> Int? {
        if let value, value > 0 { return value }
        if let checkout, checkout > 0 { return checkout }
        return nil
    }

    static func defaultReturnFuel(checkin: Int?, checkout: Int?) -> Int {
        effectiveCheckinFuel(checkin, checkout: checkout) ?? 8
    }
}

struct WheelSysReturnOperationPrefill: Equatable {
    let rentalEntityId: Int
    let resNo: String
    let raNo: String?
    let confirmationNo: String?
    let driverName: String
    let customerEmail: String?
    let vehicleEntityId: String?
    let checkoutMileage: Int?
    let checkoutFuel: Int?
    let checkinMileageHint: Int?
    let checkinFuelHint: Int?
    let dateFrom: Date?
    let dateTo: Date?
    let entryPoint: WheelSysReturnEntryPoint
}

struct WheelSysIadeReturnContext: Identifiable {
    let arac: Arac
    let prefill: WheelSysReturnOperationPrefill
    var id: String { "\(prefill.rentalEntityId)-\(prefill.entryPoint.rawValue)" }
}

/// Rental identity locked after a successful pre-check-in.
/// Return flow must keep this entity directly and never re-resolve via RES search
/// (RES can point to a booking without a vehicle).
struct WheelSysLockedRentalContext: Equatable {
    let rentalId: Int
    let vehicleId: String?
    let plate: String
    let resNo: String?
    let rntNo: String?
}
