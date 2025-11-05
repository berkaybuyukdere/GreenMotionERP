import Foundation

enum OfficeReturnReason: String, Codable, CaseIterable, Identifiable {
    case vehicleReturn = "Vehicle Return"
    case cancellation = "Cancellation"
    case refund = "Refund"
    case damageClaim = "Damage Claim"
    case other = "Other"
    
    var id: String { self.rawValue }
    
    var icon: String {
        switch self {
        case .vehicleReturn: return "arrow.uturn.backward.circle.fill"
        case .cancellation: return "xmark.circle.fill"
        case .refund: return "arrow.clockwise.circle.fill"
        case .damageClaim: return "exclamationmark.triangle.fill"
        case .other: return "ellipsis.circle.fill"
        }
    }
    
    var color: String {
        switch self {
        case .vehicleReturn: return "blue"
        case .cancellation: return "red"
        case .refund: return "green"
        case .damageClaim: return "orange"
        case .other: return "gray"
        }
    }
}

struct OfficeReturn: Identifiable, Codable, Hashable {
    var id = UUID()
    var amount: Double
    var reason: OfficeReturnReason
    var date: Date
    var photos: [String]
    var notes: String
    
    init(amount: Double, reason: OfficeReturnReason, date: Date = Date(), photos: [String] = [], notes: String = "") {
        self.amount = amount
        self.reason = reason
        self.date = date
        self.photos = photos
        self.notes = notes
    }
}

