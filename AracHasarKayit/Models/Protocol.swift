import Foundation

struct Protocol: Identifiable, Codable {
    var id: String
    let baseCost: String
    let checkInDate: String
    let checkOutDate: String
    let createdAt: String
    let createdBy: String
    let customerName: String
    let fieldValues: String
    let protocolId: String
    let protocolName: String
    let protocolType: String
    let reservationNumber: String
    var status: String
    let templatePath: String
    var updatedAt: String
    let updatedBy: String
    let vehiclePlate: String
    
    enum CodingKeys: String, CodingKey {
        case baseCost = "baseCost"
        case checkInDate = "checkInDate"
        case checkOutDate = "checkOutDate"
        case createdAt = "createdAt"
        case createdBy = "createdBy"
        case customerName = "customerName"
        case fieldValues = "fieldValues"
        case protocolId = "protocolId"
        case protocolName = "protocolName"
        case protocolType = "protocolType"
        case reservationNumber = "reservationNumber"
        case status = "status"
        case templatePath = "templatePath"
        case updatedAt = "updatedAt"
        case updatedBy = "updatedBy"
        case vehiclePlate = "vehiclePlate"
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        // The id will be set from the Firebase key in the service
        self.id = "" // Will be set by the service
        
        self.baseCost = try container.decode(String.self, forKey: .baseCost)
        self.checkInDate = try container.decode(String.self, forKey: .checkInDate)
        self.checkOutDate = try container.decode(String.self, forKey: .checkOutDate)
        self.createdAt = try container.decode(String.self, forKey: .createdAt)
        self.createdBy = try container.decode(String.self, forKey: .createdBy)
        self.customerName = try container.decode(String.self, forKey: .customerName)
        self.fieldValues = try container.decode(String.self, forKey: .fieldValues)
        self.protocolId = try container.decode(String.self, forKey: .protocolId)
        self.protocolName = try container.decode(String.self, forKey: .protocolName)
        self.protocolType = try container.decode(String.self, forKey: .protocolType)
        self.reservationNumber = try container.decode(String.self, forKey: .reservationNumber)
        self.status = try container.decode(String.self, forKey: .status)
        self.templatePath = try container.decode(String.self, forKey: .templatePath)
        self.updatedAt = try container.decode(String.self, forKey: .updatedAt)
        self.updatedBy = try container.decode(String.self, forKey: .updatedBy)
        self.vehiclePlate = try container.decode(String.self, forKey: .vehiclePlate)
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(baseCost, forKey: .baseCost)
        try container.encode(checkInDate, forKey: .checkInDate)
        try container.encode(checkOutDate, forKey: .checkOutDate)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(createdBy, forKey: .createdBy)
        try container.encode(customerName, forKey: .customerName)
        try container.encode(fieldValues, forKey: .fieldValues)
        try container.encode(protocolId, forKey: .protocolId)
        try container.encode(protocolName, forKey: .protocolName)
        try container.encode(protocolType, forKey: .protocolType)
        try container.encode(reservationNumber, forKey: .reservationNumber)
        try container.encode(status, forKey: .status)
        try container.encode(templatePath, forKey: .templatePath)
        try container.encode(updatedAt, forKey: .updatedAt)
        try container.encode(updatedBy, forKey: .updatedBy)
        try container.encode(vehiclePlate, forKey: .vehiclePlate)
    }
    
    // Custom initializer for setting ID from Firebase key
    init(id: String, baseCost: String, checkInDate: String, checkOutDate: String, createdAt: String, createdBy: String, customerName: String, fieldValues: String, protocolId: String, protocolName: String, protocolType: String, reservationNumber: String, status: String, templatePath: String, updatedAt: String, updatedBy: String, vehiclePlate: String) {
        self.id = id
        self.baseCost = baseCost
        self.checkInDate = checkInDate
        self.checkOutDate = checkOutDate
        self.createdAt = createdAt
        self.createdBy = createdBy
        self.customerName = customerName
        self.fieldValues = fieldValues
        self.protocolId = protocolId
        self.protocolName = protocolName
        self.protocolType = protocolType
        self.reservationNumber = reservationNumber
        self.status = status
        self.templatePath = templatePath
        self.updatedAt = updatedAt
        self.updatedBy = updatedBy
        self.vehiclePlate = vehiclePlate
    }
    
    // Computed properties for better usability
    var checkInDateFormatted: Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: checkInDate)
    }
    
    var checkOutDateFormatted: Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: checkOutDate)
    }
    
    var createdAtFormatted: Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: createdAt)
    }
    
    var updatedAtFormatted: Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: updatedAt)
    }
    
    var baseCostDouble: Double? {
        guard let value = Double(baseCost), value.isFinite else { return nil }
        return value
    }
    
    var fieldValuesDict: [String: String]? {
        guard let data = fieldValues.data(using: .utf8) else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: String]
    }
    
    var statusColor: String {
        switch status.uppercased() {
        case "PENDING": return "orange"
        case "COMPLETED": return "green"
        case "CANCELLED": return "red"
        case "IN_PROGRESS": return "blue"
        default: return "gray"
        }
    }
    
    var statusIcon: String {
        switch status.uppercased() {
        case "PENDING": return "clock.fill"
        case "COMPLETED": return "checkmark.circle.fill"
        case "CANCELLED": return "xmark.circle.fill"
        case "IN_PROGRESS": return "play.circle.fill"
        default: return "questionmark.circle.fill"
        }
    }
}

// MARK: - Protocol Status Enum
enum ProtocolStatus: String, CaseIterable, Identifiable {
    case draft = "DRAFT"
    case pending = "PENDING"
    case complete = "COMPLETE"
    case overdue = "OVERDUE"
    case cancelled = "CANCELLED"
    
    var id: String { self.rawValue }
    
    var displayName: String {
        switch self {
        case .draft: return "Draft"
        case .pending: return "Pending"
        case .complete: return "Complete"
        case .overdue: return "Overdue"
        case .cancelled: return "Cancelled"
        }
    }
    
    var color: String {
        switch self {
        case .draft: return "gray"
        case .pending: return "orange"
        case .complete: return "green"
        case .overdue: return "red"
        case .cancelled: return "red"
        }
    }
    
    var icon: String {
        switch self {
        case .draft: return "doc.text"
        case .pending: return "clock.fill"
        case .complete: return "checkmark.circle.fill"
        case .overdue: return "exclamationmark.triangle.fill"
        case .cancelled: return "xmark.circle.fill"
        }
    }
}
