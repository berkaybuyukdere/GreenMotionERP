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
    var spareKeyCount: Int
    var headDocumentURL: String?
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(UUID.self, forKey: .id)
        self.plaka = try container.decode(String.self, forKey: .plaka)
        self.marka = try container.decode(String.self, forKey: .marka)
        self.model = try container.decode(String.self, forKey: .model)
        self.kategori = try container.decode(String.self, forKey: .kategori)
        self.vignetteVar = try container.decode(Bool.self, forKey: .vignetteVar)
        self.kayitTarihi = try container.decode(Date.self, forKey: .kayitTarihi)
        self.hasarKayitlari = try container.decode([HasarKaydi].self, forKey: .hasarKayitlari)
        self.qrCode = try container.decode(String.self, forKey: .qrCode)
        self.spareKeyCount = (try? container.decode(Int.self, forKey: .spareKeyCount)) ?? 0
        self.headDocumentURL = try? container.decode(String.self, forKey: .headDocumentURL)
    }
    
    init(plaka: String, marka: String, model: String, kategori: String = "A", vignetteVar: Bool = false, spareKeyCount: Int = 0, headDocumentURL: String? = nil) {
        self.plaka = plaka
        self.marka = marka
        self.model = model
        self.kategori = kategori
        self.vignetteVar = vignetteVar
        self.kayitTarihi = Date()
        self.hasarKayitlari = []
        self.qrCode = plaka
        self.spareKeyCount = spareKeyCount
        self.headDocumentURL = headDocumentURL
    }
    
    var plakaFormatli: String {
        guard plaka.count >= 2 else { return plaka }
        
        let cleanPlaka = plaka.replacingOccurrences(of: " ", with: "").uppercased()
        
        var result = ""
        var digitStart = -1
        
        for (index, char) in cleanPlaka.enumerated() {
            if char.isNumber && digitStart == -1 {
                digitStart = index
            }
            result.append(char)
        }
        
        if digitStart > 0 && digitStart < cleanPlaka.count {
            let firstPart = String(cleanPlaka.prefix(digitStart))
            let secondPart = String(cleanPlaka.suffix(from: cleanPlaka.index(cleanPlaka.startIndex, offsetBy: digitStart)))
            return "\(firstPart) \(secondPart)"
        }
        
        return cleanPlaka
    }
}
