import Foundation

/// Stripe payment totals: admin tier and above only (not manager/staff).
enum FinancialAccess {
    static func canViewStripePaymentTotals(role: UserRole?) -> Bool {
        guard let role else { return false }
        return role == .admin || role == .superadmin || role == .globaladmin
    }
}

extension UserProfile {
    var canViewStripePaymentTotals: Bool {
        FinancialAccess.canViewStripePaymentTotals(role: role)
    }
}
