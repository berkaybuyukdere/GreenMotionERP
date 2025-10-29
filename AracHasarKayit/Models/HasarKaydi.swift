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
        case .inProgress: return "In Progress"
        case .done: return "Done"
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
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(UUID.self, forKey: .id)
        // Handle missing fields with defaults for backward compatibility
        self.aracId = try container.decodeIfPresent(UUID.self, forKey: .aracId) ?? UUID()
        self.aracPlaka = try container.decodeIfPresent(String.self, forKey: .aracPlaka) ?? ""
        self.tarih = try container.decode(Date.self, forKey: .tarih)
        self.handoverTarihi = try container.decode(Date.self, forKey: .handoverTarihi)
        self.resKodu = try container.decode(String.self, forKey: .resKodu)
        self.km = try container.decode(Int.self, forKey: .km)
        self.fotograflar = try container.decode([String].self, forKey: .fotograflar)
        self.durum = (try? container.decode(HasarDurum.self, forKey: .durum)) ?? .inProgress
        self.notlar = try container.decodeIfPresent(String.self, forKey: .notlar) ?? ""
        self.status = (try? container.decode(HasarStatus.self, forKey: .status)) ?? .completed
    }
    
    init(aracId: UUID, aracPlaka: String, tarih: Date, handoverTarihi: Date, resKodu: String, km: Int, fotograflar: [String] = [], durum: HasarDurum = .inProgress, notlar: String = "", status: HasarStatus = .completed) {
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
    }
}
