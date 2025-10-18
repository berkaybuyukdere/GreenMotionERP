import Foundation
import FirebaseFirestore
import CoreLocation

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
    var location: GeoPointData?
    var sessionId: String
    
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

// MARK: - Geo Point Data (Codable wrapper for location)

struct GeoPointData: Codable, Equatable {
    var latitude: Double
    var longitude: Double
    
    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
    
    init(latitude: Double, longitude: Double) {
        self.latitude = latitude
        self.longitude = longitude
    }
    
    init(coordinate: CLLocationCoordinate2D) {
        self.latitude = coordinate.latitude
        self.longitude = coordinate.longitude
    }
    
    // Convert to Firestore GeoPoint
    var geoPoint: GeoPoint {
        GeoPoint(latitude: latitude, longitude: longitude)
    }
    
    // Create from Firestore GeoPoint
    static func from(geoPoint: GeoPoint) -> GeoPointData {
        GeoPointData(latitude: geoPoint.latitude, longitude: geoPoint.longitude)
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

// MARK: - Shuttle Location Update (Real-time tracking)

struct ShuttleLocation: Identifiable, Codable {
    @DocumentID var id: String?
    var driverName: String
    var driverUID: String
    var location: GeoPointData
    var timestamp: Date
    var isActive: Bool
    var speed: Double? // km/h
    var heading: Double? // degrees
    
    var formattedTime: String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: timestamp)
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

