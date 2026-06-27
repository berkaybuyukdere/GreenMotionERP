import Foundation

/// Office-operation financial gates — mirrors web `canViewOfficeOperationTotals`.
enum FinancialAccess {
    /// Aggregated KPI / summary totals (not per-row line amounts). Admin tier and above only.
    static func canViewOfficeOperationTotals(role: UserRole?) -> Bool {
        guard let role else { return false }
        return role == .admin || role == .superadmin || role == .globaladmin
    }

    /// Stripe payment hub totals — same tier as office operation totals.
    static func canViewStripePaymentTotals(role: UserRole?) -> Bool {
        canViewOfficeOperationTotals(role: role)
    }
}

extension UserProfile {
    var canViewOfficeOperationTotals: Bool {
        FinancialAccess.canViewOfficeOperationTotals(role: role)
    }

    var canViewStripePaymentTotals: Bool {
        FinancialAccess.canViewStripePaymentTotals(role: role)
    }
}
