import Foundation

struct ServisKaydi: Identifiable, Codable {
    var id = UUID()
    var aracId: UUID
    var servisTuru: String
    var aciklama: String
    var tarih: Date
    var ucret: Double
    
    init(aracId: UUID, servisTuru: String, aciklama: String, tarih: Date = Date(), ucret: Double = 0) {
        self.aracId = aracId
        self.servisTuru = servisTuru
        self.aciklama = aciklama
        self.tarih = tarih
        self.ucret = ucret
    }
}
