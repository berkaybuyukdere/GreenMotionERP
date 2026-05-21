import SwiftUI

/// Shared month-bucket sparkline helpers for Switzerland fleet hub cards.
enum CHFleetHubCardSparkline {
    static func monthRange(for month: Date) -> (start: Date, end: Date) {
        let calendar = Calendar.current
        let monthComponents = calendar.dateComponents([.year, .month], from: month)
        let monthStart = calendar.date(from: monthComponents) ?? Date()
        let monthEnd = calendar.date(
            byAdding: DateComponents(month: 1, day: -1, hour: 23, minute: 59, second: 59),
            to: monthStart
        ) ?? Date()
        return (monthStart, monthEnd)
    }

    static func amountBuckets(month: Date, datedAmounts: [(date: Date, amount: Double)]) -> [Double] {
        let calendar = Calendar.current
        let comps = calendar.dateComponents([.year, .month], from: month)
        guard let monthStart = calendar.date(from: comps),
              let daysInMonth = calendar.range(of: .day, in: .month, for: month)?.count else { return [] }
        let buckets = 4
        let bucketSize = max(1, daysInMonth / buckets)
        return (0..<buckets).map { bucket in
            let bucketStart = calendar.date(byAdding: .day, value: bucket * bucketSize, to: monthStart)!
            let bucketEnd = calendar.date(byAdding: .day, value: min((bucket + 1) * bucketSize, daysInMonth), to: monthStart)!
            return datedAmounts
                .filter { $0.date >= bucketStart && $0.date < bucketEnd }
                .reduce(0) { $0 + $1.amount }
        }
    }

    static func trendColor(for data: [Double]) -> Color {
        guard data.count >= 2 else { return .secondary }
        let mid = data.count / 2
        let first = data.prefix(mid).reduce(0, +)
        let second = data.suffix(data.count - mid).reduce(0, +)
        return second >= first ? .green : .red
    }
}
