import Foundation

enum ExitStatus: String, Codable {
    case inProgress = "In Progress"
    case completed = "Completed"
}

struct ExitIslemi: Identifiable, Codable {
    var id = UUID()
    var aracId: UUID
    var aracPlaka: String
    var exitTarihi: Date // Sadece PDF için kullanılan tarih
    var createdAt: Date // İşlemin gerçek oluşturulma tarihi (filtreleme için)
    var fotograflar: [String]
    var notlar: String
    var resKodu: String
    var status: ExitStatus
    var createdBy: String? // User ID who created this record
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(UUID.self, forKey: .id)
        self.aracId = try container.decode(UUID.self, forKey: .aracId)
        self.aracPlaka = try container.decode(String.self, forKey: .aracPlaka)
        self.exitTarihi = try container.decode(Date.self, forKey: .exitTarihi)
        // Backward compatibility: Eğer createdAt yoksa exitTarihi kullan
        let decodedCreatedAt = try? container.decode(Date.self, forKey: .createdAt)
        self.createdAt = decodedCreatedAt ?? self.exitTarihi
        self.fotograflar = try container.decode([String].self, forKey: .fotograflar)
        self.notlar = (try? container.decode(String.self, forKey: .notlar)) ?? ""
        self.resKodu = (try? container.decode(String.self, forKey: .resKodu)) ?? ""
        self.status = (try? container.decode(ExitStatus.self, forKey: .status)) ?? .completed
        self.createdBy = try container.decodeIfPresent(String.self, forKey: .createdBy)
    }
    
    init(aracId: UUID, aracPlaka: String, exitTarihi: Date = Date(), fotograflar: [String] = [], notlar: String = "", resKodu: String = "", status: ExitStatus = .completed, createdAt: Date? = nil, createdBy: String? = nil) {
        self.aracId = aracId
        self.aracPlaka = aracPlaka
        self.exitTarihi = exitTarihi
        // createdAt belirtilmediyse şu anki tarihi kullan (gerçek işlem tarihi)
        self.createdAt = createdAt ?? Date()
        self.fotograflar = fotograflar
        self.notlar = notlar
        self.resKodu = resKodu
        self.status = status
        self.createdBy = createdBy
    }
}

