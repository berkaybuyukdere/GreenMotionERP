import Foundation

struct ServisFirma: Identifiable, Codable {
    var id = UUID()
    var ad: String
    var telefon: String
    var email: String
    var adres: String
    var notlar: String
    var kayitTarihi: Date
    
    init(ad: String, telefon: String = "", email: String = "", adres: String = "", notlar: String = "") {
        self.ad = ad
        self.telefon = telefon
        self.email = email
        self.adres = adres
        self.notlar = notlar
        self.kayitTarihi = Date()
    }
}
