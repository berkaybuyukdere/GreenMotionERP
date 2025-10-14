import Foundation

struct ServisFirmasi: Identifiable, Codable {
    var id = UUID()
    var ad: String
    var telefon: String
    var adres: String
    var email: String
    var notlar: String
    var kayitTarihi: Date
    
    init(ad: String, telefon: String = "", adres: String = "", email: String = "", notlar: String = "") {
        self.ad = ad
        self.telefon = telefon
        self.adres = adres
        self.email = email
        self.notlar = notlar
        self.kayitTarihi = Date()
    }
}
