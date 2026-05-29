import Foundation

/// Business dates for monthly reports — aligned with ExitReportsView / ReturnReportsView filters.
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
