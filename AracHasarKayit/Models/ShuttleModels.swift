import Foundation
import FirebaseFirestore

// MARK: - Shuttle Entry Type

enum ShuttleEntryType: String, Codable {
    case pickup = "Pick Up"
    case dropoff = "Drop Off"
    
    var icon: String {
        switch self {
        case .pickup: return "arrow.down.circle.fill"
        case .dropoff: return "arrow.up.circle.fill"
        }
    }
    
    var color: String {
        switch self {
        case .pickup: return "green"
        case .dropoff: return "blue"
        }
    }
}

// MARK: - Shuttle Entry

struct ShuttleEntry: Identifiable, Codable, Equatable {
    @DocumentID var id: String?
    var customerCount: Int
    var entryType: ShuttleEntryType
    var timestamp: Date
    var driverName: String
    var driverUID: String
    var sessionId: String
    var franchiseId: String = "ch" // Franchise ID for data isolation
    
    var formattedTime: String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: timestamp)
    }
    
    var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter.string(from: timestamp)
    }
    
    var formattedDateTime: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: timestamp)
    }
}

// MARK: - Shuttle Session (Daily summary)

struct ShuttleSession: Identifiable, Codable, Equatable {
    @DocumentID var id: String?
    var date: Date
    var driverName: String
    var driverUID: String
    var entries: [ShuttleEntry] // Entry objects
    var totalCustomers: Int
    var isActive: Bool
    var startTime: Date
    var endTime: Date?
    var franchiseId: String = "ch" // Franchise ID for data isolation
    
    // Normal init for creating new sessions
    init(date: Date, driverName: String, driverUID: String, entries: [ShuttleEntry], totalCustomers: Int, isActive: Bool, startTime: Date, endTime: Date? = nil, franchiseId: String = "ch") {
        self.date = date
        self.driverName = driverName
        self.driverUID = driverUID
        self.entries = entries
        self.totalCustomers = totalCustomers
        self.isActive = isActive
        self.startTime = startTime
        self.endTime = endTime
        self.franchiseId = franchiseId
    }
    
    // Custom decoder to handle missing entryType field
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        id = try container.decodeIfPresent(String.self, forKey: .id)
        date = try container.decode(Date.self, forKey: .date)
        driverName = try container.decode(String.self, forKey: .driverName)
        driverUID = try container.decode(String.self, forKey: .driverUID)
        totalCustomers = try container.decode(Int.self, forKey: .totalCustomers)
        isActive = try container.decode(Bool.self, forKey: .isActive)
        startTime = try container.decode(Date.self, forKey: .startTime)
        endTime = try container.decodeIfPresent(Date.self, forKey: .endTime)
        franchiseId = try container.decodeIfPresent(String.self, forKey: .franchiseId) ?? "ch"
        
        // Handle entries - try to decode normally first, fallback to empty array
        do {
            entries = try container.decode([ShuttleEntry].self, forKey: .entries)
        } catch {
            print("⚠️ Error parsing shuttle entries: \(error)")
            entries = []
        }
    }
    
    var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .long
        return formatter.string(from: date)
    }
    
    var duration: String {
        guard let end = endTime else {
            return "Active"
        }
        let interval = end.timeIntervalSince(startTime)
        let hours = Int(interval) / 3600
        let minutes = Int(interval) / 60 % 60
        return String(format: "%dh %dm", hours, minutes)
    }
}

// MARK: - Daily Report Summary

struct DailyShuttleReport: Codable {
    var date: Date
    var driverName: String
    var totalCustomers: Int
    var totalTrips: Int
    var entries: [ShuttleEntry]
    var startTime: Date
    var endTime: Date
    
    var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .long
        return formatter.string(from: date)
    }
    
    var duration: String {
        let interval = endTime.timeIntervalSince(startTime)
        let hours = Int(interval) / 3600
        let minutes = Int(interval) / 60 % 60
        return "\(hours)h \(minutes)m"
    }
    
    var averageCustomersPerTrip: Double {
        totalTrips > 0 ? Double(totalCustomers) / Double(totalTrips) : 0
    }
}

