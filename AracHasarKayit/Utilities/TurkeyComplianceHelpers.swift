import Foundation

/// Lists missing Turkey checkout / return compliance fields for on-screen feedback.
enum TurkeyComplianceHelpers {
    static func missingCheckoutLabels(
        nationalIdValid: Bool,
        termsSigned: Bool,
        exitPdfSigned: Bool,
        hasPhotos: Bool,
        requireNationalId: Bool = false
    ) -> [String] {
        var items: [String] = []
        if requireNationalId && !nationalIdValid {
            items.append("National ID".localized)
        }
        if !termsSigned {
            items.append("tr_checkout.kiosk_terms_missing".localized)
        }
        if !exitPdfSigned {
            items.append("tr_checkout.sign_exit_pdf".localized)
        }
        if !hasPhotos {
            items.append("Photos".localized)
        }
        return items
    }

    static func missingReturnLabels(
        nationalIdValid: Bool,
        returnPdfSigned: Bool,
        hasPhotos: Bool,
        customerRefusedSignature: Bool
    ) -> [String] {
        if customerRefusedSignature {
            return hasPhotos ? [] : ["Photos".localized]
        }
        var items: [String] = []
        if !returnPdfSigned {
            items.append("tr_return.sign_vehicle_pdf".localized)
        }
        if !hasPhotos {
            items.append("Photos".localized)
        }
        return items
    }

    static func formattedMissingList(_ labels: [String]) -> String {
        labels.map { "• \($0)" }.joined(separator: "\n")
    }
}
