import Foundation

enum CHPanelPeriod: String, CaseIterable, Identifiable {
    case daily
    case weekly
    case monthly

    var id: String { rawValue }

    var titleKey: String {
        switch self {
        case .daily: return "ch_panel.period_daily"
        case .weekly: return "ch_panel.period_weekly"
        case .monthly: return "ch_panel.period_monthly"
        }
    }
}

struct CHPanelTimeBucket: Identifiable {
    let id: String
    let label: String
    let start: Date
    let damageCount: Int
    let damagePhotos: Int
    let officeRevenue: Double
    let officeTransactionCount: Int
}

struct CHPanelOfficeBreakdownRow: Identifiable {
    let id: String
    let type: String
    let count: Int
    let totalAmount: Double
}

struct CHPanelAuditRow: Identifiable {
    let id: String
    let timestamp: Date
    let userName: String
    let action: String
    let tableName: String
    let recordId: String
}

struct CHPanelAnalyticsSnapshot {
    let period: CHPanelPeriod
    let buckets: [CHPanelTimeBucket]
    let officeBreakdown: [CHPanelOfficeBreakdownRow]
    let totalRevenue: Double
    let totalDamages: Int
    let totalAuditEntries: Int
    let summaryForAI: String
}

enum CHPanelAnalyticsEngine {

    static func buildSnapshot(
        period: CHPanelPeriod,
        damages: [HasarKaydi],
        officeOperations: [OfficeOperation],
        trafficContracts: [TrafficAccidentContract],
        auditLogs: [AuditLog],
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> CHPanelAnalyticsSnapshot {
        let rangeStart: Date
        let bucketCount: Int

        switch period {
        case .daily:
            rangeStart = calendar.date(byAdding: .day, value: -6, to: calendar.startOfDay(for: now)) ?? now
            bucketCount = 7
        case .weekly:
            let weekStart = calendar.dateInterval(of: .weekOfYear, for: now)?.start ?? calendar.startOfDay(for: now)
            rangeStart = calendar.date(byAdding: .weekOfYear, value: -3, to: weekStart) ?? weekStart
            bucketCount = 4
        case .monthly:
            let comps = calendar.dateComponents([.year, .month], from: now)
            rangeStart = calendar.date(from: comps) ?? calendar.startOfDay(for: now)
            let dayOfMonth = calendar.component(.day, from: now)
            bucketCount = max(1, dayOfMonth)
        }

        var buckets: [CHPanelTimeBucket] = []
        for i in 0..<bucketCount {
            let (start, end, label) = bucketBounds(
                period: period,
                index: i,
                bucketCount: bucketCount,
                rangeStart: rangeStart,
                now: now,
                calendar: calendar
            )
            let periodDamages = damages.filter { $0.tarih >= start && $0.tarih < end }
            let periodOps = officeOperations.filter { $0.date >= start && $0.date < end }
            let periodTraffic = trafficContracts.filter { $0.createdAt >= start && $0.createdAt < end }
            let officeRev = periodOps.reduce(0) { $0 + $1.amount }
            let trafficRev = periodTraffic.reduce(0) { $0 + ($1.paidAmount ?? 0) }
            let revenue = officeRev + trafficRev
            let photos = periodDamages.reduce(0) { $0 + $1.fotograflar.count }
            buckets.append(CHPanelTimeBucket(
                id: label,
                label: label,
                start: start,
                damageCount: periodDamages.count,
                damagePhotos: photos,
                officeRevenue: revenue,
                officeTransactionCount: periodOps.count + periodTraffic.count
            ))
        }

        let filteredOps = officeOperations.filter { $0.date >= rangeStart }
        let filteredTraffic = trafficContracts.filter { $0.createdAt >= rangeStart }
        let byType = Dictionary(grouping: filteredOps, by: { $0.type.rawValue })
        var breakdown = byType.map { type, ops in
            CHPanelOfficeBreakdownRow(
                id: type,
                type: type,
                count: ops.count,
                totalAmount: ops.reduce(0) { $0 + $1.amount }
            )
        }
        let trafficTotal = filteredTraffic.reduce(0) { $0 + ($1.paidAmount ?? 0) }
        if !filteredTraffic.isEmpty {
            breakdown.append(CHPanelOfficeBreakdownRow(
                id: "traffic_accident",
                type: "traffic_accident",
                count: filteredTraffic.count,
                totalAmount: trafficTotal
            ))
        }
        breakdown.sort { $0.totalAmount > $1.totalAmount }

        return finishSnapshot(
            period: period,
            buckets: buckets,
            breakdown: breakdown,
            damages: damages,
            rangeStart: rangeStart,
            auditLogs: auditLogs
        )
    }

    private static func finishSnapshot(
        period: CHPanelPeriod,
        buckets: [CHPanelTimeBucket],
        breakdown: [CHPanelOfficeBreakdownRow],
        damages: [HasarKaydi],
        rangeStart: Date,
        auditLogs: [AuditLog]
    ) -> CHPanelAnalyticsSnapshot {
        let totalRevenue = buckets.reduce(0) { $0 + $1.officeRevenue }
        let totalDamages = damages.filter { $0.tarih >= rangeStart }.count
        let periodAudit = auditLogs.filter { $0.timestamp >= rangeStart }

        let summary = buildAISummary(
            period: period,
            buckets: buckets,
            breakdown: breakdown,
            totalRevenue: totalRevenue,
            totalDamages: totalDamages,
            auditCount: periodAudit.count
        )

        return CHPanelAnalyticsSnapshot(
            period: period,
            buckets: buckets,
            officeBreakdown: breakdown,
            totalRevenue: totalRevenue,
            totalDamages: totalDamages,
            totalAuditEntries: periodAudit.count,
            summaryForAI: summary
        )
    }

    static func auditRows(from logs: [AuditLog]) -> [CHPanelAuditRow] {
        logs.map { log in
            CHPanelAuditRow(
                id: log.id.uuidString,
                timestamp: log.timestamp,
                userName: log.userName ?? log.userId,
                action: log.action.rawValue,
                tableName: log.tableName,
                recordId: log.recordId
            )
        }
    }

    private static func bucketBounds(
        period: CHPanelPeriod,
        index: Int,
        bucketCount: Int,
        rangeStart: Date,
        now: Date,
        calendar: Calendar
    ) -> (start: Date, end: Date, label: String) {
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "en_GB")

        switch period {
        case .daily:
            let day = calendar.date(byAdding: .day, value: index, to: calendar.startOfDay(for: rangeStart)) ?? rangeStart
            let end = min(calendar.date(byAdding: .day, value: 1, to: day) ?? day, calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) ?? now)
            fmt.dateFormat = "EEE dd"
            return (day, end, fmt.string(from: day))
        case .weekly:
            let start = calendar.date(byAdding: .weekOfYear, value: index, to: rangeStart) ?? rangeStart
            let weekEnd = calendar.date(byAdding: .weekOfYear, value: 1, to: start) ?? start
            let end = min(weekEnd, calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) ?? now)
            fmt.dateFormat = "dd MMM"
            return (start, end, "W\(index + 1) · \(fmt.string(from: start))")
        case .monthly:
            let monthStart = rangeStart
            let day = calendar.date(byAdding: .day, value: index, to: monthStart) ?? monthStart
            let nextDay = calendar.date(byAdding: .day, value: 1, to: day) ?? day
            let end = min(nextDay, calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) ?? now)
            fmt.dateFormat = "d MMM"
            return (day, end, fmt.string(from: day))
        }
    }

    private static func buildAISummary(
        period: CHPanelPeriod,
        buckets: [CHPanelTimeBucket],
        breakdown: [CHPanelOfficeBreakdownRow],
        totalRevenue: Double,
        totalDamages: Int,
        auditCount: Int
    ) -> String {
        let periodLabel = period.rawValue
        let bucketLines = buckets.map {
            "\($0.label): damages=\($0.damageCount), revenue=\(AppCurrency.amountWithCode($0.officeRevenue)), ops=\($0.officeTransactionCount)"
        }.joined(separator: "\n")
        let typeLines = breakdown.prefix(8).map {
            "\($0.type): count=\($0.count), total=\(String(format: "%.2f", $0.totalAmount))"
        }.joined(separator: "\n")
        return """
        Franchise analytics snapshot (Switzerland fleet app).
        Period grouping: \(periodLabel).
        Total damages in range: \(totalDamages).
        Total revenue in range: \(AppCurrency.amountWithCode(totalRevenue)).
        Audit log entries in range: \(auditCount).
        Buckets:
        \(bucketLines)
        Revenue breakdown:
        \(typeLines)
        """
    }
}
