import Foundation

/// Shared category for Payments hub (`OfficeOperation` type `.banking`) and traffic accident contract payment method.
enum FleetPaymentCategory: String, Codable, CaseIterable, Identifiable {
    case debtCollection = "debtCollection"
    case officePayment = "officePayment"
    case bankingTransaction = "bankingTransaction"

    var id: String { rawValue }

    var localizationKey: String {
        switch self {
        case .debtCollection: return "payment.category.debt_collection"
        case .officePayment: return "payment.category.office_payment"
        case .bankingTransaction: return "payment.category.banking_transaction"
        }
    }

    var localizedTitle: String { localizationKey.localized }
}

/// Lifecycle for a Payments hub row (`OfficeOperation` type `.banking`).
enum FleetPaymentRecordStatus: String, Codable, CaseIterable, Identifiable {
    case pending = "pending"
    case partial = "partial"
    case received = "received"
    case closed = "closed"

    var id: String { rawValue }

    var localizationKey: String {
        switch self {
        case .pending: return "payment.record.status.pending"
        case .partial: return "payment.record.status.partial"
        case .received: return "payment.record.status.received"
        case .closed: return "payment.record.status.closed"
        }
    }

    var localizedTitle: String { localizationKey.localized }

    var next: FleetPaymentRecordStatus {
        let arr = Array(Self.allCases)
        guard let i = arr.firstIndex(of: self) else { return .pending }
        return arr[(i + 1) % arr.count]
    }

    /// SF Symbol for compact status chips (Payments list).
    var statusIconName: String {
        switch self {
        case .pending: return "clock.fill"
        case .partial: return "circle.lefthalf.filled"
        case .received: return "checkmark.circle.fill"
        case .closed: return "archivebox.fill"
        }
    }
}
