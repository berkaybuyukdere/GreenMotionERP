import Foundation

/// Shared category filter for Fleet Operations surfaces (`FleetOperationsHubView`, `InkassoHubListView`,
/// `PaymentsHubListView` and their hub cards). Centralising the predicates here eliminates the
/// count drift that used to appear when a card and its list disagreed on what an "inkasso" row was.
enum FleetOperationsFilter: String, CaseIterable, Identifiable {
    case traffic
    case inkasso
    case banking
    case all

    var id: String { rawValue }

    /// Inclusive month range `[start, end]` for a given anchor month.
    static func monthRange(for month: Date, calendar: Calendar = .current) -> (start: Date, end: Date) {
        let monthComponents = calendar.dateComponents([.year, .month], from: month)
        let monthStart = calendar.date(from: monthComponents) ?? month
        let monthEnd = calendar.date(
            byAdding: DateComponents(month: 1, day: -1, hour: 23, minute: 59, second: 59),
            to: monthStart
        ) ?? month
        return (monthStart, monthEnd)
    }

    /// Office payment categories included by this filter. Empty for `.traffic` (no office row matches).
    var officePaymentCategories: Set<FleetPaymentCategory> {
        switch self {
        case .traffic: return []
        case .inkasso: return [.debtCollection, .officePayment]
        case .banking: return [.bankingTransaction]
        case .all: return [.debtCollection, .officePayment, .bankingTransaction]
        }
    }

    /// True when this filter accepts the given banking office operation.
    /// Traffic-only filters always return false (use `matchesTrafficContract` for those).
    func matchesOfficeOperation(_ op: OfficeOperation) -> Bool {
        guard op.type == .banking else { return false }
        let category = op.effectivePaymentCategory
        return officePaymentCategories.contains(category)
    }

    /// True when this filter accepts traffic accident contracts.
    func matchesTrafficContract(_ contract: TrafficAccidentContract) -> Bool {
        switch self {
        case .traffic, .all: return true
        case .inkasso, .banking: return false
        }
    }

    /// Filter + sort `operations` for this category in the supplied month (descending by date).
    func filteredOfficeOperations(_ operations: [OfficeOperation], in month: Date) -> [OfficeOperation] {
        let range = Self.monthRange(for: month)
        return operations
            .filter { op in
                matchesOfficeOperation(op)
                    && op.date >= range.start
                    && op.date <= range.end
            }
            .sorted { $0.date > $1.date }
    }

    /// Filter + sort traffic contracts for this category in the supplied month (descending by issue date).
    func filteredTrafficContracts(_ contracts: [TrafficAccidentContract], in month: Date) -> [TrafficAccidentContract] {
        guard self == .traffic || self == .all else { return [] }
        let range = Self.monthRange(for: month)
        return contracts
            .filter { c in c.contractIssueDate >= range.start && c.contractIssueDate <= range.end }
            .sorted { $0.contractIssueDate > $1.contractIssueDate }
    }
}
