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
    case exitYapildi = "Exit Yapıldı"
    case shuttlePickup = "Shuttle Pickup"
    case officeOperation = "Office Operation"
    case officeOperationSilindi = "Office Operation Deleted"
    case checkInKaydedildi = "Check In Kaydedildi"
    case wheelsysNtrOpen = "WheelSys NTR Opened"
    case wheelsysNtrClose = "WheelSys NTR Closed"
    case wheelsysPrecheckin = "WheelSys Pre-check-in"
    case wheelsysCheckinSync = "WheelSys Check-in Sync"
    case wheelsysNoteSaved = "WheelSys Note Saved"
    case wheelsysNoteDeleted = "WheelSys Note Deleted"
    case wheelsysVehicleAssigned = "WheelSys Vehicle Assigned"
    case wheelsysVehicleRemoved = "WheelSys Vehicle Removed"
    case wheelsysVehicleChanged = "WheelSys Vehicle Changed"
    
    var icon: String {
        switch self {
        case .aracEklendi: return "car.fill"
        case .aracSilindi: return "trash.fill"
        case .hasarEklendi: return "exclamationmark.triangle.fill"
        case .hasarSilindi: return "trash.fill"
        case .hasarGuncellendi: return "pencil.circle.fill"
        case .servisEklendi: return "wrench.and.screwdriver.fill"
        case .iadeYapildi: return "checkmark.shield.fill"
        case .exitYapildi: return "arrow.right.circle.fill"
        case .shuttlePickup: return "bus.fill"
        case .officeOperation: return "briefcase.fill"
        case .officeOperationSilindi: return "trash.fill"
        case .checkInKaydedildi: return "arrow.down.circle.fill"
        case .wheelsysNtrOpen: return "wrench.and.screwdriver"
        case .wheelsysNtrClose: return "checkmark.circle.fill"
        case .wheelsysPrecheckin: return "checkmark.seal.fill"
        case .wheelsysCheckinSync: return "arrow.triangle.2.circlepath"
        case .wheelsysNoteSaved, .wheelsysNoteDeleted: return "note.text"
        case .wheelsysVehicleAssigned, .wheelsysVehicleChanged: return "car.fill"
        case .wheelsysVehicleRemoved: return "car.slash.fill"
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
        case .exitYapildi: return .teal
        case .shuttlePickup: return .cyan
        case .officeOperation: return .indigo
        case .officeOperationSilindi: return .red
        case .checkInKaydedildi: return .green
        case .wheelsysNtrOpen: return .orange
        case .wheelsysNtrClose: return .green
        case .wheelsysPrecheckin: return .teal
        case .wheelsysCheckinSync: return .blue
        case .wheelsysNoteSaved: return .indigo
        case .wheelsysNoteDeleted: return .red
        case .wheelsysVehicleAssigned, .wheelsysVehicleChanged: return .green
        case .wheelsysVehicleRemoved: return .orange
        }
    }
    
    var renk: Color {
        return self.color
    }
    
    var englishDisplayName: String {
        switch self {
        case .aracEklendi: return "Vehicle Added".localized
        case .aracSilindi: return "Vehicle Deleted".localized
        case .hasarEklendi: return "Damage Added".localized
        case .hasarSilindi: return "Damage Deleted".localized
        case .hasarGuncellendi: return "Damage Updated".localized
        case .servisEklendi: return "Service Added".localized
        case .iadeYapildi: return "Return Completed".localized
        case .exitYapildi: return "Check Out Completed".localized
        case .shuttlePickup: return "Shuttle Pickup".localized
        case .officeOperation: return "Office Operation".localized
        case .officeOperationSilindi: return "Office Operation Deleted".localized
        case .checkInKaydedildi: return "Check In Saved".localized
        case .wheelsysNtrOpen: return "wheelsys_ntr.activity_open_title".localized
        case .wheelsysNtrClose: return "wheelsys_ntr.activity_close_title".localized
        case .wheelsysPrecheckin: return "wheelsys.activity.precheckin_title".localized
        case .wheelsysCheckinSync: return "wheelsys.activity.checkin_sync_title".localized
        case .wheelsysNoteSaved: return "wheelsys.activity.note_saved_title".localized
        case .wheelsysNoteDeleted: return "wheelsys.activity.note_deleted_title".localized
        case .wheelsysVehicleAssigned: return "wheelsys.activity.vehicle_assigned_title".localized
        case .wheelsysVehicleRemoved: return "wheelsys.activity.vehicle_removed_title".localized
        case .wheelsysVehicleChanged: return "wheelsys.activity.vehicle_changed_title".localized
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
    var franchiseId: String = "CH" // Franchise ID for data isolation
    
    enum CodingKeys: String, CodingKey {
        case id, tip, aciklama, tarih, aracPlaka, detayliAciklama, kullaniciAdi, kullaniciEmail, officeOperationId, franchiseId
    }
    
    init(tip: ActivityType, aciklama: String, tarih: Date, aracPlaka: String? = nil, detayliAciklama: String? = nil, kullaniciAdi: String? = nil, kullaniciEmail: String? = nil, officeOperationId: UUID? = nil, franchiseId: String = "CH") {
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
        self.franchiseId = (try container.decodeIfPresent(String.self, forKey: .franchiseId) ?? "CH").uppercased()
    }
    
    var localizedDescription: String {
        PersistedLabelLocalizer.localizeActivityDescription(self)
    }
}
