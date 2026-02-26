import Foundation

struct ServisKaydi: Identifiable, Codable {
    var id: UUID
    var aracId: UUID
    var servisTuru: String
    var aciklama: String
    var tarih: Date
    var ucret: Double
    var teslimTarihi: Date?
    var servisNedenleri: [String]
    var durum: String
    var franchiseId: String = "CH" // Franchise ID for data isolation
    
    enum CodingKeys: String, CodingKey {
        case id, aracId, servisTuru, aciklama, tarih, ucret, teslimTarihi, servisNedenleri, durum, franchiseId
    }
    
    init(id: UUID = UUID(), aracId: UUID, servisTuru: String, aciklama: String, tarih: Date = Date(), ucret: Double = 0, teslimTarihi: Date? = nil, servisNedenleri: [String] = [], durum: String = "Serviste", franchiseId: String = "CH") {
        self.id = id
        self.aracId = aracId
        self.servisTuru = servisTuru
        self.aciklama = aciklama
        self.tarih = tarih
        self.ucret = ucret
        self.teslimTarihi = teslimTarihi
        self.servisNedenleri = servisNedenleri
        self.durum = durum
        self.franchiseId = franchiseId
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = (try? container.decode(UUID.self, forKey: .id)) ?? UUID()
        self.aracId = try container.decode(UUID.self, forKey: .aracId)
        self.servisTuru = try container.decode(String.self, forKey: .servisTuru)
        self.aciklama = try container.decode(String.self, forKey: .aciklama)
        self.tarih = try container.decode(Date.self, forKey: .tarih)
        self.ucret = (try? container.decode(Double.self, forKey: .ucret)) ?? 0
        self.teslimTarihi = try container.decodeIfPresent(Date.self, forKey: .teslimTarihi)
        self.servisNedenleri = (try? container.decode([String].self, forKey: .servisNedenleri)) ?? []
        self.durum = (try? container.decode(String.self, forKey: .durum)) ?? "Serviste"
        self.franchiseId = (try container.decodeIfPresent(String.self, forKey: .franchiseId) ?? "CH").uppercased()
    }
}
