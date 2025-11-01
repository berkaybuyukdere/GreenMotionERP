import Foundation
import FirebaseFirestore
import SwiftUI

// MARK: - Work Schedule Model

struct WorkSchedule: Identifiable, Codable {
    var id: String?
    var userId: String
    var userName: String
    var weekStartDate: Date // Haftanın başlangıç tarihi (Pazartesi)
    var schedules: [DailySchedule] // Haftalık program
    var weeklyHours: Double // Haftalık toplam çalışma saati
    var vacationDays: Int // Haftalık izin gün sayısı
    var createdAt: Date
    var updatedAt: Date
    
    init(userId: String, userName: String, weekStartDate: Date, schedules: [DailySchedule] = [], weeklyHours: Double = 0, vacationDays: Int = 0) {
        self.userId = userId
        self.userName = userName
        self.weekStartDate = weekStartDate
        self.schedules = schedules
        self.weeklyHours = weeklyHours
        self.vacationDays = vacationDays
        self.createdAt = Date()
        self.updatedAt = Date()
    }
    
    // Haftalık toplam saatleri hesapla
    var calculatedWeeklyHours: Double {
        schedules.reduce(0.0) { total, schedule in
            if schedule.isVacation {
                return total
            }
            return total + schedule.workingHours
        }
    }
    
    // İzin gün sayısını hesapla
    var calculatedVacationDays: Int {
        schedules.filter { $0.isVacation }.count
    }
}

// MARK: - Daily Schedule

struct DailySchedule: Identifiable, Codable, Equatable {
    var id: String { "\(dayOfWeek)-\(startTime)-\(endTime)" }
    var dayOfWeek: Int // 0=Pazartesi, 6=Pazar
    var startTime: String // "09:00" formatında
    var endTime: String // "17:00" formatında
    var isVacation: Bool
    var shiftType: ShiftType
    
    enum ShiftType: String, Codable, CaseIterable {
        case morning = "Morning"
        case afternoon = "Afternoon"
        case evening = "Evening"
        case fullDay = "Full Day"
        
        var icon: String {
            switch self {
            case .morning: return "sunrise.fill"
            case .afternoon: return "sun.max.fill"
            case .evening: return "moon.fill"
            case .fullDay: return "calendar.badge.clock"
            }
        }
    }
    
    var dayName: String {
        let days = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"]
        return days[dayOfWeek]
    }
    
    // Çalışma saatlerini hesapla
    var workingHours: Double {
        guard !isVacation else { return 0 }
        guard let start = timeToMinutes(startTime),
              let end = timeToMinutes(endTime) else {
            return 0
        }
        return Double(end - start) / 60.0
    }
    
    private func timeToMinutes(_ time: String) -> Int? {
        let components = time.split(separator: ":")
        guard components.count == 2,
              let hours = Int(components[0]),
              let minutes = Int(components[1]) else {
            return nil
        }
        return hours * 60 + minutes
    }
    
    var displayTime: String {
        if isVacation {
            return "Vacation"
        }
        return "\(startTime) - \(endTime)"
    }
}

// MARK: - User Color Assignment

struct UserColorAssignment {
    static let userColors: [Color] = [
        .blue, .green, .orange, .purple, .pink, .red, .cyan, .indigo, .mint, .teal
    ]
    
    static func colorForUser(userId: String, totalUsers: Int) -> Color {
        let index = abs(userId.hashValue) % userColors.count
        return userColors[index]
    }
    
    static func colorForIndex(_ index: Int) -> Color {
        return userColors[index % userColors.count]
    }
}

