import Foundation

/// Read-only franchise dataset for Jarvis (never written back to Firebase). Switzerland-scoped.
struct JarvisFleetDataContext {
    let franchiseId: String
    let generatedAt: Date
    private let damages: [HasarKaydi]
    private let office: [OfficeOperation]
    private let exits: [ExitIslemi]
    private let returns: [IadeIslemi]
    private let traffic: [TrafficAccidentContract]
    private let vehicleCount: Int
    private let auditLogs: [AuditLog]
    let healthReport: JarvisSystemHealthReport

    var tables: [String: JarvisDataTable] {
        [
            "damage_6m_monthly": buildDamageTable(period: .monthly, monthsBack: 6),
            "office_6m": buildOfficeTable(period: .monthly),
            "system_health": healthReport.table
        ]
    }

    static func build(
        viewModel: AracViewModel,
        auditLogs: [AuditLog] = []
    ) -> JarvisFleetDataContext {
        let fid = FirebaseService.shared.currentFranchiseId
        return JarvisFleetDataContext(
            franchiseId: fid,
            generatedAt: Date(),
            damages: scopedCH(viewModel.allHasarKayitlariForReporting),
            office: scopedCH(viewModel.officeOperations),
            exits: scopedCH(viewModel.exitIslemleri),
            returns: scopedCH(viewModel.iadeIslemleri),
            traffic: scopedCH(viewModel.trafficAccidentContracts),
            vehicleCount: viewModel.araclar.count,
            auditLogs: auditLogs,
            healthReport: JarvisSystemHealthScanner.scan(viewModel: viewModel)
        )
    }

    private static func scopedCH<T>(_ items: [T]) -> [T] {
        items.filter { item in
            let fid: String
            if let d = item as? HasarKaydi { fid = d.franchiseId }
            else if let e = item as? ExitIslemi { fid = e.franchiseId }
            else if let r = item as? IadeIslemi { fid = r.franchiseId }
            else if let o = item as? OfficeOperation { fid = o.franchiseId }
            else if let t = item as? TrafficAccidentContract { fid = t.franchiseId }
            else { return true }
            return FranchiseCapabilityMatrix.isSwitzerland(franchiseId: fid)
        }
    }

    func compactJSON(for request: JarvisAnalysisRequest) -> String {
        if request.domain == .systemHealth {
            return healthReport.summaryJSON
        }
        let range = request.period.dateRange(endingAt: generatedAt)
        let payload = domainPayload(period: request.period, domain: request.domain, range: range)
        let wrap: [String: Any] = [
            "read_only": true,
            "franchise_id": franchiseId,
            "period": request.period.rawValue,
            "domain": request.domain.rawValue,
            "range_start": ISO8601DateFormatter().string(from: range.start),
            "range_end": ISO8601DateFormatter().string(from: range.end),
            "metrics": payload
        ]
        return jsonString(wrap)
    }

    func overviewJSON() -> String {
        let range = JarvisPeriod.monthly.dateRange(endingAt: generatedAt)
        let wrap: [String: Any] = [
            "read_only": true,
            "franchise_id": franchiseId,
            "vehicles": vehicleCount,
            "health_issue_count": healthReport.findings.filter { $0.severity != "info" }.count,
            "monthly_overview": domainPayload(period: .monthly, domain: .overview, range: range)
        ]
        return jsonString(wrap)
    }

    func tables(for request: JarvisAnalysisRequest) -> [JarvisDataTable] {
        if request.domain == .systemHealth { return [healthReport.table] }
        let range = request.period.dateRange(endingAt: generatedAt)
        switch request.domain {
        case .damages:
            return [buildDamageTable(period: request.period, range: range)]
        case .officeOperations, .banking, .additionalSales, .posClosing, .fuel, .washing:
            return [buildOfficeTable(period: request.period, range: range, domain: request.domain)]
        case .checkouts:
            return [buildCheckoutTable(range: range)]
        case .returns:
            return [buildReturnTable(range: range)]
        case .trafficContracts:
            return [buildTrafficTable(range: range)]
        case .overview:
            return [
                buildDamageTable(period: request.period, range: range),
                buildOfficeTable(period: request.period, range: range, domain: .officeOperations)
            ]
        default:
            return []
        }
    }

    func todayBriefJSON() -> String {
        let range = JarvisPeriod.daily.dateRange(endingAt: generatedAt)
        let wrap: [String: Any] = [
            "read_only": true,
            "franchise_id": franchiseId,
            "period": "today",
            "generated_at": ISO8601DateFormatter().string(from: generatedAt),
            "vehicles": vehicleCount,
            "damages_today": damageMetrics(in: range),
            "checkouts_today": checkoutMetrics(in: range),
            "returns_today": returnMetrics(in: range),
            "office_ops_today": officeMetrics(in: range, types: nil),
            "shuttle_today": ["see_reports_module": true],
            "traffic_today": trafficMetrics(in: range),
            "system_health_issues": healthReport.findings.filter { $0.severity != "info" }.count
        ]
        return jsonString(wrap)
    }

    // MARK: - Domain payloads

    private func domainPayload(period: JarvisPeriod, domain: JarvisDomain, range: (start: Date, end: Date)) -> [String: Any] {
        switch domain {
        case .overview:
            return overviewMetrics(range: range)
        case .damages:
            return damageMetrics(in: range)
        case .checkouts:
            return checkoutMetrics(in: range)
        case .returns:
            return returnMetrics(in: range)
        case .officeOperations:
            return officeMetrics(in: range, types: nil)
        case .banking:
            return officeMetrics(in: range, types: [.banking])
        case .additionalSales:
            return officeMetrics(in: range, types: [.additionalSales])
        case .posClosing:
            return officeMetrics(in: range, types: [.posClosing])
        case .fuel:
            return officeMetrics(in: range, types: [.fuelReceipt])
        case .washing:
            return officeMetrics(in: range, types: [.washing])
        case .trafficContracts:
            return trafficMetrics(in: range)
        case .systemHealth:
            return ["findings": healthReport.findings.count]
        }
    }

    private func overviewMetrics(range: (start: Date, end: Date)) -> [String: Any] {
        [
            "damages": damageMetrics(in: range),
            "checkouts": checkoutMetrics(in: range),
            "returns": returnMetrics(in: range),
            "office": officeMetrics(in: range, types: nil),
            "traffic": trafficMetrics(in: range)
        ]
    }

    private func damageMetrics(in range: (start: Date, end: Date)) -> [String: Any] {
        let slice = damages.filter { $0.tarih >= range.start && $0.tarih <= range.end }
        let photoCount = slice.reduce(0) { $0 + $1.fotograflar.count }
        let avg = slice.isEmpty ? 0.0 : Double(photoCount) / Double(slice.count)
        return [
            "count": slice.count,
            "in_progress": slice.filter { $0.durum == .inProgress }.count,
            "avg_photos_per_report": round(avg * 100) / 100,
            "total_photos": photoCount
        ]
    }

    private func checkoutMetrics(in range: (start: Date, end: Date)) -> [String: Any] {
        let slice = exits.filter {
            ReportTransactionDates.exitIsReportable($0) &&
            ReportTransactionDates.exitDate($0) >= range.start &&
            ReportTransactionDates.exitDate($0) <= range.end
        }
        return [
            "count": slice.count,
            "completed": slice.filter { $0.status == .completed }.count,
            "in_progress": slice.filter { $0.status == .inProgress }.count,
            "parked": slice.filter { $0.status == .parked }.count
        ]
    }

    private func returnMetrics(in range: (start: Date, end: Date)) -> [String: Any] {
        let slice = returns.filter {
            ReportTransactionDates.returnIsReportable($0) &&
            ReportTransactionDates.returnDate($0) >= range.start &&
            ReportTransactionDates.returnDate($0) <= range.end
        }
        return [
            "count": slice.count,
            "completed": slice.filter { $0.status == .completed }.count,
            "with_linked_checkout": slice.filter { $0.linkedExitId != nil }.count
        ]
    }

    private func officeMetrics(in range: (start: Date, end: Date), types: [OfficeOperationType]?) -> [String: Any] {
        var slice = office.filter { $0.date >= range.start && $0.date <= range.end }
        if let types { slice = slice.filter { types.contains($0.type) } }
        let total = slice.reduce(0.0) { $0 + $1.amount }
        var byType: [String: Int] = [:]
        for o in slice { byType[o.type.rawValue, default: 0] += 1 }
        return [
            "count": slice.count,
            "total_chf": round(total * 100) / 100,
            "by_type": byType
        ]
    }

    private func trafficMetrics(in range: (start: Date, end: Date)) -> [String: Any] {
        let slice = traffic.filter { $0.createdAt >= range.start && $0.createdAt <= range.end }
        let paid = slice.reduce(0.0) { $0 + ($1.paidAmount ?? 0) }
        let amount = slice.reduce(0.0) { $0 + $1.amount }
        return [
            "count": slice.count,
            "amount_chf": round(amount * 100) / 100,
            "paid_chf": round(paid * 100) / 100,
            "unpaid_count": slice.filter { ($0.paidAmount ?? 0) < $0.amount - 0.01 }.count
        ]
    }

    // MARK: - Tables

    private func buildDamageTable(period: JarvisPeriod, monthsBack: Int = 1, range: (start: Date, end: Date)? = nil) -> JarvisDataTable {
        if let range {
            let slice = damages.filter { $0.tarih >= range.start && $0.tarih <= range.end }
            return JarvisDataTable(
                id: "damage_\(period.rawValue)",
                title: "Damage — \(period.rawValue)",
                headers: ["Status", "Count"],
                rows: [
                    ["Total", "\(slice.count)"],
                    ["In progress", "\(slice.filter { $0.durum == .inProgress }.count)"],
                    ["Done", "\(slice.filter { $0.durum == .done }.count)"]
                ]
            )
        }
        let calendar = Calendar.current
        var rows: [[String]] = []
        for offset in (0..<monthsBack).reversed() {
            guard let start = calendar.date(byAdding: .month, value: -offset, to: calendar.startOfDay(for: generatedAt)),
                  let end = calendar.date(byAdding: .month, value: 1, to: start) else { continue }
            let slice = damages.filter { $0.tarih >= start && $0.tarih < end }
            let fmt = DateFormatter()
            fmt.dateFormat = "yyyy-MM"
            rows.append([fmt.string(from: start), "\(slice.count)", "\(slice.reduce(0) { $0 + $1.fotograflar.count })", "\(slice.filter { $0.durum == .inProgress }.count)"])
        }
        return JarvisDataTable(
            id: "damage_6m_monthly",
            title: "Damage reports",
            headers: ["Month", "Reports", "Photos", "In progress"],
            rows: rows
        )
    }

    private func buildOfficeTable(period: JarvisPeriod, range: (start: Date, end: Date)? = nil, domain: JarvisDomain = .officeOperations) -> JarvisDataTable {
        let r = range ?? period.dateRange(endingAt: generatedAt)
        var slice = office.filter { $0.date >= r.start && $0.date <= r.end }
        switch domain {
        case .banking: slice = slice.filter { $0.type == .banking }
        case .additionalSales: slice = slice.filter { $0.type == .additionalSales }
        case .posClosing: slice = slice.filter { $0.type == .posClosing }
        case .fuel: slice = slice.filter { $0.type == .fuelReceipt }
        case .washing: slice = slice.filter { $0.type == .washing }
        default: break
        }
        var totals: [String: (Int, Double)] = [:]
        for o in slice {
            var e = totals[o.type.rawValue] ?? (0, 0)
            e.0 += 1
            e.1 += o.amount
            totals[o.type.rawValue] = e
        }
        let rows = totals.sorted { $0.value.1 > $1.value.1 }.map {
            [$0.key, AppMetrics.formatInteger($0.value.0), AppCurrency.format($0.value.1)]
        }
        return JarvisDataTable(
            id: "office_\(domain.rawValue)",
            title: "Office — \(domain.rawValue)",
            headers: ["Type", "Count", AppCurrency.code],
            rows: rows
        )
    }

    private func buildCheckoutTable(range: (start: Date, end: Date)) -> JarvisDataTable {
        let slice = exits.filter {
            ReportTransactionDates.exitIsReportable($0) &&
            ReportTransactionDates.exitDate($0) >= range.start &&
            ReportTransactionDates.exitDate($0) <= range.end
        }
        return JarvisDataTable(
            id: "checkouts",
            title: "Checkouts",
            headers: ["Metric", "Value"],
            rows: [
                ["Total", "\(slice.count)"],
                ["Completed", "\(slice.filter { $0.status == .completed }.count)"],
                ["In progress", "\(slice.filter { $0.status == .inProgress }.count)"],
                ["Parked", "\(slice.filter { $0.status == .parked }.count)"]
            ]
        )
    }

    private func buildReturnTable(range: (start: Date, end: Date)) -> JarvisDataTable {
        let slice = returns.filter {
            ReportTransactionDates.returnIsReportable($0) &&
            ReportTransactionDates.returnDate($0) >= range.start &&
            ReportTransactionDates.returnDate($0) <= range.end
        }
        return JarvisDataTable(
            id: "returns",
            title: "Returns",
            headers: ["Metric", "Value"],
            rows: [
                ["Total", "\(slice.count)"],
                ["Completed", "\(slice.filter { $0.status == .completed }.count)"],
                ["Linked checkout", "\(slice.filter { $0.linkedExitId != nil }.count)"]
            ]
        )
    }

    private func buildTrafficTable(range: (start: Date, end: Date)) -> JarvisDataTable {
        let slice = traffic.filter { $0.createdAt >= range.start && $0.createdAt <= range.end }
        let unpaid = slice.filter { ($0.paidAmount ?? 0) < $0.amount - 0.01 }.count
        return JarvisDataTable(
            id: "traffic",
            title: "Traffic contracts",
            headers: ["Metric", "Value"],
            rows: [
                ["Contracts", "\(slice.count)"],
                ["Unpaid", "\(unpaid)"],
                ["Total \(AppCurrency.code)", AppCurrency.format(slice.reduce(0) { $0 + $1.amount })]
            ]
        )
    }

    private func jsonString(_ object: [String: Any]) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: object) else { return "{}" }
        return String(data: data, encoding: .utf8) ?? "{}"
    }
}
