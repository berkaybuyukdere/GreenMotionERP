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
    
    init(type: OfficeOperationType, date: Date = Date(), amount: Double = 0, photos: [String] = [], vehiclePlate: String? = nil, posCount: Int? = nil, posAmounts: [Double]? = nil, notes: String = "") {
        self.type = type
        self.date = date
        self.amount = amount
        self.photos = photos
        self.vehiclePlate = vehiclePlate
        self.posCount = posCount
        self.posAmounts = posAmounts
        self.notes = notes
    }
}
