import Foundation

struct HasarKaydi: Identifiable, Codable {
    var id = UUID()
    var tarih: Date
    var handoverTarihi: Date // İlk fotoğraf tarihi
    var resKodu: String // YENİ: RES-XXXXX formatında
    var km: Int // YENİ: Araç KM'si hasar anında
    var fotograflar: [String]
    
    init(tarih: Date, handoverTarihi: Date, resKodu: String, km: Int, fotograflar: [String] = []) {
        self.tarih = tarih
        self.handoverTarihi = handoverTarihi
        self.resKodu = resKodu
        self.km = km
        self.fotograflar = fotograflar
    }
}
