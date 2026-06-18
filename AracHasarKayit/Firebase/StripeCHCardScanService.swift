import Foundation
import FirebaseAuth
import FirebaseFirestore
import StripeCardScan
import StripeCore
import StripePayments
import UIKit

/// Result of scanning + validating a card (PAN never persisted).
struct CHScannedCardResult {
    let last4: String
    /// e.g. `XXXX XXXX XXXX 1234` — full PAN is never stored or shown.
    let maskedDisplay: String
    let brandName: String
    let isValid: Bool
    let validationMessage: String
    let scannedAt: Date
}

enum StripeCHCardScanServiceError: LocalizedError {
    case notAuthenticated
    case saveFailed
    case cancelled

    var errorDescription: String? {
        switch self {
        case .notAuthenticated: return "You must be signed in.".localized
        case .saveFailed: return "Could not save card scan record.".localized
        case .cancelled: return nil
        }
    }
}

/// Stripe CardScan + Luhn validation. Stores only last4 / brand (PCI-safe).
enum StripeCHCardScanService {

    private static var configured = false

    static func configureIfNeeded() {
        let key = StripeCHConfig.publishableKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return }
        guard !configured || STPAPIClient.shared.publishableKey != key else { return }
        STPAPIClient.shared.publishableKey = key
        configured = true
    }

    /// Masks all digits except the last four (e.g. `XXXX XXXX XXXX 4242`).
    static func maskedDisplay(forPAN pan: String) -> String {
        let digits = pan.filter(\.isNumber)
        guard digits.count >= 4 else {
            return String(repeating: "X", count: max(4, digits.count))
        }
        let last4 = String(digits.suffix(4))
        let maskCount = digits.count - 4
        let raw = String(repeating: "X", count: maskCount) + last4
        var grouped = ""
        for (index, character) in raw.enumerated() {
            if index > 0, index % 4 == 0 { grouped.append(" ") }
            grouped.append(character)
        }
        return grouped
    }

    static func maskedDisplay(last4: String, assumedLength: Int = 16) -> String {
        let safeLast4 = String(last4.filter(\.isNumber).suffix(4))
        let length = max(4, assumedLength)
        let maskCount = length - 4
        let raw = String(repeating: "X", count: maskCount) + safeLast4
        var grouped = ""
        for (index, character) in raw.enumerated() {
            if index > 0, index % 4 == 0 { grouped.append(" ") }
            grouped.append(character)
        }
        return grouped
    }

    static func validate(pan: String) -> CHScannedCardResult {
        let digits = pan.filter(\.isNumber)
        let last4 = String(digits.suffix(4))
        let masked = maskedDisplay(forPAN: digits)
        let brand = STPCardValidator.brand(forNumber: digits)
        let brandName = STPCard.string(from: brand)
        let state = STPCardValidator.validationState(
            forNumber: digits,
            validatingCardBrand: true
        )
        let isValid = state == .valid
        let message: String
        switch state {
        case .valid:
            message = "ch_stripe.card_valid".localized
        case .invalid:
            message = "ch_stripe.card_invalid".localized
        case .incomplete:
            message = "ch_stripe.card_incomplete".localized
        @unknown default:
            message = "ch_stripe.card_unknown".localized
        }
        return CHScannedCardResult(
            last4: last4,
            maskedDisplay: masked,
            brandName: brandName,
            isValid: isValid,
            validationMessage: message,
            scannedAt: Date()
        )
    }

    /// Presents Stripe `CardScanSheet`. Completion is always called (including cancel).
    static func presentScan(
        from presenter: UIViewController,
        onComplete: @escaping (Result<CHScannedCardResult, Error>) -> Void
    ) {
        configureIfNeeded()
        let sheet = CardScanSheet()
        sheet.present(from: presenter) { result in
            switch result {
            case .completed(let scanned):
                let validated = validate(pan: scanned.pan)
                onComplete(.success(validated))
            case .canceled:
                onComplete(.failure(StripeCHCardScanServiceError.cancelled))
            case .failed(let error):
                onComplete(.failure(error))
            }
        }
    }

    /// Saves scan metadata to Firestore (never full card number).
    static func saveScanRecord(
        franchiseId: String,
        result: CHScannedCardResult,
        customerReference: String,
        plate: String,
        description: String
    ) async throws {
        guard let uid = Auth.auth().currentUser?.uid else {
            throw StripeCHCardScanServiceError.notAuthenticated
        }
        let fid = franchiseId.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let ref = Firestore.firestore()
            .collection("franchises").document(fid)
            .collection("cardScans")
            .document()

        let payload: [String: Any] = [
            "franchiseId": fid,
            "last4": result.last4,
            "brand": result.brandName,
            "isValid": result.isValid,
            "validationMessage": result.validationMessage,
            "customerReference": customerReference,
            "plate": plate,
            "description": description,
            "createdByUid": uid,
            "createdAt": FieldValue.serverTimestamp(),
        ]
        do {
            try await ref.setData(payload)
        } catch {
            throw StripeCHCardScanServiceError.saveFailed
        }
    }
}
