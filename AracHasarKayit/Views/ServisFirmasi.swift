import Foundation

struct ServisFirmasi: Identifiable, Codable {
    var id = UUID()
    var ad: String
    var telefon: String
    var adres: String
    var email: String
    var notlar: String
    var kayitTarihi: Date
    var franchiseId: String = "CH" // Franchise ID for data isolation
    
    enum CodingKeys: String, CodingKey {
        case id, ad, telefon, adres, email, notlar, kayitTarihi, franchiseId
    }
    
    init(ad: String, telefon: String = "", adres: String = "", email: String = "", notlar: String = "", franchiseId: String = "CH") {
        self.ad = ad
        self.telefon = telefon
        self.adres = adres
        self.email = email
        self.notlar = notlar
        self.kayitTarihi = Date()
        self.franchiseId = franchiseId
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = (try? container.decode(UUID.self, forKey: .id)) ?? UUID()
        self.ad = try container.decode(String.self, forKey: .ad)
        self.telefon = (try? container.decode(String.self, forKey: .telefon)) ?? ""
        self.adres = (try? container.decode(String.self, forKey: .adres)) ?? ""
        self.email = (try? container.decode(String.self, forKey: .email)) ?? ""
        self.notlar = (try? container.decode(String.self, forKey: .notlar)) ?? ""
        self.kayitTarihi = (try? container.decode(Date.self, forKey: .kayitTarihi)) ?? Date()
        self.franchiseId = (try container.decodeIfPresent(String.self, forKey: .franchiseId) ?? "CH").uppercased()
    }
}
