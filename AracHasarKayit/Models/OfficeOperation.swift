import Foundation

enum OfficeOperationType: String, Codable, CaseIterable, Identifiable {
    case creditCard = "Credit Card Receipt"
    case posClosing = "POS Daily Closing"
    case fuelReceipt = "Fuel Receipt"
    case washing = "Washing Expense"
    
    var id: String { self.rawValue }
    
    var icon: String {
        switch self {
        case .creditCard: return "creditcard.fill"
        case .posClosing: return "centsign.circle.fill"
        case .fuelReceipt: return "fuelpump.fill"
        case .washing: return "drop.fill"
        }
    }
    
    var color: String {
        switch self {
        case .creditCard: return "blue"
        case .posClosing: return "green"
        case .fuelReceipt: return "orange"
        case .washing: return "cyan"
        }
    }
}

struct OfficeOperation: Identifiable, Codable {
    var id = UUID()
    var type: OfficeOperationType
    var date: Date
    var amount: Double
    var photos: [String]
    var vehiclePlate: String?
    var posCount: Int?
    var posAmounts: [Double]?
    var notes: String
    var isCompleted: Bool = false // For fuel receipts - mark as done
    
    enum CodingKeys: String, CodingKey {
        case id, type, date, amount, photos, vehiclePlate, posCount, posAmounts, notes, isCompleted
    }
    
    init(type: OfficeOperationType, date: Date = Date(), amount: Double = 0, photos: [String] = [], vehiclePlate: String? = nil, posCount: Int? = nil, posAmounts: [Double]? = nil, notes: String = "", isCompleted: Bool = false) {
        self.type = type
        self.date = date
        self.amount = amount
        self.photos = photos
        self.vehiclePlate = vehiclePlate
        self.posCount = posCount
        self.posAmounts = posAmounts
        self.notes = notes
        self.isCompleted = isCompleted
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        type = try container.decode(OfficeOperationType.self, forKey: .type)
        date = try container.decode(Date.self, forKey: .date)
        amount = try container.decode(Double.self, forKey: .amount)
        photos = try container.decode([String].self, forKey: .photos)
        vehiclePlate = try container.decodeIfPresent(String.self, forKey: .vehiclePlate)
        posCount = try container.decodeIfPresent(Int.self, forKey: .posCount)
        posAmounts = try container.decodeIfPresent([Double].self, forKey: .posAmounts)
        notes = try container.decodeIfPresent(String.self, forKey: .notes) ?? ""
        // Default to false if isCompleted is missing (for backward compatibility)
        isCompleted = try container.decodeIfPresent(Bool.self, forKey: .isCompleted) ?? false
    }
}
