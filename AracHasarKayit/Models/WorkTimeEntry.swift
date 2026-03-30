import Foundation
import FirebaseFirestore

struct WorkTimeEntry: Identifiable, Equatable {
    var id: String
    var userId: String
    var franchiseId: String
    var dayKey: String
    var clockIn: Date
    var clockOut: Date
    var totalMinutes: Int
    var userDisplayName: String
    var userEmail: String
    var notes: String
    var updatedAt: Date

    static func documentId(userId: String, dayKey: String) -> String {
        "\(userId)_\(dayKey)"
    }

    static func dayKey(for date: Date, calendar: Calendar = .current) -> String {
        let d = calendar.startOfDay(for: date)
        let y = calendar.component(.year, from: d)
        let m = calendar.component(.month, from: d)
        let day = calendar.component(.day, from: d)
        return String(format: "%04d-%02d-%02d", y, m, day)
    }

    static func monthDayKeyRange(for month: Date, calendar: Calendar = .current) -> (start: String, end: String) {
        let c = calendar.dateComponents([.year, .month], from: month)
        let start = calendar.date(from: c) ?? month
        let end = calendar.date(byAdding: DateComponents(month: 1, day: -1), to: start) ?? start
        return (dayKey(for: start, calendar: calendar), dayKey(for: end, calendar: calendar))
    }

    static func combine(day: Date, timeSource: Date, calendar: Calendar = .current) -> Date {
        let base = calendar.startOfDay(for: day)
        let h = calendar.component(.hour, from: timeSource)
        let min = calendar.component(.minute, from: timeSource)
        return calendar.date(bySettingHour: h, minute: min, second: 0, of: base) ?? base
    }

    /// Handles end time on next calendar day when clock-out is before clock-in on the same day.
    static func totalMinutes(day: Date, clockIn: Date, clockOut: Date, calendar: Calendar = .current) -> Int {
        let start = combine(day: day, timeSource: clockIn, calendar: calendar)
        var end = combine(day: day, timeSource: clockOut, calendar: calendar)
        if end <= start {
            end = calendar.date(byAdding: .day, value: 1, to: end) ?? end
        }
        return max(0, Int(end.timeIntervalSince(start) / 60))
    }

    static func formattedDuration(minutes: Int) -> String {
        let h = minutes / 60
        let m = minutes % 60
        if h == 0 { return String(format: "%dm", m) }
        if m == 0 { return String(format: "%dh", h) }
        return String(format: "%dh %dm", h, m)
    }

    static func fromDocument(_ doc: DocumentSnapshot) -> WorkTimeEntry? {
        guard let data = doc.data(),
              let userId = data["userId"] as? String,
              let franchiseId = data["franchiseId"] as? String,
              let dayKey = data["dayKey"] as? String,
              let clockIn = (data["clockIn"] as? Timestamp)?.dateValue(),
              let clockOut = (data["clockOut"] as? Timestamp)?.dateValue(),
              let updatedAt = (data["updatedAt"] as? Timestamp)?.dateValue() else {
            return nil
        }
        let dayStart = Calendar.current.startOfDay(for: clockIn)
        let total = data["totalMinutes"] as? Int ?? WorkTimeEntry.totalMinutes(day: dayStart, clockIn: clockIn, clockOut: clockOut)
        let name = data["userDisplayName"] as? String ?? ""
        let email = data["userEmail"] as? String ?? ""
        let notes = data["notes"] as? String ?? ""
        return WorkTimeEntry(
            id: doc.documentID,
            userId: userId,
            franchiseId: franchiseId,
            dayKey: dayKey,
            clockIn: clockIn,
            clockOut: clockOut,
            totalMinutes: total,
            userDisplayName: name,
            userEmail: email,
            notes: notes,
            updatedAt: updatedAt
        )
    }
}

struct TeamWorkAggregate: Identifiable, Equatable {
    var id: String { userId }
    var userId: String
    var displayName: String
    var email: String
    var totalMinutes: Int
}
