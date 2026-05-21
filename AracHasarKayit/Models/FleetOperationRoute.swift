import Foundation

/// Routes an Operations intake to Traffic accident, Inkasso, or Banking transaction storage.
enum FleetOperationRoute: String, Codable, CaseIterable, Identifiable {
    case trafficAccident = "trafficAccident"
    case inkasso = "inkasso"
    case bankingTransaction = "bankingTransaction"

    var id: String { rawValue }

    var localizationKey: String {
        switch self {
        case .trafficAccident: return "operation.route.traffic_accident"
        case .inkasso: return "operation.route.inkasso"
        case .bankingTransaction: return "operation.route.banking_transaction"
        }
    }

    var localizedTitle: String { localizationKey.localized }

    var hubIconName: String {
        switch self {
        case .trafficAccident: return "car.side.rear.and.collision.and.car.side.front"
        case .inkasso: return "doc.text.magnifyingglass"
        case .bankingTransaction: return "building.columns.fill"
        }
    }

    var accentColorName: String {
        switch self {
        case .trafficAccident: return "orange"
        case .inkasso: return "red"
        case .bankingTransaction: return "indigo"
        }
    }

    /// Maps to `OfficeOperation` payment category when stored under type `.banking`.
    var officePaymentCategory: FleetPaymentCategory? {
        switch self {
        case .trafficAccident: return nil
        case .inkasso: return .debtCollection
        case .bankingTransaction: return .bankingTransaction
        }
    }

    static func from(officePaymentCategory category: FleetPaymentCategory) -> FleetOperationRoute? {
        switch category {
        case .debtCollection, .officePayment: return .inkasso
        case .bankingTransaction: return .bankingTransaction
        }
    }
}

/// Unified Operations log row (derived from traffic contracts + banking office ops).
enum FleetOperationLogItem: Identifiable {
    case traffic(TrafficAccidentContract)
    case inkasso(OfficeOperation)
    case banking(OfficeOperation)

    var id: String {
        switch self {
        case .traffic(let c): return "tac-\(c.documentId ?? c.id.uuidString)"
        case .inkasso(let o): return "ink-\(o.documentId ?? o.id.uuidString)"
        case .banking(let o): return "bnk-\(o.documentId ?? o.id.uuidString)"
        }
    }

    var route: FleetOperationRoute {
        switch self {
        case .traffic: return .trafficAccident
        case .inkasso: return .inkasso
        case .banking: return .bankingTransaction
        }
    }

    var sortDate: Date {
        switch self {
        case .traffic(let c): return c.contractIssueDate
        case .inkasso(let o), .banking(let o): return o.date
        }
    }

    var amount: Double {
        switch self {
        case .traffic(let c): return c.amount
        case .inkasso(let o), .banking(let o): return o.amount
        }
    }

    var resDisplay: String {
        switch self {
        case .traffic(let c): return c.displayResCode
        case .inkasso(let o), .banking(let o):
            let r = TrafficAccidentContract.canonicalRES(from: o.referenceNumber ?? "")
            return r.isEmpty ? "—" : r
        }
    }

    var createdByName: String? {
        switch self {
        case .traffic(let c): return c.createdByName
        case .inkasso(let o), .banking(let o): return o.createdByName
        }
    }

    var photoCount: Int {
        switch self {
        case .traffic(let c): return c.photos.count
        case .inkasso(let o), .banking(let o): return o.photos.count
        }
    }
}
