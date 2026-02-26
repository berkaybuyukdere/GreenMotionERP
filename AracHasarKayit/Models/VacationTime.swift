import Foundation
import FirebaseFirestore

struct VacationTime: Identifiable, Codable {
    var id = UUID()
    var documentId: String? // Firebase document ID
    var employeeName: String
    var startDate: Date
    var endDate: Date
    var isActive: Bool = true
    var createdBy: String // User email
    var createdAt: Date = Date()
    var franchiseId: String = "CH" // Franchise ID for data isolation
    
    enum CodingKeys: String, CodingKey {
        case id, documentId, employeeName, startDate, endDate, isActive, createdBy, createdAt, franchiseId
    }
    
    init(id: UUID = UUID(), documentId: String? = nil, employeeName: String, startDate: Date, endDate: Date, isActive: Bool = true, createdBy: String, createdAt: Date = Date()) {
        self.id = id
        self.documentId = documentId
        self.employeeName = employeeName
        self.startDate = startDate
        self.endDate = endDate
        self.isActive = isActive
        self.createdBy = createdBy
        self.createdAt = createdAt
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        // Handle id: can be UUID or String
        if let idString = try? container.decode(String.self, forKey: .id),
           let uuid = UUID(uuidString: idString) {
            id = uuid
        } else if let uuid = try? container.decode(UUID.self, forKey: .id) {
            id = uuid
        } else {
            id = UUID()
        }
        
        documentId = try container.decodeIfPresent(String.self, forKey: .documentId)
        employeeName = try container.decode(String.self, forKey: .employeeName)
        
        // Handle date: can be Timestamp, Date, or TimeInterval
        if let timestamp = try? container.decode(Timestamp.self, forKey: .startDate) {
            startDate = timestamp.dateValue()
        } else if let dateValue = try? container.decode(Date.self, forKey: .startDate) {
            startDate = dateValue
        } else if let timeInterval = try? container.decode(Double.self, forKey: .startDate) {
            let referenceDate = Date(timeIntervalSinceReferenceDate: 0)
            let baseDate = Date(timeInterval: -978307200, since: referenceDate) // 2001-01-01
            startDate = Date(timeInterval: timeInterval, since: baseDate)
        } else {
            startDate = Date()
        }
        
        if let timestamp = try? container.decode(Timestamp.self, forKey: .endDate) {
            endDate = timestamp.dateValue()
        } else if let dateValue = try? container.decode(Date.self, forKey: .endDate) {
            endDate = dateValue
        } else if let timeInterval = try? container.decode(Double.self, forKey: .endDate) {
            let referenceDate = Date(timeIntervalSinceReferenceDate: 0)
            let baseDate = Date(timeInterval: -978307200, since: referenceDate) // 2001-01-01
            endDate = Date(timeInterval: timeInterval, since: baseDate)
        } else {
            endDate = Date()
        }
        
        isActive = try container.decodeIfPresent(Bool.self, forKey: .isActive) ?? true
        createdBy = try container.decode(String.self, forKey: .createdBy)
        
        if let timestamp = try? container.decode(Timestamp.self, forKey: .createdAt) {
            createdAt = timestamp.dateValue()
        } else if let dateValue = try? container.decode(Date.self, forKey: .createdAt) {
            createdAt = dateValue
        } else if let timeInterval = try? container.decode(Double.self, forKey: .createdAt) {
            let referenceDate = Date(timeIntervalSinceReferenceDate: 0)
            let baseDate = Date(timeInterval: -978307200, since: referenceDate) // 2001-01-01
            createdAt = Date(timeInterval: timeInterval, since: baseDate)
        } else {
            createdAt = Date()
        }
        
        franchiseId = (try container.decodeIfPresent(String.self, forKey: .franchiseId) ?? "CH").uppercased()
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        
        try container.encode(id.uuidString, forKey: .id)
        
        if let documentId = documentId {
            try container.encode(documentId, forKey: .documentId)
        }
        
        try container.encode(employeeName, forKey: .employeeName)
        
        // Encode dates as TimeInterval (seconds since 2001-01-01) for web compatibility
        let referenceDate = Date(timeIntervalSinceReferenceDate: 0)
        let baseDate = Date(timeInterval: -978307200, since: referenceDate) // 2001-01-01
        
        let startTimeInterval = startDate.timeIntervalSince(baseDate)
        try container.encode(startTimeInterval, forKey: .startDate)
        
        let endTimeInterval = endDate.timeIntervalSince(baseDate)
        try container.encode(endTimeInterval, forKey: .endDate)
        
        try container.encode(isActive, forKey: .isActive)
        try container.encode(createdBy, forKey: .createdBy)
        
        let createdAtTimeInterval = createdAt.timeIntervalSince(baseDate)
        try container.encode(createdAtTimeInterval, forKey: .createdAt)
        try container.encode(franchiseId, forKey: .franchiseId)
    }
    
    // Helper: Check if a date is within vacation period
    func contains(date: Date) -> Bool {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: startDate)
        let end = calendar.startOfDay(for: endDate)
        let checkDate = calendar.startOfDay(for: date)
        
        return checkDate >= start && checkDate <= end && isActive
    }
}

