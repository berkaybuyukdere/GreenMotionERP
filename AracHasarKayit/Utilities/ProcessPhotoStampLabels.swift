import Foundation
import SwiftUI

/// First process photo = handover (handover date); later photos = return (return date).
enum ProcessPhotoStampLabels {
    struct Stamp {
        let labelKey: String
        let date: Date
        var localizedLabel: String { labelKey.localized }
    }

    static func stamp(globalIndex: Int, handoverDate: Date, returnDate: Date) -> Stamp {
        if globalIndex == 0 {
            return Stamp(labelKey: "HANDOVER", date: handoverDate)
        }
        return Stamp(labelKey: "RETURN", date: returnDate)
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
