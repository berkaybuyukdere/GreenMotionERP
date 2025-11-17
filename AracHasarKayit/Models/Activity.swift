import Foundation
import SwiftUI

enum ActivityType: String, Codable {
    case aracEklendi = "Araç Eklendi"
    case aracSilindi = "Araç Silindi"
    case hasarEklendi = "Hasar Eklendi"
    case hasarSilindi = "Hasar Silindi"
    case hasarGuncellendi = "Hasar Güncellendi"
    case servisEklendi = "Servis Eklendi"
    case iadeYapildi = "İade Yapıldı"
    case shuttlePickup = "Shuttle Pickup"
    
    var icon: String {
        switch self {
        case .aracEklendi: return "car.fill"
        case .aracSilindi: return "trash.fill"
        case .hasarEklendi: return "exclamationmark.triangle.fill"
        case .hasarSilindi: return "trash.fill"
        case .hasarGuncellendi: return "pencil.circle.fill"
        case .servisEklendi: return "wrench.and.screwdriver.fill"
        case .iadeYapildi: return "checkmark.shield.fill"
        case .shuttlePickup: return "bus.fill"
        }
    }
    
    var color: Color {
        switch self {
        case .aracEklendi: return .green
        case .aracSilindi: return .red
        case .hasarEklendi: return .orange
        case .hasarSilindi: return .red
        case .hasarGuncellendi: return .blue
        case .servisEklendi: return .purple
        case .iadeYapildi: return .blue
        case .shuttlePickup: return .cyan
        }
    }
    
    var renk: Color {
        return self.color
    }
    
    var englishDisplayName: String {
        switch self {
        case .aracEklendi: return "Vehicle Added"
        case .aracSilindi: return "Vehicle Deleted"
        case .hasarEklendi: return "Damage Added"
        case .hasarSilindi: return "Damage Deleted"
        case .hasarGuncellendi: return "Damage Updated"
        case .servisEklendi: return "Service Added"
        case .iadeYapildi: return "Return Completed"
        case .shuttlePickup: return "Shuttle Pickup"
        }
    }
}

struct Activity: Identifiable, Codable, Equatable {
    var id = UUID()
    var tip: ActivityType
    var aciklama: String
    var tarih: Date
    var aracPlaka: String?
    var detayliAciklama: String?
    var kullaniciAdi: String?
    var kullaniciEmail: String?
    
    init(tip: ActivityType, aciklama: String, tarih: Date, aracPlaka: String? = nil, detayliAciklama: String? = nil, kullaniciAdi: String? = nil, kullaniciEmail: String? = nil) {
        self.tip = tip
        self.aciklama = aciklama
        self.tarih = tarih
        self.aracPlaka = aracPlaka
        self.detayliAciklama = detayliAciklama
        self.kullaniciAdi = kullaniciAdi
        self.kullaniciEmail = kullaniciEmail
    }
}
