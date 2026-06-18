import Foundation

// MARK: - Row

struct WheelSysAvailabilityRow: Identifiable, Equatable {
    let vehicleClass: String
    let carGroup: String
    let hourlyValues: [Date: Int]

    var id: String { "\(vehicleClass)|\(carGroup)" }

    var displayTitle: String {
        if vehicleClass.isEmpty { return carGroup }
        if carGroup.isEmpty { return vehicleClass }
        return "\(vehicleClass) / \(carGroup)"
    }

    var hourKeyCount: Int { hourlyValues.count }

    var sortedHourEntries: [(Date, Int)] {
        hourlyValues.sorted { $0.key < $1.key }.map { ($0.key, $0.value) }
    }

    var firstHourValue: Int? { sortedHourEntries.first?.1 }

    var minValue: Int? {
        guard !hourlyValues.isEmpty else { return nil }
        return hourlyValues.values.min()
    }

    var maxValue: Int? {
        guard !hourlyValues.isEmpty else { return nil }
        return hourlyValues.values.max()
    }
}

// MARK: - Result

struct WheelSysAvailabilityResult: Equatable {
    let cacheKey: String
    let metric: String
    let station: String
    let dateFrom: Date
    let dateTo: Date
    let readyAttempt: Int?
    let rows: [WheelSysAvailabilityRow]
    let sortedHourDates: [Date]
    let classSections: [WheelSysAvailabilityClassSection]
    let calendarDays: [Date]

    var rowsCount: Int { rows.count }

    init(
        cacheKey: String,
        metric: String,
        station: String,
        dateFrom: Date,
        dateTo: Date,
        readyAttempt: Int?,
        rows: [WheelSysAvailabilityRow]
    ) {
        self.cacheKey = cacheKey
        self.metric = metric
        self.station = station
        self.dateFrom = dateFrom
        self.dateTo = dateTo
        self.readyAttempt = readyAttempt
        self.rows = rows
        self.sortedHourDates = Array(Set(rows.flatMap(\.hourlyValues.keys))).sorted()
        let grouped = Dictionary(grouping: rows, by: \.vehicleClass)
        self.classSections = grouped
            .map { WheelSysAvailabilityClassSection(vehicleClass: $0.key, groups: $0.value) }
            .sorted { $0.vehicleClass.localizedCaseInsensitiveCompare($1.vehicleClass) == .orderedAscending }
        self.calendarDays = WheelSysAvailabilityDateRange.uniqueDays(from: self.sortedHourDates)
    }

    /// Sum hourly values across all rows (includes negative values).
    var totalHourlyValues: [Date: Int] {
        var totals: [Date: Int] = [:]
        for row in rows {
            for (date, value) in row.hourlyValues {
                totals[date, default: 0] += value
            }
        }
        return totals
    }

    func hours(on day: Date) -> [Date] {
        WheelSysAvailabilityDateRange.hours(on: day, from: sortedHourDates)
    }
}

// MARK: - Class section

struct WheelSysAvailabilityClassSection: Identifiable, Equatable {
    let vehicleClass: String
    let groups: [WheelSysAvailabilityRow]

    var id: String { vehicleClass }

    var groupCount: Int { groups.count }

    /// Pre-sorted groups for stable UI order.
    var sortedGroups: [WheelSysAvailabilityRow] {
        groups.sorted { $0.carGroup.localizedCaseInsensitiveCompare($1.carGroup) == .orderedAscending }
    }

    var classTotals: [Date: Int] {
        var totals: [Date: Int] = [:]
        for group in groups {
            for (date, value) in group.hourlyValues {
                totals[date, default: 0] += value
            }
        }
        return totals
    }

    var sortedHourDates: [Date] {
        let keys = Set(groups.flatMap { $0.hourlyValues.keys })
        return keys.sorted()
    }
}

// MARK: - Date helpers

enum WheelSysAvailabilityDateRange {
    private static var zurich: TimeZone { TimeZone(identifier: "Europe/Zurich")! }

    /// Dynamic window: today (Zurich) so today's availability is always shown.
    static var defaultFrom: Date {
        zurichCalendar.startOfDay(for: Date())
    }

    /// Dynamic window: today + 30 days (Zurich).
    static var defaultTo: Date {
        zurichCalendar.date(byAdding: .day, value: 30, to: defaultFrom) ?? defaultFrom
    }

    /// WheelSys expects UTC Z suffix with calendar date (matches Chrome DevTools).
    static func isoStart(_ date: Date) -> String {
        let cal = Calendar(identifier: .gregorian)
        let y = cal.component(.year, from: date)
        let m = cal.component(.month, from: date)
        let d = cal.component(.day, from: date)
        return String(format: "%04d-%02d-%02dT00:00:00.000Z", y, m, d)
    }

    static func isoEnd(_ date: Date) -> String {
        let cal = Calendar(identifier: .gregorian)
        let y = cal.component(.year, from: date)
        let m = cal.component(.month, from: date)
        let d = cal.component(.day, from: date)
        return String(format: "%04d-%02d-%02dT23:59:59.000Z", y, m, d)
    }

    static var zurichCalendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = zurich
        return cal
    }

    static func uniqueDays(from hours: [Date]) -> [Date] {
        guard !hours.isEmpty else { return [] }
        let cal = zurichCalendar
        var seen = Set<Int>()
        var days: [Date] = []
        for hour in hours {
            let day = cal.startOfDay(for: hour)
            let token = Int(day.timeIntervalSince1970)
            if seen.insert(token).inserted {
                days.append(day)
            }
        }
        return days.sorted()
    }

    static func hours(on day: Date, from allHours: [Date]) -> [Date] {
        let cal = zurichCalendar
        let target = cal.startOfDay(for: day)
        return allHours.filter { cal.startOfDay(for: $0) == target }
    }
}

// MARK: - Hour key parsing

enum WheelSysAvailabilityHourKey {
    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyMMddHHmm"
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "Europe/Zurich")
        return f
    }()

    static func parse(_ key: String) -> Date? {
        guard key.count == 10, key.allSatisfy(\.isNumber) else { return nil }
        return formatter.date(from: key)
    }

    static func parseRow(_ dict: [String: Any]) -> WheelSysAvailabilityRow? {
        let vehicleClass = string(dict["VehicleClass"])
        let carGroup = string(dict["CarGroup"])
        guard !vehicleClass.isEmpty || !carGroup.isEmpty else { return nil }

        var hourly: [Date: Int] = [:]
        for (key, value) in dict {
            if key == "VehicleClass" || key == "CarGroup" { continue }
            guard let date = parse(key) else { continue }
            if let n = value as? NSNumber {
                hourly[date] = n.intValue
            } else if let i = value as? Int {
                hourly[date] = i
            }
        }

        return WheelSysAvailabilityRow(
            vehicleClass: vehicleClass,
            carGroup: carGroup,
            hourlyValues: hourly
        )
    }

    private static func string(_ value: Any?) -> String {
        if let s = value as? String { return s.trimmingCharacters(in: .whitespacesAndNewlines) }
        if let n = value as? NSNumber { return n.stringValue }
        return ""
    }
}
