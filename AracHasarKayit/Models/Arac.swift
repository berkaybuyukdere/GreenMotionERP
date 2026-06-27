import Foundation

struct VehicleWashingRecord: Codable, Equatable, Hashable, Identifiable {
    var id: UUID
    var createdAt: Date
    var price: Double
    var createdBy: String
    var photoURLs: [String]
    var notes: String?
    var franchiseId: String = "CH"
    
    enum CodingKeys: String, CodingKey {
        case id, createdAt, price, createdBy, photoURLs, notes, franchiseId
    }
    
    init(
        id: UUID = UUID(),
        createdAt: Date = Date(),
        price: Double,
        createdBy: String,
        photoURLs: [String] = [],
        notes: String? = nil,
        franchiseId: String = "CH"
    ) {
        self.id = id
        self.createdAt = createdAt
        self.price = price
        self.createdBy = createdBy
        self.photoURLs = photoURLs
        self.notes = notes
        self.franchiseId = franchiseId.uppercased()
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        self.createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        self.price = try container.decodeIfPresent(Double.self, forKey: .price) ?? 0
        self.createdBy = try container.decodeIfPresent(String.self, forKey: .createdBy) ?? "Unknown"
        self.photoURLs = try container.decodeIfPresent([String].self, forKey: .photoURLs) ?? []
        self.notes = try container.decodeIfPresent(String.self, forKey: .notes)
        self.franchiseId = (try container.decodeIfPresent(String.self, forKey: .franchiseId) ?? "CH").uppercased()
    }
}

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
    /// Optional VIN / chassis number (fleet import + manual entry).
    var vin: String?
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
    /// Vehicle-scoped washing expense history (also mirrored into office operations).
    var washingRecords: [VehicleWashingRecord]
    var franchiseId: String = "CH"
    /// Türkiye: aracın bağlı olduğu şube (`TurkiyeGarajSubeleri` anahtarı veya serbest id).
    var garageBranchId: String?
    /// Soft-delete flags (audit/compliance). Hard delete is reserved for admin cleanup.
    var isDeleted: Bool = false
    var deletedAt: Date?
    var deletedBy: String?

    // MARK: WheelSys link (CH only — populated by fleet chart entity sync)
    /// Fleet chart resource id (stable vehicle identity in WheelSys).
    var wheelsysVehicleId: String?
    /// Active rental entityId (runtime; refreshed by sync, used for check-in).
    var wheelsysRentalEntityId: Int?
    /// Canonical plate used for the last successful match (sync cache).
    var wheelsysPlateCanonical: String?
    /// When the entity link was last verified against fleet data.
    var wheelsysEntityVerifiedAt: Date?
    /// "matched" | "unmatched" | "ambiguous".
    var wheelsysEntitySyncStatus: String?

    // MARK: WheelSys NTR (non-revenue ticket)
    var wheelsysNtrEntityId: Int?
    var wheelsysNtrDocNo: String?
    var wheelsysNtrStatus: String?
    var wheelsysNtrSyncStatus: String?
    var wheelsysNtrCreatedByUserId: String?
    var wheelsysNtrCreatedByUserName: String?
    var wheelsysNtrStartedAt: Date?
    var wheelsysNtrStartKm: Int?
    var wheelsysNtrStartFuel: Int?
    var wheelsysNtrClosedByUserId: String?
    var wheelsysNtrClosedByUserName: String?
    var wheelsysNtrClosedAt: Date?
    var wheelsysNtrCloseKm: Int?
    var wheelsysNtrCloseFuel: Int?
    var wheelsysNtrMilesTravelled: Int?
    var wheelsysNtrFuelUsed: Int?
    var wheelsysNtrLastSyncError: String?
    var wheelsysNtrHistory: [WheelSysNTRHistoryEntry]

    var lastCheckIn: LastCheckInSnapshot? {
        checkInKayitlari.max { a, b in
            if a.timestamp != b.timestamp { return a.timestamp < b.timestamp }
            return a.id.uuidString < b.id.uuidString
        }
    }
    
    enum CodingKeys: String, CodingKey {
        case id, plaka, marka, model, vin, kategori, vignetteVar, kayitTarihi, hasarKayitlari, qrCode, spareKeyCount
        case headDocumentURL, createdBy, assistantCompanyName, assistantCompanyPhone
        case checkInKayitlari, lastCheckIn, washingRecords, franchiseId, garageBranchId
        case isDeleted, deletedAt, deletedBy
        case wheelsysVehicleId, wheelsysRentalEntityId, wheelsysPlateCanonical
        case wheelsysEntityVerifiedAt, wheelsysEntitySyncStatus
        case wheelsysNtrEntityId, wheelsysNtrDocNo, wheelsysNtrStatus, wheelsysNtrSyncStatus
        case wheelsysNtrCreatedByUserId, wheelsysNtrCreatedByUserName, wheelsysNtrStartedAt
        case wheelsysNtrStartKm, wheelsysNtrStartFuel
        case wheelsysNtrClosedByUserId, wheelsysNtrClosedByUserName, wheelsysNtrClosedAt
        case wheelsysNtrCloseKm, wheelsysNtrCloseFuel, wheelsysNtrMilesTravelled, wheelsysNtrFuelUsed
        case wheelsysNtrLastSyncError, wheelsysNtrHistory
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        // Backward-compatible decoding: older documents may be missing some fields.
        // We prefer to keep the record (and its damage history) rather than failing decoding.
        self.id = (try? container.decode(UUID.self, forKey: .id)) ?? UUID()
        self.plaka = (try? container.decode(String.self, forKey: .plaka)) ?? ""
        self.marka = (try? container.decode(String.self, forKey: .marka)) ?? ""
        self.model = (try? container.decode(String.self, forKey: .model)) ?? ""
        if let rawVin = try container.decodeIfPresent(String.self, forKey: .vin) {
            let t = rawVin.trimmingCharacters(in: .whitespacesAndNewlines)
            self.vin = t.isEmpty ? nil : t
        } else {
            self.vin = nil
        }
        self.kategori = (try? container.decode(String.self, forKey: .kategori)) ?? ""
        self.vignetteVar = (try? container.decode(Bool.self, forKey: .vignetteVar)) ?? false
        self.kayitTarihi = (try? container.decode(Date.self, forKey: .kayitTarihi)) ?? Date(timeIntervalSince1970: 0)
        self.hasarKayitlari = (try? container.decode([HasarKaydi].self, forKey: .hasarKayitlari)) ?? []
        self.qrCode = (try? container.decode(String.self, forKey: .qrCode)) ?? self.plaka
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
        self.washingRecords = try container.decodeIfPresent([VehicleWashingRecord].self, forKey: .washingRecords) ?? []
        self.franchiseId = (try container.decodeIfPresent(String.self, forKey: .franchiseId) ?? "CH").uppercased()
        self.garageBranchId = try container.decodeIfPresent(String.self, forKey: .garageBranchId)
        self.isDeleted = try container.decodeIfPresent(Bool.self, forKey: .isDeleted) ?? false
        self.deletedAt = try container.decodeIfPresent(Date.self, forKey: .deletedAt)
        self.deletedBy = try container.decodeIfPresent(String.self, forKey: .deletedBy)
        self.wheelsysVehicleId = try container.decodeIfPresent(String.self, forKey: .wheelsysVehicleId)
        self.wheelsysRentalEntityId = try container.decodeIfPresent(Int.self, forKey: .wheelsysRentalEntityId)
        self.wheelsysPlateCanonical = try container.decodeIfPresent(String.self, forKey: .wheelsysPlateCanonical)
        self.wheelsysEntityVerifiedAt = try container.decodeIfPresent(Date.self, forKey: .wheelsysEntityVerifiedAt)
        self.wheelsysEntitySyncStatus = try container.decodeIfPresent(String.self, forKey: .wheelsysEntitySyncStatus)
        self.wheelsysNtrEntityId = try container.decodeIfPresent(Int.self, forKey: .wheelsysNtrEntityId)
        self.wheelsysNtrDocNo = try container.decodeIfPresent(String.self, forKey: .wheelsysNtrDocNo)
        self.wheelsysNtrStatus = try container.decodeIfPresent(String.self, forKey: .wheelsysNtrStatus)
        self.wheelsysNtrSyncStatus = try container.decodeIfPresent(String.self, forKey: .wheelsysNtrSyncStatus)
        self.wheelsysNtrCreatedByUserId = try container.decodeIfPresent(String.self, forKey: .wheelsysNtrCreatedByUserId)
        self.wheelsysNtrCreatedByUserName = try container.decodeIfPresent(String.self, forKey: .wheelsysNtrCreatedByUserName)
        self.wheelsysNtrStartedAt = try container.decodeIfPresent(Date.self, forKey: .wheelsysNtrStartedAt)
        self.wheelsysNtrStartKm = try container.decodeIfPresent(Int.self, forKey: .wheelsysNtrStartKm)
        self.wheelsysNtrStartFuel = try container.decodeIfPresent(Int.self, forKey: .wheelsysNtrStartFuel)
        self.wheelsysNtrClosedByUserId = try container.decodeIfPresent(String.self, forKey: .wheelsysNtrClosedByUserId)
        self.wheelsysNtrClosedByUserName = try container.decodeIfPresent(String.self, forKey: .wheelsysNtrClosedByUserName)
        self.wheelsysNtrClosedAt = try container.decodeIfPresent(Date.self, forKey: .wheelsysNtrClosedAt)
        self.wheelsysNtrCloseKm = try container.decodeIfPresent(Int.self, forKey: .wheelsysNtrCloseKm)
        self.wheelsysNtrCloseFuel = try container.decodeIfPresent(Int.self, forKey: .wheelsysNtrCloseFuel)
        self.wheelsysNtrMilesTravelled = try container.decodeIfPresent(Int.self, forKey: .wheelsysNtrMilesTravelled)
        self.wheelsysNtrFuelUsed = try container.decodeIfPresent(Int.self, forKey: .wheelsysNtrFuelUsed)
        self.wheelsysNtrLastSyncError = try container.decodeIfPresent(String.self, forKey: .wheelsysNtrLastSyncError)
        self.wheelsysNtrHistory = try container.decodeIfPresent([WheelSysNTRHistoryEntry].self, forKey: .wheelsysNtrHistory) ?? []
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(plaka, forKey: .plaka)
        try container.encode(marka, forKey: .marka)
        try container.encode(model, forKey: .model)
        try container.encodeIfPresent(vin, forKey: .vin)
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
        try container.encode(washingRecords, forKey: .washingRecords)
        try container.encode(franchiseId, forKey: .franchiseId)
        try container.encodeIfPresent(garageBranchId, forKey: .garageBranchId)
        try container.encode(isDeleted, forKey: .isDeleted)
        try container.encodeIfPresent(deletedAt, forKey: .deletedAt)
        try container.encodeIfPresent(deletedBy, forKey: .deletedBy)
        try container.encodeIfPresent(wheelsysVehicleId, forKey: .wheelsysVehicleId)
        try container.encodeIfPresent(wheelsysRentalEntityId, forKey: .wheelsysRentalEntityId)
        try container.encodeIfPresent(wheelsysPlateCanonical, forKey: .wheelsysPlateCanonical)
        try container.encodeIfPresent(wheelsysEntityVerifiedAt, forKey: .wheelsysEntityVerifiedAt)
        try container.encodeIfPresent(wheelsysEntitySyncStatus, forKey: .wheelsysEntitySyncStatus)
        try container.encodeIfPresent(wheelsysNtrEntityId, forKey: .wheelsysNtrEntityId)
        try container.encodeIfPresent(wheelsysNtrDocNo, forKey: .wheelsysNtrDocNo)
        try container.encodeIfPresent(wheelsysNtrStatus, forKey: .wheelsysNtrStatus)
        try container.encodeIfPresent(wheelsysNtrSyncStatus, forKey: .wheelsysNtrSyncStatus)
        try container.encodeIfPresent(wheelsysNtrCreatedByUserId, forKey: .wheelsysNtrCreatedByUserId)
        try container.encodeIfPresent(wheelsysNtrCreatedByUserName, forKey: .wheelsysNtrCreatedByUserName)
        try container.encodeIfPresent(wheelsysNtrStartedAt, forKey: .wheelsysNtrStartedAt)
        try container.encodeIfPresent(wheelsysNtrStartKm, forKey: .wheelsysNtrStartKm)
        try container.encodeIfPresent(wheelsysNtrStartFuel, forKey: .wheelsysNtrStartFuel)
        try container.encodeIfPresent(wheelsysNtrClosedByUserId, forKey: .wheelsysNtrClosedByUserId)
        try container.encodeIfPresent(wheelsysNtrClosedByUserName, forKey: .wheelsysNtrClosedByUserName)
        try container.encodeIfPresent(wheelsysNtrClosedAt, forKey: .wheelsysNtrClosedAt)
        try container.encodeIfPresent(wheelsysNtrCloseKm, forKey: .wheelsysNtrCloseKm)
        try container.encodeIfPresent(wheelsysNtrCloseFuel, forKey: .wheelsysNtrCloseFuel)
        try container.encodeIfPresent(wheelsysNtrMilesTravelled, forKey: .wheelsysNtrMilesTravelled)
        try container.encodeIfPresent(wheelsysNtrFuelUsed, forKey: .wheelsysNtrFuelUsed)
        try container.encodeIfPresent(wheelsysNtrLastSyncError, forKey: .wheelsysNtrLastSyncError)
        if !wheelsysNtrHistory.isEmpty {
            try container.encode(wheelsysNtrHistory, forKey: .wheelsysNtrHistory)
        }
    }
    
    init(plaka: String, marka: String, model: String, kategori: String = "", vin: String? = nil, vignetteVar: Bool = false, spareKeyCount: Int = 0, headDocumentURL: String? = nil, createdBy: String? = nil, assistantCompanyName: String? = nil, assistantCompanyPhone: String? = nil, garageBranchId: String? = nil) {
        self.plaka = plaka
        self.marka = marka
        self.model = model
        let v = vin?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.vin = (v?.isEmpty == false) ? v : nil
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
        self.washingRecords = []
        self.wheelsysNtrHistory = []
        self.garageBranchId = garageBranchId
        self.isDeleted = false
    }
    
    var plakaFormatli: String {
        if franchiseId.uppercased() == "TR" {
            return TurkishPlateFormats.formatForDisplay(plaka)
        }
        
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
