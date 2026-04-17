import Foundation

enum HasarDurum: String, Codable, CaseIterable {
    case inProgress = "In Progress"
    case done = "Done"
}

enum HasarStatus: String, Codable {
    case inProgress = "In Progress"
    case completed = "Completed"
}

extension HasarDurum {
    var displayTitle: String {
        switch self {
        case .inProgress: return "In Progress".localized
        case .done: return "Done".localized
        }
    }
}

struct HasarKaydi: Identifiable, Codable, Equatable, Hashable {
    var id = UUID()
    var aracId: UUID
    var aracPlaka: String
    var tarih: Date
    var handoverTarihi: Date
    var resKodu: String
    var km: Int
    var fotograflar: [String]
    var durum: HasarDurum
    var notlar: String
    var status: HasarStatus
    var createdBy: String?
    var franchiseId: String = "CH"
    var damageZone: String? // CarDamageZone.rawValue — optional for backward compatibility
    var isConditionForm: Bool?
    var conditionRegionId: String?
    var conditionPointX: Double?
    var conditionPointY: Double?
    var damageType: String?
    var damageSeverity: String?
    var markerNumber: Int?
    var conditionViewBlockId: String? // which VehicleViewBlock the condition marker belongs to

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = (try? container.decode(UUID.self, forKey: .id)) ?? UUID()
        self.aracId = try container.decodeIfPresent(UUID.self, forKey: .aracId) ?? UUID()
        self.aracPlaka = try container.decodeIfPresent(String.self, forKey: .aracPlaka) ?? ""
        self.tarih = (try? container.decode(Date.self, forKey: .tarih)) ?? Date(timeIntervalSince1970: 0)
        self.handoverTarihi = (try? container.decode(Date.self, forKey: .handoverTarihi)) ?? self.tarih
        self.resKodu = try container.decodeIfPresent(String.self, forKey: .resKodu) ?? ""
        if let kmInt = try? container.decode(Int.self, forKey: .km) {
            self.km = kmInt
        } else if let kmString = try? container.decode(String.self, forKey: .km),
                  let kmParsed = Int(kmString) {
            self.km = kmParsed
        } else {
            self.km = 0
        }
        self.fotograflar = (try? container.decode([String].self, forKey: .fotograflar)) ?? []
        self.durum = (try? container.decode(HasarDurum.self, forKey: .durum)) ?? .inProgress
        self.notlar = try container.decodeIfPresent(String.self, forKey: .notlar) ?? ""
        self.status = (try? container.decode(HasarStatus.self, forKey: .status)) ?? .completed
        self.createdBy = try container.decodeIfPresent(String.self, forKey: .createdBy)
        self.franchiseId = (try container.decodeIfPresent(String.self, forKey: .franchiseId) ?? "CH").uppercased()
        self.damageZone = try container.decodeIfPresent(String.self, forKey: .damageZone)
        self.isConditionForm = try container.decodeIfPresent(Bool.self, forKey: .isConditionForm)
        self.conditionRegionId = try container.decodeIfPresent(String.self, forKey: .conditionRegionId)
        self.conditionPointX = try container.decodeIfPresent(Double.self, forKey: .conditionPointX)
        self.conditionPointY = try container.decodeIfPresent(Double.self, forKey: .conditionPointY)
        self.damageType = try container.decodeIfPresent(String.self, forKey: .damageType)
        self.damageSeverity = try container.decodeIfPresent(String.self, forKey: .damageSeverity)
        self.markerNumber = try container.decodeIfPresent(Int.self, forKey: .markerNumber)
        self.conditionViewBlockId = try container.decodeIfPresent(String.self, forKey: .conditionViewBlockId)
    }
    
    init(aracId: UUID, aracPlaka: String, tarih: Date, handoverTarihi: Date, resKodu: String, km: Int,
         fotograflar: [String] = [], durum: HasarDurum = .inProgress, notlar: String = "",
         status: HasarStatus = .completed, createdBy: String? = nil, franchiseId: String = "CH",
         damageZone: String? = nil, isConditionForm: Bool? = nil, conditionRegionId: String? = nil,
         conditionPointX: Double? = nil, conditionPointY: Double? = nil, damageType: String? = nil,
         damageSeverity: String? = nil, markerNumber: Int? = nil, conditionViewBlockId: String? = nil) {
        self.aracId = aracId
        self.aracPlaka = aracPlaka
        self.tarih = tarih
        self.handoverTarihi = handoverTarihi
        self.resKodu = resKodu
        self.km = km
        self.fotograflar = fotograflar
        self.durum = durum
        self.notlar = notlar
        self.status = status
        self.createdBy = createdBy
        self.franchiseId = franchiseId.uppercased()
        self.damageZone = damageZone
        self.isConditionForm = isConditionForm
        self.conditionRegionId = conditionRegionId
        self.conditionPointX = conditionPointX
        self.conditionPointY = conditionPointY
        self.damageType = damageType
        self.damageSeverity = damageSeverity
        self.markerNumber = markerNumber
        self.conditionViewBlockId = conditionViewBlockId
    }
}
