import Foundation

/// WheelSys operational date/time formatting and validation (Europe/Zurich).
enum WheelSysZurichDateTime {
    static let timeZone = TimeZone(identifier: "Europe/Zurich")!
    private static let locale = Locale(identifier: "en_GB")

    static func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = timeZone
        formatter.dateFormat = "dd/MM/yyyy"
        return formatter.string(from: date)
    }

    static func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = timeZone
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }

    static func now() -> Date { Date() }

    /// Parse WheelSys dd/MM/yyyy + HH:mm into a comparable instant (Zurich wall clock).
    static func parse(dateText: String?, timeText: String?) -> Date? {
        let dateRaw = dateText?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let timeRaw = timeText?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !dateRaw.isEmpty else { return nil }

        let dateFormatter = DateFormatter()
        dateFormatter.locale = locale
        dateFormatter.timeZone = timeZone
        for pattern in ["dd/MM/yyyy", "d/M/yyyy", "dd.MM.yyyy"] {
            dateFormatter.dateFormat = pattern
            if let base = dateFormatter.date(from: dateRaw) {
                guard !timeRaw.isEmpty else { return base }
                let timeFormatter = DateFormatter()
                timeFormatter.locale = locale
                timeFormatter.timeZone = timeZone
                timeFormatter.dateFormat = "HH:mm"
                if let timeOnly = timeFormatter.date(from: timeRaw) {
                    var cal = Calendar(identifier: .gregorian)
                    cal.timeZone = timeZone
                    let hm = cal.dateComponents([.hour, .minute], from: timeOnly)
                    return cal.date(bySettingHour: hm.hour ?? 0, minute: hm.minute ?? 0, second: 0, of: base)
                }
                return base
            }
        }
        return nil
    }

    enum ReturnDateValidationError: LocalizedError {
        case beforeCheckout(checkout: Date, actual: Date)

        var errorDescription: String? {
            switch self {
            case .beforeCheckout(let checkout, let actual):
                let df = DateFormatter()
                df.locale = locale
                df.timeZone = timeZone
                df.dateFormat = "dd/MM/yyyy HH:mm"
                return String(
                    format: "wheelsys.error.return_before_checkout_detail".localized,
                    df.string(from: checkout),
                    df.string(from: actual)
                )
            }
        }
    }

    /// Only rule: actual return must be >= checkout. Early return before planned end is valid.
    static func validateReturnNotBeforeCheckout(
        checkoutDate: String?,
        checkoutTime: String?,
        plannedDate: String?,
        plannedTime: String?,
        actual: Date
    ) throws {
        let checkout = parse(dateText: checkoutDate, timeText: checkoutTime)
        let planned = parse(dateText: plannedDate, timeText: plannedTime)
        WheelSysDebug.log(
            "ReturnCheckin",
            "checkoutDateTime=\(checkout.map { "\(formatDate($0)) \(formatTime($0))" } ?? "nil") " +
            "plannedReturnDateTime=\(planned.map { "\(formatDate($0)) \(formatTime($0))" } ?? "nil") " +
            "actualReturnDateTime=\(formatDate(actual)) \(formatTime(actual)) " +
            "validation actual>=checkout = \(checkout.map { actual >= $0 } ?? true)"
        )
        if let checkout, actual < checkout {
            throw ReturnDateValidationError.beforeCheckout(checkout: checkout, actual: actual)
        }
    }

    /// Round up to the next 15-minute boundary (Europe/Zurich wall clock).
    static func roundUpToNext15Minutes(_ date: Date) -> Date {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timeZone
        let minute = cal.component(.minute, from: date)
        let second = cal.component(.second, from: date)
        let remainder = minute % 15
        var addMinutes = remainder == 0 && second == 0 ? 0 : (15 - remainder)
        if remainder == 0 && second > 0 { addMinutes = 15 }
        var result = cal.date(byAdding: .minute, value: addMinutes, to: date) ?? date
        result = cal.date(bySetting: .second, value: 0, of: result) ?? result
        return result
    }

    /// NTR close must be strictly after checkout; round up then enforce +5 min minimum gap.
    static func validNTRCloseDate(checkout: Date, proposedClose: Date) -> Date {
        let rounded = roundUpToNext15Minutes(proposedClose)
        if rounded <= checkout {
            var cal = Calendar(identifier: .gregorian)
            cal.timeZone = timeZone
            return cal.date(byAdding: .minute, value: 5, to: checkout) ?? rounded
        }
        return rounded
    }

    /// WheelSys NTR km display — de-CH thousands with dot (e.g. 149.212); hidden field stays raw int.
    static func formatKmText(_ km: Int) -> String {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "de_CH")
        formatter.numberStyle = .decimal
        formatter.groupingSeparator = "."
        formatter.maximumFractionDigits = 0
        return formatter.string(from: NSNumber(value: max(0, km))) ?? String(max(0, km))
    }

    static func parseKmText(_ text: String) -> Int {
        Int(text.filter { $0.isNumber }) ?? 0
    }

    static func formatFuelText(_ eighths: Int, capacity: Int = 8) -> String {
        let v = min(capacity, max(0, eighths))
        return "\(v) /\(capacity)"
    }

    static func formatFuelUsedText(_ used: Int) -> String {
        let formatter = NumberFormatter()
        formatter.locale = locale
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = used == 0 ? 0 : 1
        formatter.maximumFractionDigits = 1
        formatter.decimalSeparator = ","
        return formatter.string(from: NSNumber(value: max(0, used))) ?? String(max(0, used))
    }
}
