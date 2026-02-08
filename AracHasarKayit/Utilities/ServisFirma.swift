import Foundation

struct ServisFirma: Identifiable, Codable {
    var id = UUID()
    var ad: String
    var telefon: String
    var email: String
    var adres: String
    var notlar: String
    var kayitTarihi: Date
    var franchiseId: String = "ch" // Franchise ID for data isolation
    
    enum CodingKeys: String, CodingKey {
        case id, ad, telefon, email, adres, notlar, kayitTarihi, franchiseId
    }
    
    init(ad: String, telefon: String = "", email: String = "", adres: String = "", notlar: String = "", franchiseId: String = "ch") {
        self.ad = ad
        self.telefon = telefon
        self.email = email
        self.adres = adres
        self.notlar = notlar
        self.kayitTarihi = Date()
        self.franchiseId = franchiseId
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = (try? container.decode(UUID.self, forKey: .id)) ?? UUID()
        self.ad = try container.decode(String.self, forKey: .ad)
        self.telefon = (try? container.decode(String.self, forKey: .telefon)) ?? ""
        self.email = (try? container.decode(String.self, forKey: .email)) ?? ""
        self.adres = (try? container.decode(String.self, forKey: .adres)) ?? ""
        self.notlar = (try? container.decode(String.self, forKey: .notlar)) ?? ""
        self.kayitTarihi = (try? container.decode(Date.self, forKey: .kayitTarihi)) ?? Date()
        self.franchiseId = try container.decodeIfPresent(String.self, forKey: .franchiseId) ?? "ch"
    }
}
