import Foundation

/// Helper for Swiss/Zurich public holidays
class SwissHolidaysHelper {
    static let shared = SwissHolidaysHelper()
    
    private init() {}
    
    /// Get all Swiss public holidays for a given year
    func getPublicHolidays(for year: Int) -> [Date] {
        var holidays: [Date] = []
        let calendar = Calendar.current
        
        // Fixed holidays
        holidays.append(contentsOf: [
            // New Year's Day
            date(year: year, month: 1, day: 1),
            // Labor Day
            date(year: year, month: 5, day: 1),
            // Swiss National Day
            date(year: year, month: 8, day: 1),
            // Christmas
            date(year: year, month: 12, day: 25),
            // Boxing Day / St. Stephen's Day
            date(year: year, month: 12, day: 26)
        ].compactMap { $0 })
        
        // Easter-based holidays
        if let easter = easterDate(for: year) {
            // Good Friday (2 days before Easter)
            if let goodFriday = calendar.date(byAdding: .day, value: -2, to: easter) {
                holidays.append(goodFriday)
            }
            // Easter Monday (1 day after Easter)
            if let easterMonday = calendar.date(byAdding: .day, value: 1, to: easter) {
                holidays.append(easterMonday)
            }
            // Ascension Day (39 days after Easter)
            if let ascension = calendar.date(byAdding: .day, value: 39, to: easter) {
                holidays.append(ascension)
            }
            // Whit Monday (50 days after Easter)
            if let whitMonday = calendar.date(byAdding: .day, value: 50, to: easter) {
                holidays.append(whitMonday)
            }
        }
        
        // Epiphany (January 6)
        holidays.append(date(year: year, month: 1, day: 6) ?? Date())
        
        // Christmas Eve (December 24)
        holidays.append(date(year: year, month: 12, day: 24) ?? Date())
        
        // New Year's Eve (December 31)
        holidays.append(date(year: year, month: 12, day: 31) ?? Date())
        
        return holidays.sorted()
    }
    
    /// Check if a date is a Swiss public holiday
    func isPublicHoliday(_ date: Date) -> Bool {
        let calendar = Calendar.current
        let year = calendar.component(.year, from: date)
        let holidays = getPublicHolidays(for: year)
        
        return holidays.contains { holiday in
            calendar.isDate(holiday, inSameDayAs: date)
        }
    }
    
    /// Check if a date is a weekend
    func isWeekend(_ date: Date) -> Bool {
        let calendar = Calendar.current
        let weekday = calendar.component(.weekday, from: date)
        return weekday == 1 || weekday == 7 // Sunday or Saturday
    }
    
    /// Get holiday name for a date (if it's a holiday)
    func getHolidayName(for date: Date) -> String? {
        let calendar = Calendar.current
        let year = calendar.component(.year, from: date)
        let month = calendar.component(.month, from: date)
        let day = calendar.component(.day, from: date)
        
        // Fixed holidays
        switch (month, day) {
        case (1, 1): return "New Year's Day"
        case (1, 6): return "Epiphany"
        case (5, 1): return "Labor Day"
        case (8, 1): return "Swiss National Day"
        case (12, 24): return "Christmas Eve"
        case (12, 25): return "Christmas"
        case (12, 26): return "Boxing Day"
        case (12, 31): return "New Year's Eve"
        default:
            break
        }
        
        // Easter-based holidays
        if let easter = easterDate(for: year) {
            let daysDiff = calendar.dateComponents([.day], from: easter, to: date).day ?? 0
            
            switch daysDiff {
            case -2: return "Good Friday"
            case 0: return "Easter Sunday"
            case 1: return "Easter Monday"
            case 39: return "Ascension Day"
            case 49: return "Whit Sunday"
            case 50: return "Whit Monday"
            default:
                break
            }
        }
        
        return nil
    }
    
    // MARK: - Private Helpers
    
    private func date(year: Int, month: Int, day: Int) -> Date? {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        return Calendar.current.date(from: components)
    }
    
    private func easterDate(for year: Int) -> Date? {
        // Algorithm to calculate Easter date (Gregorian calendar)
        let a = year % 19
        let b = year / 100
        let c = year % 100
        let d = b / 4
        let e = b % 4
        let f = (b + 8) / 25
        let g = (b - f + 1) / 3
        let h = (19 * a + b - d - g + 15) % 30
        let i = c / 4
        let k = c % 4
        let l = (32 + 2 * e + 2 * i - h - k) % 7
        let m = (a + 11 * h + 22 * l) / 451
        let month = (h + l - 7 * m + 114) / 31
        let day = ((h + l - 7 * m + 114) % 31) + 1
        
        return date(year: year, month: month, day: day)
    }
}

