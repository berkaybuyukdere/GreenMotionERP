import Foundation

struct Arac: Identifiable, Codable {
    var id = UUID()
    var plaka: String
    var marka: String
    var model: String
    var kategori: String
    var vignetteVar: Bool
    var kayitTarihi: Date
    var hasarKayitlari: [HasarKaydi]
    var qrCode: String
    
    init(plaka: String, marka: String, model: String, kategori: String = "A", vignetteVar: Bool = false) {
        self.plaka = plaka
        self.marka = marka
        self.model = model
        self.kategori = kategori
        self.vignetteVar = vignetteVar
        self.kayitTarihi = Date()
        self.hasarKayitlari = []
        self.qrCode = plaka
    }
    
    var plakaFormatli: String {
        let temiz = plaka.replacingOccurrences(of: " ", with: "").uppercased()
        if temiz.count >= 3 {
            let kantonIndex = temiz.index(temiz.startIndex, offsetBy: 2)
            let kanton = String(temiz[..<kantonIndex])
            let numara = String(temiz[kantonIndex...])
            return "\(kanton) \(numara)"
        }
        return plaka.uppercased()
    }
}
