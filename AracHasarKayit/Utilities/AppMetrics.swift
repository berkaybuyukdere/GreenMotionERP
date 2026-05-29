import Foundation

/// Locale-aware numeric formatting aligned with active franchise currency region.
enum AppMetrics {
    static var locale: Locale { AppCurrency.formattingLocale }

    static func formatDecimal(_ value: Double, fractionDigits: Int = 2) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.locale = locale
        f.minimumFractionDigits = fractionDigits
        f.maximumFractionDigits = fractionDigits
        return f.string(from: NSNumber(value: value)) ?? String(value)
    }

    static func formatInteger(_ value: Int) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.locale = locale
        f.maximumFractionDigits = 0
        return f.string(from: NSNumber(value: value)) ?? "\(value)"
    }

    static func formatPercent(_ ratio: Double, fractionDigits: Int = 1) -> String {
        let f = NumberFormatter()
        f.numberStyle = .percent
        f.locale = locale
        f.minimumFractionDigits = fractionDigits
        f.maximumFractionDigits = fractionDigits
        return f.string(from: NSNumber(value: ratio)) ?? "\(ratio)"
    }
}
