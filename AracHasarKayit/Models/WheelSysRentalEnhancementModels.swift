import Foundation

struct WheelSysEntityNote: Identifiable, Hashable {
    let id: String
    let text: String
    let createdBy: String
    let createdAt: String
    let source: String
}

struct WheelSysInsuranceSummary: Hashable {
    let hasInsuranceCharge: Bool
    let insuranceChargeAmount: String
    let excessAmount: String
    let damageExcessAmount: String
    let insuranceTypes: [String]
}
