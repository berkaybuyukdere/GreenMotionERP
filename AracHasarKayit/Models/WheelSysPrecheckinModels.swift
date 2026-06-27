import Foundation

// MARK: - Pre-check-in context (mirrors `wheelsysGetPrecheckinContext`)
//
// Plain structs with manual `[String: Any]` parsing — matches the WheelSys
// damage-history model style and is robust to nulls / type drift from the
// backend bridge.

struct WheelSysPrecheckinRental {
    let rentalId: Int
    let rntNo: String?
    let resNo: String?
    let irn: String?
    let voucherNo: String?
    let confirmationNo: String?
}

struct WheelSysPrecheckinCustomer {
    let driverId: Int?
    let firstName: String?
    let lastName: String?
    let fullName: String
    let email: String?
}

struct WheelSysPrecheckinVehicle {
    let vehicleId: Int?
    let plateNo: String
    let normalizedPlateNo: String
    let model: String?
    let modelId: Int?
    let bookedGroup: String?
    let chargedGroup: String?
}

struct WheelSysPrecheckinMileageFuel {
    let checkoutMileage: Int?
    let checkoutFuel: Int?
    let currentReturnMileage: Int?
    let currentReturnFuel: Int?
    let milesDriven: Int?
}

struct WheelSysPrecheckinInsurance {
    let excessAmount: Double?
    let cdp: String?
    let insuranceCharge: Double?
    let damageCharge: Double?
    let damageExcess: Double?
    let currency: String
}

struct WheelSysPrecheckinBodyDiagram {
    let imageUrl: String?
    let width: Int?
    let height: Int?

    var hasResolvableImage: Bool {
        guard let imageUrl, !imageUrl.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return false
        }
        return true
    }
}

struct WheelSysPrecheckinDamagePosition {
    let x: Double?
    let y: Double?
    let markerWidth: Double?
    let markerHeight: Double?

    var hasCoordinates: Bool { x != nil && y != nil }
}

struct WheelSysPrecheckinDamageAttachment {
    let uid: String?
    let name: String?
    let previewable: Bool
    let previewPath: String?

    var canPreview: Bool {
        previewable && (previewPath?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false)
    }
}

struct WheelSysPrecheckinDamageFlags {
    let isReadOnly: Bool
    let isFixed: Bool
    let excessCovered: Bool
}

struct WheelSysPrecheckinDamage: Identifiable {
    let damageId: String
    let uid: String?
    let vehicleId: Int?
    let plateNo: String?
    let damageType: String?
    let actionName: String?
    let memo: String?
    let netCharge: Double?
    let relatedRentalNo: String?
    let addedByName: String?
    let entryDate: String?
    let position: WheelSysPrecheckinDamagePosition?
    let areaName: String?
    let elementName: String?
    let attachment: WheelSysPrecheckinDamageAttachment?
    let flags: WheelSysPrecheckinDamageFlags?

    var id: String { damageId }

    var displayTitle: String {
        let candidates = [damageType, areaName, elementName]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return candidates.first ?? "Unknown damage".localized
    }

    var areaElementText: String {
        [areaName, elementName]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
    }
}

struct WheelSysPrecheckinCarUsability {
    let isUsable: Bool
    let warnings: [String]
}

struct WheelSysPrecheckinStatus {
    let ready: Bool
    let blockers: [String]
    let warnings: [String]
}

struct WheelSysPrecheckinEligibility {
    let eligible: Bool
    let reasonCode: String?
    let reason: String?
    let pageTitle: String?
    let dbgInitialStatus: String?
    let rdStatus: String?
    let rdUsageType: String?
    let rdDispDocno_text: String?
    let rdRaDocNo_text: String?
    let rdResDocNo_text: String?
    let rdDateTo_text: String?
    let rdTimeTo_text: String?

    /// True when WheelSys allows PRECHECKIN on this rental page.
    var eligibleForPrecheckin: Bool { eligible }

    /// WheelSys page title for open returns is often "Review rental - RNT-…" (normal while out on rental).
    var isReviewRentalMode: Bool {
        pageTitle?.localizedCaseInsensitiveContains("Review rental") == true
    }

    /// Post pre-check-in state: rdStatus=3 and rdUsageType=2.
    var isAlreadyInCheckinReview: Bool {
        rdStatus == "3" && rdUsageType == "2"
    }
}

struct WheelSysPrecheckinContext {
    let rental: WheelSysPrecheckinRental
    let customer: WheelSysPrecheckinCustomer
    let vehicle: WheelSysPrecheckinVehicle
    let mileageFuel: WheelSysPrecheckinMileageFuel
    let insurance: WheelSysPrecheckinInsurance?
    let bodyDiagram: WheelSysPrecheckinBodyDiagram?
    let existingDamages: [WheelSysPrecheckinDamage]
    let carUsability: WheelSysPrecheckinCarUsability?
    let precheckinStatus: WheelSysPrecheckinStatus
    let eligibility: WheelSysPrecheckinEligibility?
    let syncedAt: String

    /// Combined warnings from car usability + pre-check-in status (deduplicated, order preserved).
    var combinedWarnings: [String] {
        var seen = Set<String>()
        var result: [String] = []
        for w in (carUsability?.warnings ?? []) + precheckinStatus.warnings {
            let trimmed = w.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, !seen.contains(trimmed) else { continue }
            seen.insert(trimmed)
            result.append(trimmed)
        }
        return result
    }

    var blockers: [String] {
        precheckinStatus.blockers
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    var canSubmit: Bool {
        if eligibility?.eligible == false { return false }
        if blockers.contains("rental_status_not_eligible") { return false }
        // Review-rental pages are valid precheck-in targets even when soft warnings exist.
        if eligibility?.isReviewRentalMode == true { return true }
        return true
    }

    var eligibilityDisplayMessage: String? {
        guard eligibility?.eligible == false || blockers.contains("rental_status_not_eligible") else {
            return nil
        }
        switch eligibility?.reasonCode {
        case "closed_status":
            return "wheelsys.precheckin.closed_status".localized
        case "title_closed":
            return "wheelsys.precheckin.title_closed".localized
        case "already_in_checkin_review":
            return "wheelsys.precheckin.already_checkin_review".localized
        default:
            break
        }
        if let reason = eligibility?.reason?.trimmingCharacters(in: .whitespacesAndNewlines), !reason.isEmpty {
            return reason
        }
        return precheckinStatus.warnings.first
            ?? "wheelsys.precheckin.status_not_eligible".localized
    }

    var statusIneligibleMessage: String? {
        eligibilityDisplayMessage
    }
}

// MARK: - Submit result (mirrors `wheelsysSubmitPrecheckin`)

struct WheelSysPrecheckinSubmitResult {
    let success: Bool
    let message: String?
    let rentalId: Int
    let rntNo: String?
    let resNo: String?
    let operation: String
    let afterSave: [String: Any]?
    let syncedAt: String
    let retryable: Bool
    let warnings: [String]
    let debug: WheelSysPrecheckinSubmitDebug?
}

struct WheelSysPrecheckinSubmitDebug {
    let httpStatus: Int?
    let responseLength: Int?
    let containsAfterSave: Bool
    let containsPrecheckin: Bool
    let containsRecordChanged: Bool
    let containsValidation: Bool
    let postbackSource: String?
    let sanitizedSnippet: String?
}
