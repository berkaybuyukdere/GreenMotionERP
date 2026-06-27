import Foundation
import SwiftUI

enum ProcessPhotoStampLabels {
    /// Damage-only: first photo = HANDOVER, rest = RETURN.
    struct Stamp {
        let labelKey: String
        let date: Date
        var localizedLabel: String { labelKey.localized }
    }

    static func damagePhotoStamp(globalIndex: Int, handoverDate: Date, returnDate: Date) -> Stamp {
        if globalIndex == 0 {
            return Stamp(labelKey: "HANDOVER", date: handoverDate)
        }
        return Stamp(labelKey: "RETURN", date: returnDate)
    }

    /// Legacy alias — damage flows only.
    static func stamp(globalIndex: Int, handoverDate: Date, returnDate: Date) -> Stamp {
        damagePhotoStamp(globalIndex: globalIndex, handoverDate: handoverDate, returnDate: returnDate)
    }

    /// Checkout/return photos: index only (no HANDOVER/RETURN wording).
    static func processPhotoIndexLabel(_ globalIndex: Int) -> String {
        "\(globalIndex + 1)"
    }

    /// Checkout/return photos: process date caption.
    static func processPhotoDateCaption(_ date: Date, includeTime: Bool) -> String {
        formatDisplayDate(date, includeTime: includeTime)
    }

    static func formatDisplayDate(_ date: Date, includeTime: Bool) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.calendar = Calendar(identifier: .gregorian)
        f.dateFormat = includeTime ? "dd.MM.yyyy HH:mm" : "dd.MM.yyyy"
        return f.string(from: date)
    }

    static func formatPDFDate(_ date: Date, includeTime: Bool) -> String {
        formatDisplayDate(date, includeTime: includeTime)
    }

    static func formatPDFTime(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.calendar = Calendar(identifier: .gregorian)
        f.dateFormat = "HH:mm"
        return f.string(from: date)
    }
}
