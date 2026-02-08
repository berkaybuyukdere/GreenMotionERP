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
    case officeOperation = "Office Operation"
    case officeOperationSilindi = "Office Operation Deleted"
    
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
        case .officeOperation: return "briefcase.fill"
        case .officeOperationSilindi: return "trash.fill"
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
        case .officeOperation: return .indigo
        case .officeOperationSilindi: return .red
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
        case .officeOperation: return "Office Operation"
        case .officeOperationSilindi: return "Office Operation Deleted"
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
    var officeOperationId: UUID? // For navigation to office operation detail
    var franchiseId: String = "ch" // Franchise ID for data isolation
    
    enum CodingKeys: String, CodingKey {
        case id, tip, aciklama, tarih, aracPlaka, detayliAciklama, kullaniciAdi, kullaniciEmail, officeOperationId, franchiseId
    }
    
    init(tip: ActivityType, aciklama: String, tarih: Date, aracPlaka: String? = nil, detayliAciklama: String? = nil, kullaniciAdi: String? = nil, kullaniciEmail: String? = nil, officeOperationId: UUID? = nil, franchiseId: String = "ch") {
        self.tip = tip
        self.aciklama = aciklama
        self.tarih = tarih
        self.aracPlaka = aracPlaka
        self.detayliAciklama = detayliAciklama
        self.kullaniciAdi = kullaniciAdi
        self.kullaniciEmail = kullaniciEmail
        self.officeOperationId = officeOperationId
        self.franchiseId = franchiseId
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = (try? container.decode(UUID.self, forKey: .id)) ?? UUID()
        self.tip = try container.decode(ActivityType.self, forKey: .tip)
        self.aciklama = try container.decode(String.self, forKey: .aciklama)
        self.tarih = try container.decode(Date.self, forKey: .tarih)
        self.aracPlaka = try container.decodeIfPresent(String.self, forKey: .aracPlaka)
        self.detayliAciklama = try container.decodeIfPresent(String.self, forKey: .detayliAciklama)
        self.kullaniciAdi = try container.decodeIfPresent(String.self, forKey: .kullaniciAdi)
        self.kullaniciEmail = try container.decodeIfPresent(String.self, forKey: .kullaniciEmail)
        self.officeOperationId = try container.decodeIfPresent(UUID.self, forKey: .officeOperationId)
        self.franchiseId = try container.decodeIfPresent(String.self, forKey: .franchiseId) ?? "ch"
    }
}
