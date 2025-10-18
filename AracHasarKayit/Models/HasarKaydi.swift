import Foundation

enum HasarDurum: String, Codable, CaseIterable {
    case inProgress = "In Progress"
    case done = "Done"
}

extension HasarDurum {
    var displayTitle: String {
        switch self {
        case .inProgress: return "In Progress"
        case .done: return "Done"
        }
    }
}

struct HasarKaydi: Identifiable, Codable, Equatable {
    var id = UUID()
    var tarih: Date
    var handoverTarihi: Date
    var resKodu: String
    var km: Int
    var fotograflar: [String]
    var durum: HasarDurum
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(UUID.self, forKey: .id)
        self.tarih = try container.decode(Date.self, forKey: .tarih)
        self.handoverTarihi = try container.decode(Date.self, forKey: .handoverTarihi)
        self.resKodu = try container.decode(String.self, forKey: .resKodu)
        self.km = try container.decode(Int.self, forKey: .km)
        self.fotograflar = try container.decode([String].self, forKey: .fotograflar)
        self.durum = (try? container.decode(HasarDurum.self, forKey: .durum)) ?? .inProgress
    }
    
    init(tarih: Date, handoverTarihi: Date, resKodu: String, km: Int, fotograflar: [String] = [], durum: HasarDurum = .inProgress) {
        self.tarih = tarih
        self.handoverTarihi = handoverTarihi
        self.resKodu = resKodu
        self.km = km
        self.fotograflar = fotograflar
        self.durum = durum
    }
}
