import Foundation
import FirebaseFirestore

enum OfficeOperationType: String, Codable, CaseIterable, Identifiable {
    case creditCard = "Credit Card Receipt"
    case posClosing = "POS Daily Closing"
    case fuelReceipt = "Fuel Receipt"
    case washing = "Washing Expense"
    case additionalSales = "Additional Sales"
    case banking = "Banking Transaction"
    case trafficFine = "Traffic Fine"
    
    var id: String { self.rawValue }
    
    var icon: String {
        switch self {
        case .creditCard: return "creditcard.fill"
        case .posClosing: return "centsign.circle.fill"
        case .fuelReceipt: return "fuelpump.fill"
        case .washing: return "drop.fill"
        case .additionalSales: return "cart.fill"
        case .banking: return "building.columns.fill"
        case .trafficFine: return "exclamationmark.triangle.fill"
        }
    }
    
    var color: String {
        switch self {
        case .creditCard: return "blue"
        case .posClosing: return "green"
        case .fuelReceipt: return "orange"
        case .washing: return "cyan"
        case .additionalSales: return "purple"
        case .banking: return "indigo"
        case .trafficFine: return "red"
        }
    }
}

struct OfficeOperation: Identifiable, Codable {
    var id = UUID()
    var documentId: String? // Firebase document ID for web-compatible operations
    var type: OfficeOperationType
    var date: Date
    var amount: Double
    var photos: [String]
    var vehiclePlate: String?
    var posCount: Int?
    var posAmounts: [Double]?
    var notes: String
    var isCompleted: Bool = false // For fuel receipts - mark as done
    var createdBy: String? // User ID who created this record
    
    // MARK: - Additional Fields for Traffic Fines
    var fineNumber: String? // Traffic fine number/reference
    var fineType: String? // Type of traffic fine
    var paymentStatus: String? // Payment status (e.g., "Paid", "Pending", "Overdue")
    
    // MARK: - Additional Fields for Banking
    var transactionNumber: String? // Bank transaction number
    var bankName: String? // Bank name
    var accountNumber: String? // Account number (last 4 digits or masked)
    var transactionType: String? // Transaction type (e.g., "Transfer", "Payment", "Deposit")
    var referenceNumber: String? // Reference number for the transaction
    
    // MARK: - Additional Fields for Additional Sales
    var productName: String? // Product/service name
    var quantity: Double? // Quantity sold
    var unitPrice: Double? // Unit price
    var customerName: String? // Customer name
    var invoiceNumber: String? // Invoice number
    var franchiseId: String = "CH" // Franchise ID for data isolation
    
    enum CodingKeys: String, CodingKey {
        case id, documentId, type, date, amount, photos, vehiclePlate, posCount, posAmounts, notes, isCompleted, createdBy
        // Traffic Fine fields
        case fineNumber, fineType, paymentStatus
        // Banking fields
        case transactionNumber, bankName, accountNumber, transactionType, referenceNumber
        // Additional Sales fields
        case productName, quantity, unitPrice, customerName, invoiceNumber
        // Franchise
        case franchiseId
    }
    
    init(type: OfficeOperationType, date: Date = Date(), amount: Double = 0, photos: [String] = [], vehiclePlate: String? = nil, posCount: Int? = nil, posAmounts: [Double]? = nil, notes: String = "", isCompleted: Bool = false, fineNumber: String? = nil, fineType: String? = nil, paymentStatus: String? = nil, transactionNumber: String? = nil, bankName: String? = nil, accountNumber: String? = nil, transactionType: String? = nil, referenceNumber: String? = nil, productName: String? = nil, quantity: Double? = nil, unitPrice: Double? = nil, customerName: String? = nil, invoiceNumber: String? = nil, createdBy: String? = nil) {
        self.type = type
        self.date = date
        self.amount = amount
        self.photos = photos
        self.vehiclePlate = vehiclePlate
        self.posCount = posCount
        self.posAmounts = posAmounts
        self.notes = notes
        self.isCompleted = isCompleted
        // Traffic Fine fields
        self.fineNumber = fineNumber
        self.fineType = fineType
        self.paymentStatus = paymentStatus
        // Banking fields
        self.transactionNumber = transactionNumber
        self.bankName = bankName
        self.accountNumber = accountNumber
        self.transactionType = transactionType
        self.referenceNumber = referenceNumber
        // Additional Sales fields
        self.productName = productName
        self.quantity = quantity
        self.unitPrice = unitPrice
        self.customerName = customerName
        self.invoiceNumber = invoiceNumber
        self.createdBy = createdBy
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        // Handle id: can be UUID or String (for web-compatible operations)
        if let idString = try? container.decode(String.self, forKey: .id),
           let uuid = UUID(uuidString: idString) {
            id = uuid
        } else if let uuid = try? container.decode(UUID.self, forKey: .id) {
            id = uuid
        } else {
            // If both fail, generate a new UUID (fallback)
            id = UUID()
        }
        
        documentId = try container.decodeIfPresent(String.self, forKey: .documentId)
        type = try container.decode(OfficeOperationType.self, forKey: .type)
        
        // Handle date: can be Timestamp, Date, or TimeInterval (iOS format)
        if let timestamp = try? container.decode(Timestamp.self, forKey: .date) {
            date = timestamp.dateValue()
        } else if let dateValue = try? container.decode(Date.self, forKey: .date) {
            date = dateValue
        } else if let timeInterval = try? container.decode(Double.self, forKey: .date) {
            // iOS TimeInterval format (seconds since 2001-01-01)
            let referenceDate = Date(timeIntervalSinceReferenceDate: 0)
            let baseDate = Date(timeInterval: -978307200, since: referenceDate) // 2001-01-01
            date = Date(timeInterval: timeInterval, since: baseDate)
        } else {
            date = Date()
        }
        
        amount = try container.decode(Double.self, forKey: .amount)
        photos = try container.decodeIfPresent([String].self, forKey: .photos) ?? []
        vehiclePlate = try container.decodeIfPresent(String.self, forKey: .vehiclePlate)
        posCount = try container.decodeIfPresent(Int.self, forKey: .posCount)
        posAmounts = try container.decodeIfPresent([Double].self, forKey: .posAmounts)
        notes = try container.decodeIfPresent(String.self, forKey: .notes) ?? ""
        // Default to false if isCompleted is missing (for backward compatibility)
        isCompleted = try container.decodeIfPresent(Bool.self, forKey: .isCompleted) ?? false
        createdBy = try container.decodeIfPresent(String.self, forKey: .createdBy)
        
        // Decode additional fields for Traffic Fines (optional - won't break if missing)
        fineNumber = try container.decodeIfPresent(String.self, forKey: .fineNumber)
        fineType = try container.decodeIfPresent(String.self, forKey: .fineType)
        paymentStatus = try container.decodeIfPresent(String.self, forKey: .paymentStatus)
        
        // Decode additional fields for Banking (optional - won't break if missing)
        transactionNumber = try container.decodeIfPresent(String.self, forKey: .transactionNumber)
        bankName = try container.decodeIfPresent(String.self, forKey: .bankName)
        accountNumber = try container.decodeIfPresent(String.self, forKey: .accountNumber)
        transactionType = try container.decodeIfPresent(String.self, forKey: .transactionType)
        referenceNumber = try container.decodeIfPresent(String.self, forKey: .referenceNumber)
        
        // Decode additional fields for Additional Sales (optional - won't break if missing)
        productName = try container.decodeIfPresent(String.self, forKey: .productName)
        quantity = try container.decodeIfPresent(Double.self, forKey: .quantity)
        unitPrice = try container.decodeIfPresent(Double.self, forKey: .unitPrice)
        customerName = try container.decodeIfPresent(String.self, forKey: .customerName)
        invoiceNumber = try container.decodeIfPresent(String.self, forKey: .invoiceNumber)
        franchiseId = (try container.decodeIfPresent(String.self, forKey: .franchiseId) ?? "CH").uppercased()
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        
        // ID'yi string olarak encode et (web uyumluluğu için)
        try container.encode(id.uuidString, forKey: .id)
        
        // DocumentId varsa encode et
        if let documentId = documentId {
            try container.encode(documentId, forKey: .documentId)
        }
        
        try container.encode(type, forKey: .type)
        
        // Date'i iOS TimeInterval formatına çevir (seconds since 2001-01-01)
        // Web uygulaması ile uyumluluk için
        let referenceDate = Date(timeIntervalSinceReferenceDate: 0)
        let baseDate = Date(timeInterval: -978307200, since: referenceDate) // 2001-01-01
        let timeInterval = date.timeIntervalSince(baseDate)
        try container.encode(timeInterval, forKey: .date)
        
        try container.encode(amount, forKey: .amount)
        try container.encode(photos, forKey: .photos)
        try container.encodeIfPresent(vehiclePlate, forKey: .vehiclePlate)
        try container.encodeIfPresent(posCount, forKey: .posCount)
        try container.encodeIfPresent(posAmounts, forKey: .posAmounts)
        try container.encode(notes, forKey: .notes)
        try container.encode(isCompleted, forKey: .isCompleted)
        try container.encodeIfPresent(createdBy, forKey: .createdBy)
        
        // Encode additional fields for Traffic Fines (only if present)
        try container.encodeIfPresent(fineNumber, forKey: .fineNumber)
        try container.encodeIfPresent(fineType, forKey: .fineType)
        try container.encodeIfPresent(paymentStatus, forKey: .paymentStatus)
        
        // Encode additional fields for Banking (only if present)
        try container.encodeIfPresent(transactionNumber, forKey: .transactionNumber)
        try container.encodeIfPresent(bankName, forKey: .bankName)
        try container.encodeIfPresent(accountNumber, forKey: .accountNumber)
        try container.encodeIfPresent(transactionType, forKey: .transactionType)
        try container.encodeIfPresent(referenceNumber, forKey: .referenceNumber)
        
        // Encode additional fields for Additional Sales (only if present)
        try container.encodeIfPresent(productName, forKey: .productName)
        try container.encodeIfPresent(quantity, forKey: .quantity)
        try container.encodeIfPresent(unitPrice, forKey: .unitPrice)
        try container.encodeIfPresent(customerName, forKey: .customerName)
        try container.encodeIfPresent(invoiceNumber, forKey: .invoiceNumber)
        try container.encode(franchiseId, forKey: .franchiseId)
    }
}
