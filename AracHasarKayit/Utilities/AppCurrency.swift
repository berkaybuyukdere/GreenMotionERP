import Foundation

enum AppCurrency {
    private static let franchiseCurrencyKey = "franchiseCurrencyCodeOverride"
    private static let activeFranchiseIdKey = "activeFranchiseIdForCurrencyFallback"
    private static let enforcedCountryCurrency: [String: String] = [
        "DE": "EUR",
        "TR": "TRY",
        "CH": "CHF"
    ]
    
    /// Effective ISO 4217 code: franchise document override when set, otherwise login country default.
    static var code: String {
        if let o = UserDefaults.standard.string(forKey: franchiseCurrencyKey)?.trimmingCharacters(in: .whitespacesAndNewlines),
           !o.isEmpty {
            return o.uppercased()
        }
        if let mapped = enforcedCountryCurrency[resolvedCountryCodeForFallback()] {
            return mapped
        }
        return UserDefaults.standard.selectedCountry.currency.uppercased()
    }
    
    static func setFranchiseCurrencyCode(_ code: String?) {
        let t = code?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if t.isEmpty {
            UserDefaults.standard.removeObject(forKey: franchiseCurrencyKey)
            return
        }
        UserDefaults.standard.set(t.uppercased(), forKey: franchiseCurrencyKey)
    }
    
    static func clearFranchiseCurrencyOverride() {
        UserDefaults.standard.removeObject(forKey: franchiseCurrencyKey)
    }

    /// Stores currently active franchise id (e.g. `CH`, `DE_DUSSELDORF`) for country-level fallback resolution.
    static func setActiveFranchiseId(_ franchiseId: String?) {
        let normalized = (franchiseId ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
        if normalized.isEmpty {
            UserDefaults.standard.removeObject(forKey: activeFranchiseIdKey)
            return
        }
        UserDefaults.standard.set(normalized, forKey: activeFranchiseIdKey)
    }

    static func clearActiveFranchiseId() {
        UserDefaults.standard.removeObject(forKey: activeFranchiseIdKey)
    }

    private static func resolvedCountryCodeForFallback() -> String {
        let activeFranchise = UserDefaults.standard.string(forKey: activeFranchiseIdKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased() ?? ""
        if !activeFranchise.isEmpty {
            let prefix = activeFranchise
                .split(separator: "_")
                .first
                .map(String.init)?
                .uppercased() ?? ""
            if prefix.count >= 2 {
                return prefix
            }
        }
        return UserDefaults.standard.selectedCountry.countryCode.uppercased()
    }
    
    /// Locale used for currency and decimal display (e.g. `de_CH` for Switzerland).
    static var formattingLocale: Locale {
        switch code {
        case "CHF": return Locale(identifier: "de_CH")
        case "EUR": return Locale(identifier: "de_DE")
        case "TRY": return Locale(identifier: "tr_TR")
        default: return Locale.current
        }
    }

    /// Switzerland: CHF with `de_CH` grouping (`1'234.56`). Other franchises use matching locales.
    static func format(_ amount: Double, fractionDigits: Int = 2) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = code
        formatter.locale = formattingLocale
        formatter.minimumFractionDigits = fractionDigits
        formatter.maximumFractionDigits = fractionDigits
        return formatter.string(from: NSNumber(value: amount)) ?? fallbackAmount(amount, fractionDigits: fractionDigits)
    }

    static func amountWithCode(_ amount: Double, fractionDigits: Int = 2) -> String {
        let formatted = AppMetrics.formatDecimal(amount, fractionDigits: fractionDigits)
        return "\(formatted) \(code)"
    }

    private static func fallbackAmount(_ amount: Double, fractionDigits: Int) -> String {
        "\(AppMetrics.formatDecimal(amount, fractionDigits: fractionDigits)) \(code)"
    }
}
