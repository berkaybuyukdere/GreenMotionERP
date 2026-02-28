import Foundation

enum AppCurrency {
    static var code: String {
        UserDefaults.standard.selectedCountry.currency
    }
    
    static func format(_ amount: Double, fractionDigits: Int = 2) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = code
        formatter.minimumFractionDigits = fractionDigits
        formatter.maximumFractionDigits = fractionDigits
        return formatter.string(from: NSNumber(value: amount)) ?? "\(amount) \(code)"
    }
    
    static func amountWithCode(_ amount: Double, fractionDigits: Int = 2) -> String {
        let formatted = String(format: "%.\(fractionDigits)f", amount)
        return "\(formatted) \(code)"
    }
}
