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
    
    init(id: UUID = UUID(), aracId: UUID, servisTuru: String, aciklama: String, tarih: Date = Date(), ucret: Double = 0, teslimTarihi: Date? = nil, servisNedenleri: [String] = [], durum: String = "Serviste") {
        self.id = id
        self.aracId = aracId
        self.servisTuru = servisTuru
        self.aciklama = aciklama
        self.tarih = tarih
        self.ucret = ucret
        self.teslimTarihi = teslimTarihi
        self.servisNedenleri = servisNedenleri
        self.durum = durum
    }
}
