import Foundation

enum ActivityType: String, Codable {
    case aracEklendi = "Araç Eklendi"
    case aracSilindi = "Araç Silindi"
    case hasarEklendi = "Hasar Eklendi"
    case hasarSilindi = "Hasar Silindi"
    case hasarGuncellendi = "Hasar Güncellendi"
    case servisEklendi = "Servis Eklendi"
    case iadeYapildi = "İade Yapıldı"
    
    var icon: String {
        switch self {
        case .aracEklendi: return "car.fill"
        case .aracSilindi: return "trash.fill"
        case .hasarEklendi: return "exclamationmark.triangle.fill"
        case .hasarSilindi: return "trash.fill"
        case .hasarGuncellendi: return "pencil.circle.fill"
        case .servisEklendi: return "wrench.and.screwdriver.fill"
        case .iadeYapildi: return "checkmark.shield.fill"
        }
    }
    
    var color: String {
        switch self {
        case .aracEklendi: return "green"
        case .aracSilindi: return "red"
        case .hasarEklendi: return "orange"
        case .hasarSilindi: return "red"
        case .hasarGuncellendi: return "blue"
        case .servisEklendi: return "purple"
        case .iadeYapildi: return "blue"
        }
    }
    
    var renk: String {
        return self.color
    }
}

struct Activity: Identifiable, Codable {
    var id = UUID()
    var tip: ActivityType
    var aciklama: String
    var tarih: Date
    var aracPlaka: String?
    var detayliAciklama: String?
    
    init(tip: ActivityType, aciklama: String, tarih: Date, aracPlaka: String? = nil, detayliAciklama: String? = nil) {
        self.tip = tip
        self.aciklama = aciklama
        self.tarih = tarih
        self.aracPlaka = aracPlaka
        self.detayliAciklama = detayliAciklama
    }
}
