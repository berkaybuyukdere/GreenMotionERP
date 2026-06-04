import Foundation

/// Business dates for monthly reports — aligned with ExitReportsView / ReturnReportsView filters.
enum ReportDateFilterPreset: String, CaseIterable {
    case all = "All"
    case daily = "Daily"
    case weekly = "Weekly"
    case monthly = "Monthly"
}

func reportMonthStart(_ date: Date) -> Date {
    let cal = Calendar.current
    return cal.date(from: cal.dateComponents([.year, .month], from: date)) ?? date
}

func makeReportFilterDateRange(preset: ReportDateFilterPreset, filterMonth: Date) -> (start: Date, end: Date) {
    let calendar = Calendar.current
    let now = Date()
    switch preset {
    case .all:
        return (.distantPast, .distantFuture)
    case .daily:
        let start = calendar.startOfDay(for: now)
        let end = calendar.date(byAdding: DateComponents(day: 1, second: -1), to: start) ?? now
        return (start, end)
    case .weekly:
        let start = calendar.date(byAdding: .day, value: -7, to: now) ?? now
        return (start, now)
    case .monthly:
        let monthComponents = calendar.dateComponents([.year, .month], from: filterMonth)
        guard let monthStart = calendar.date(from: monthComponents),
              let monthEnd = calendar.date(byAdding: DateComponents(month: 1, second: -1), to: monthStart) else {
            let start = calendar.date(byAdding: .month, value: -1, to: now) ?? now
            return (start, now)
        }
        return (monthStart, monthEnd)
    }
}

func reportDateMatchesFilter(
    _ value: Date,
    preset: ReportDateFilterPreset,
    filterMonth: Date
) -> Bool {
    let range = makeReportFilterDateRange(preset: preset, filterMonth: filterMonth)
    return value >= range.start && value <= range.end
}

enum ReportTransactionDates {
    static func exitDate(_ exit: ExitIslemi) -> Date {
        exit.exitTarihi
    }

    static func returnDate(_ iade: IadeIslemi) -> Date {
        iade.iadeTarihi
    }

    static func exitIsReportable(_ exit: ExitIslemi) -> Bool {
        !exit.isDeleted
    }

    /// Completed returns and in-progress user returns; excludes auto placeholder rows still open.
    static func returnIsReportable(_ iade: IadeIslemi) -> Bool {
        guard !iade.isDeleted else { return false }
        if iade.expectedReturnPlanned && iade.status != .completed { return false }
        return true
    }

    static func isInHalfOpenRange(_ date: Date, start: Date, end: Date) -> Bool {
        date >= start && date < end
    }
}
