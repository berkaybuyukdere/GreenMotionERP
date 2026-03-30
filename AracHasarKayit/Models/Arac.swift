import Foundation

struct LastCheckInSnapshot: Codable, Equatable, Hashable, Identifiable {
    var id: UUID
    var timestamp: Date
    var km: Int
    /// Fuel gauge step 0…8 (8 = full). Drives `fuelLevel` / `fuelTankFull` for legacy APIs.
    var fuelEighths: Int
    /// Legacy field; kept for Firestore / API compatibility.
    var fuelLevel: Double
    var fuelTankFull: Bool
    var reservationNumber: String
    var checkedInBy: String
    var customerName: String?
    var linkedExitId: UUID?
    
    enum CodingKeys: String, CodingKey {
        case id, timestamp, km, fuelEighths, fuelLevel, fuelTankFull, reservationNumber, checkedInBy, customerName, linkedExitId
    }
    
    init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        km: Int,
        fuelEighths: Int,
        reservationNumber: String,
        checkedInBy: String,
        customerName: String? = nil,
        linkedExitId: UUID? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.km = km
        let fe = min(8, max(0, fuelEighths))
        self.fuelEighths = fe
        self.fuelLevel = Double(fe) / 8.0
        self.fuelTankFull = fe >= 8
        self.reservationNumber = reservationNumber
        self.checkedInBy = checkedInBy
        self.customerName = customerName
        self.linkedExitId = linkedExitId
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        self.timestamp = try container.decode(Date.self, forKey: .timestamp)
        self.km = try container.decode(Int.self, forKey: .km)
        
        if let fe = try container.decodeIfPresent(Int.self, forKey: .fuelEighths) {
            self.fuelEighths = min(8, max(0, fe))
        } else {
            let fl = try container.decodeIfPresent(Double.self, forKey: .fuelLevel) ?? 1.0
            self.fuelEighths = min(8, max(0, Int(round(fl * 8.0))))
        }
        self.fuelLevel = Double(self.fuelEighths) / 8.0
        
        if let full = try container.decodeIfPresent(Bool.self, forKey: .fuelTankFull) {
            self.fuelTankFull = full
        } else {
            self.fuelTankFull = self.fuelEighths >= 8
        }
        self.reservationNumber = try container.decode(String.self, forKey: .reservationNumber)
        self.checkedInBy = try container.decode(String.self, forKey: .checkedInBy)
        self.customerName = try container.decodeIfPresent(String.self, forKey: .customerName)
        self.linkedExitId = try container.decodeIfPresent(UUID.self, forKey: .linkedExitId)
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(timestamp, forKey: .timestamp)
        try container.encode(km, forKey: .km)
        try container.encode(fuelEighths, forKey: .fuelEighths)
        try container.encode(fuelLevel, forKey: .fuelLevel)
        try container.encode(fuelTankFull, forKey: .fuelTankFull)
        try container.encode(reservationNumber, forKey: .reservationNumber)
        try container.encode(checkedInBy, forKey: .checkedInBy)
        try container.encodeIfPresent(customerName, forKey: .customerName)
        try container.encodeIfPresent(linkedExitId, forKey: .linkedExitId)
    }
}

struct Arac: Identifiable, Codable, Equatable, Hashable {
    var id = UUID()
    var plaka: String
    var marka: String
    var model: String
    var kategori: String
    var vignetteVar: Bool
    var kayitTarihi: Date
    var hasarKayitlari: [HasarKaydi]
    var qrCode: String
    var spareKeyCount: Int
    var headDocumentURL: String?
    var createdBy: String?
    var assistantCompanyName: String?
    var assistantCompanyPhone: String?
    /// Operational check-ins (history). `lastCheckIn` is the latest by timestamp.
    var checkInKayitlari: [LastCheckInSnapshot]
    var franchiseId: String = "CH"
    /// Soft-delete flags (audit/compliance). Hard delete is reserved for admin cleanup.
    var isDeleted: Bool = false
    var deletedAt: Date?
    var deletedBy: String?
    
    var lastCheckIn: LastCheckInSnapshot? {
        checkInKayitlari.max { a, b in
            if a.timestamp != b.timestamp { return a.timestamp < b.timestamp }
            return a.id.uuidString < b.id.uuidString
        }
    }
    
    enum CodingKeys: String, CodingKey {
        case id, plaka, marka, model, kategori, vignetteVar, kayitTarihi, hasarKayitlari, qrCode, spareKeyCount
        case headDocumentURL, createdBy, assistantCompanyName, assistantCompanyPhone
        case checkInKayitlari, lastCheckIn, franchiseId
        case isDeleted, deletedAt, deletedBy
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(UUID.self, forKey: .id)
        self.plaka = try container.decode(String.self, forKey: .plaka)
        self.marka = try container.decode(String.self, forKey: .marka)
        self.model = try container.decode(String.self, forKey: .model)
        self.kategori = try container.decode(String.self, forKey: .kategori)
        self.vignetteVar = try container.decode(Bool.self, forKey: .vignetteVar)
        self.kayitTarihi = try container.decode(Date.self, forKey: .kayitTarihi)
        self.hasarKayitlari = try container.decode([HasarKaydi].self, forKey: .hasarKayitlari)
        self.qrCode = try container.decode(String.self, forKey: .qrCode)
        self.spareKeyCount = (try? container.decode(Int.self, forKey: .spareKeyCount)) ?? 0
        self.headDocumentURL = try? container.decode(String.self, forKey: .headDocumentURL)
        self.createdBy = try container.decodeIfPresent(String.self, forKey: .createdBy)
        self.assistantCompanyName = try container.decodeIfPresent(String.self, forKey: .assistantCompanyName)
        self.assistantCompanyPhone = try container.decodeIfPresent(String.self, forKey: .assistantCompanyPhone)
        
        let fromArray = try container.decodeIfPresent([LastCheckInSnapshot].self, forKey: .checkInKayitlari)
        let legacySingle = try container.decodeIfPresent(LastCheckInSnapshot.self, forKey: .lastCheckIn)
        if let arr = fromArray, !arr.isEmpty {
            self.checkInKayitlari = arr
        } else if let one = legacySingle {
            self.checkInKayitlari = [one]
        } else {
            self.checkInKayitlari = []
        }
        self.franchiseId = (try container.decodeIfPresent(String.self, forKey: .franchiseId) ?? "CH").uppercased()
        self.isDeleted = try container.decodeIfPresent(Bool.self, forKey: .isDeleted) ?? false
        self.deletedAt = try container.decodeIfPresent(Date.self, forKey: .deletedAt)
        self.deletedBy = try container.decodeIfPresent(String.self, forKey: .deletedBy)
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(plaka, forKey: .plaka)
        try container.encode(marka, forKey: .marka)
        try container.encode(model, forKey: .model)
        try container.encode(kategori, forKey: .kategori)
        try container.encode(vignetteVar, forKey: .vignetteVar)
        try container.encode(kayitTarihi, forKey: .kayitTarihi)
        try container.encode(hasarKayitlari, forKey: .hasarKayitlari)
        try container.encode(qrCode, forKey: .qrCode)
        try container.encode(spareKeyCount, forKey: .spareKeyCount)
        try container.encodeIfPresent(headDocumentURL, forKey: .headDocumentURL)
        try container.encodeIfPresent(createdBy, forKey: .createdBy)
        try container.encodeIfPresent(assistantCompanyName, forKey: .assistantCompanyName)
        try container.encodeIfPresent(assistantCompanyPhone, forKey: .assistantCompanyPhone)
        try container.encode(checkInKayitlari, forKey: .checkInKayitlari)
        if let latest = lastCheckIn {
            try container.encode(latest, forKey: .lastCheckIn)
        }
        try container.encode(franchiseId, forKey: .franchiseId)
        try container.encode(isDeleted, forKey: .isDeleted)
        try container.encodeIfPresent(deletedAt, forKey: .deletedAt)
        try container.encodeIfPresent(deletedBy, forKey: .deletedBy)
    }
    
    init(plaka: String, marka: String, model: String, kategori: String = "", vignetteVar: Bool = false, spareKeyCount: Int = 0, headDocumentURL: String? = nil, createdBy: String? = nil, assistantCompanyName: String? = nil, assistantCompanyPhone: String? = nil) {
        self.plaka = plaka
        self.marka = marka
        self.model = model
        self.kategori = kategori
        self.vignetteVar = vignetteVar
        self.kayitTarihi = Date()
        self.hasarKayitlari = []
        self.qrCode = plaka
        self.spareKeyCount = spareKeyCount
        self.headDocumentURL = headDocumentURL
        self.createdBy = createdBy
        self.assistantCompanyName = assistantCompanyName
        self.assistantCompanyPhone = assistantCompanyPhone
        self.checkInKayitlari = []
        self.isDeleted = false
    }
    
    var plakaFormatli: String {
        guard plaka.count >= 2 else { return plaka }
        
        let cleanPlaka = plaka.replacingOccurrences(of: " ", with: "").uppercased()
        
        var result = ""
        var digitStart = -1
        
        for (index, char) in cleanPlaka.enumerated() {
            if char.isNumber && digitStart == -1 {
                digitStart = index
            }
            result.append(char)
        }
        
        if digitStart > 0 && digitStart < cleanPlaka.count {
            let firstPart = String(cleanPlaka.prefix(digitStart))
            let secondPart = String(cleanPlaka.suffix(from: cleanPlaka.index(cleanPlaka.startIndex, offsetBy: digitStart)))
            return "\(firstPart) \(secondPart)"
        }
        
        return cleanPlaka
    }
}
